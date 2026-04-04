from __future__ import annotations

import argparse
import json
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta

import paho.mqtt.client as mqtt
from pymongo import ASCENDING, MongoClient
from pymongo.errors import DuplicateKeyError, OperationFailure

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883
LOOP_INTERVAL = 0.5
RETRY_INTERVAL = 2
BATCH_SIZE = 50
MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"

mongo = MongoClient(MONGO_URI)
mongo_events = mongo["pisid"]["sensor_events"]
MQTT_CLIENT = None


@dataclass
class RuntimeState:
    simulation_id: int | None = None
    current_seq: int = 0
    raw_subscribed: bool = False
    simulation_finished: bool = False
    ingest_buffer: deque[dict] = field(default_factory=deque)


STATE = RuntimeState()

RAW_TOPICS = [
    f"pisid_mazemov_{GROUP_ID}",
    f"pisid_mazetemp_{GROUP_ID}",
    f"pisid_mazesound_{GROUP_ID}",
]
BRIDGE_TOPIC = f"pisid_pc_bridge_{GROUP_ID}"


def ensure_indexes() -> None:
    mongo_events.create_index([("event_id", ASCENDING)], unique=True)
    try:
        mongo_events.create_index(
            [("simulation_id", ASCENDING), ("seq", ASCENDING)],
            unique=True,
            partialFilterExpression={"seq": {"$exists": True}},
        )
    except OperationFailure as exc:
        if getattr(exc, "code", None) != 86:
            raise
    mongo_events.create_index(
        [("simulation_id", ASCENDING), ("state", ASCENDING), ("seq", ASCENDING)]
    )


def is_primary() -> bool:
    try:
        return mongo.admin.command("hello").get("isWritablePrimary", False)
    except Exception:
        return False


def publish_bridge(message: dict) -> None:
    MQTT_CLIENT.publish(BRIDGE_TOPIC, json.dumps(message, default=str), qos=1)


def set_raw_subscription(enabled: bool) -> None:
    if enabled == STATE.raw_subscribed:
        return
    for topic in RAW_TOPICS:
        if enabled:
            MQTT_CLIENT.subscribe(topic, qos=1)
        else:
            MQTT_CLIENT.unsubscribe(topic)
    STATE.raw_subscribed = enabled
    print(f"PC1: raw topics {'subscribed' if enabled else 'unsubscribed'}")


def build_raw_event(topic: str, payload: dict) -> dict:
    STATE.current_seq += 1
    seq = STATE.current_seq
    return {
        "event_id": f"{STATE.simulation_id}:{seq}",
        "simulation_id": STATE.simulation_id,
        "seq": seq,
        "topic": topic,
        "payload": payload,
        "received_at": datetime.now(),
        "state": "pending",
        "last_sent_at": None,
        "error": None,
    }


def enqueue_raw_event(topic: str, payload: dict) -> None:
    if STATE.simulation_finished:
        return
    event = build_raw_event(topic, payload)
    STATE.ingest_buffer.append(event)
    print(f"PC1: buffered seq={event['seq']}, {payload}")


def flush_buffer_once() -> None:
    if not is_primary():
        return
    while STATE.ingest_buffer:
        event = STATE.ingest_buffer[0]
        try:
            mongo_events.insert_one(event)
        except DuplicateKeyError:
            print(f"PC1: duplicate seq={event['seq']} already in Mongo, dropping from buffer")
        except Exception as exc:
            print("PC1 flush error:", exc)
            return
        STATE.ingest_buffer.popleft()


def publish_doc(doc: dict) -> None:
    publish_bridge(
        {
            "kind": "event",
            "src": "pc1",
            "event_id": doc["event_id"],
            "simulation_id": doc["simulation_id"],
            "seq": doc["seq"],
            "topic": doc["topic"],
            "payload": doc["payload"],
        }
    )
    mongo_events.update_one({"_id": doc["_id"]}, {"$set": {"last_sent_at": datetime.now()}})


def publish_pending_once() -> None:
    if not is_primary():
        return
    cutoff = datetime.now() - timedelta(seconds=RETRY_INTERVAL)
    cursor = (
        mongo_events.find(
            {
                "simulation_id": STATE.simulation_id,
                "state": "pending",
                "$or": [
                    {"last_sent_at": None},
                    {"last_sent_at": {"$lt": cutoff}},
                ],
            }
        )
        .sort("seq", 1)
        .limit(BATCH_SIZE)
    )
    for doc in cursor:
        publish_doc(doc)


def handle_receipt(data: dict) -> None:
    if int(data.get("simulation_id", -1)) != STATE.simulation_id:
        return
    mongo_events.update_one(
        {
            "event_id": data["event_id"],
            "simulation_id": STATE.simulation_id,
            "seq": int(data["seq"]),
            "state": "pending",
        },
        {
            "$set": {
                "state": data.get("state", "done"),
                "error": data.get("error"),
            }
        },
    )


def handle_game_end(data: dict) -> None:
    if int(data.get("simulation_id", -1)) != STATE.simulation_id:
        return
    STATE.simulation_finished = True
    set_raw_subscription(False)
    print(f"PC1: simulation {STATE.simulation_id} finished, draining buffer and pending events")


def on_message(client, userdata, msg) -> None:
    try:
        data = json.loads(msg.payload.decode())
        if msg.topic == BRIDGE_TOPIC:
            if data.get("src") == "pc1":
                return
            kind = data.get("kind")
            if kind == "receipt":
                handle_receipt(data)
            elif kind == "game_end":
                handle_game_end(data)
        elif msg.topic in RAW_TOPICS and not STATE.simulation_finished:
            enqueue_raw_event(msg.topic, data)
    except Exception as exc:
        print("Erro PC1:", exc)


def on_connect(client, userdata, flags, reason_code, properties) -> None:
    client.subscribe(BRIDGE_TOPIC, qos=1)
    if not STATE.simulation_finished:
        set_raw_subscription(True)


def load_last_state_from_mongo() -> None:
    last_doc = mongo_events.find_one({"simulation_id": STATE.simulation_id}, sort=[("seq", -1)])
    STATE.current_seq = last_doc["seq"] if last_doc else 0


def buffer_is_empty() -> bool:
    return not STATE.ingest_buffer


def pending_count() -> int:
    return mongo_events.count_documents({"simulation_id": STATE.simulation_id, "state": "pending"})


def can_exit() -> bool:
    return STATE.simulation_finished and buffer_is_empty() and pending_count() == 0


def main() -> None:
    global MQTT_CLIENT

    parser = argparse.ArgumentParser()
    parser.add_argument("--simulation-id", type=int, required=True)
    STATE.simulation_id = parser.parse_args().simulation_id

    ensure_indexes()
    load_last_state_from_mongo()

    MQTT_CLIENT = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    MQTT_CLIENT.on_connect = on_connect
    MQTT_CLIENT.on_message = on_message
    MQTT_CLIENT.connect(BROKER, PORT)
    MQTT_CLIENT.loop_start()

    try:
        while not can_exit():
            flush_buffer_once()
            publish_pending_once()
            time.sleep(LOOP_INTERVAL)
    except KeyboardInterrupt:
        pass
    finally:
        set_raw_subscription(False)
        MQTT_CLIENT.loop_stop()
        MQTT_CLIENT.disconnect()


if __name__ == "__main__":
    main()
