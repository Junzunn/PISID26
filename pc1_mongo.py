from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from uuid import uuid4

import paho.mqtt.client as mqtt
from pymongo import ASCENDING, MongoClient
from pymongo.errors import DuplicateKeyError, OperationFailure

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883
VALIDATION_TIMEOUT = 20
LOOP_INTERVAL = 0.5
RETRY_INTERVAL = 2
BATCH_SIZE = 50
MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"

mongo = MongoClient(MONGO_URI)
mongo_events = mongo["pisid"]["sensor_events"]
MQTT_CLIENT = None
stop_event = threading.Event()
buffer_lock = threading.Lock()


@dataclass
class RuntimeState:
    simulation_id: int | None = None
    current_seq: int = 0
    validation_ok: bool = False
    validation_error: str | None = None
    validation_request_id: str | None = None
    raw_subscribed: bool = False
    simulation_finished: bool = False
    ingest_buffer: deque[dict] = field(default_factory=deque)


STATE = RuntimeState()


RAW_TOPICS = [
    f"pisid_mazemov_{GROUP_ID}",
    f"pisid_mazetemp_{GROUP_ID}",
    f"pisid_mazesound_{GROUP_ID}",
]

STAGE2_TOPIC = f"pisid_pc2_stage2_{GROUP_ID}"
ACK_TOPIC = f"pisid_pc2_ack_{GROUP_ID}"
SIMCHECK_REQ_TOPIC = f"pisid_simcheck_req_{GROUP_ID}"
SIMCHECK_RESP_TOPIC = f"pisid_simcheck_resp_{GROUP_ID}"
GAME_END_TOPIC = f"pisid_game_end_{GROUP_ID}"


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
        [("publish_state", ASCENDING), ("simulation_id", ASCENDING), ("seq", ASCENDING)]
    )


def is_primary() -> bool:
    try:
        return mongo.admin.command("hello").get("isWritablePrimary", False)
    except Exception:
        return False


def set_raw_subscription(enabled: bool) -> None:
    if enabled == STATE.raw_subscribed:
        return

    topics = RAW_TOPICS
    action = MQTT_CLIENT.subscribe if enabled else MQTT_CLIENT.unsubscribe
    for topic in topics:
        if enabled:
            action(topic, qos=1)
        else:
            action(topic)

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
        "publish_state": "pending",
        "last_publish_at": None,
        "ack_result": None,
        "ack_error": None,
    }


def enqueue_raw_event(topic: str, payload: dict) -> None:
    with buffer_lock:
        if STATE.simulation_finished:
            return
        event = build_raw_event(topic, payload)
        STATE.ingest_buffer.append(event)

    print(f"PC1: buffered seq={event['seq']}, {payload}")


def flush_buffer_to_mongo() -> None:
    while not stop_event.is_set():
        if not (STATE.validation_ok and is_primary()):
            time.sleep(LOOP_INTERVAL)
            continue

        while not stop_event.is_set() and STATE.validation_ok and is_primary():
            with buffer_lock:
                if not STATE.ingest_buffer:
                    break
                event = STATE.ingest_buffer[0]

            try:
                mongo_events.insert_one(event)
                print(f"PC1: saved Mongo, seq={event['seq']}, {event['payload']}")
            except DuplicateKeyError:
                print(f"PC1: duplicate seq={event['seq']} already in Mongo, dropping from buffer")
            except Exception as exc:
                print("PC1 flush error:", exc)
                break

            with buffer_lock:
                if STATE.ingest_buffer and STATE.ingest_buffer[0]["event_id"] == event["event_id"]:
                    STATE.ingest_buffer.popleft()

        time.sleep(LOOP_INTERVAL)


def publish_doc(doc: dict) -> None:
    MQTT_CLIENT.publish(
        STAGE2_TOPIC,
        json.dumps(
            {
                "event_id": doc["event_id"],
                "simulation_id": doc["simulation_id"],
                "seq": doc["seq"],
                "topic": doc["topic"],
                "payload": doc["payload"],
            },
            default=str,
        ),
        qos=1,
    )
    mongo_events.update_one({"_id": doc["_id"]}, {"$set": {"last_publish_at": datetime.now()}})


def publish_pending() -> None:
    while not stop_event.is_set():
        if STATE.validation_ok and is_primary():
            cutoff = datetime.now() - timedelta(seconds=RETRY_INTERVAL)
            cursor = (
                mongo_events.find(
                    {
                        "simulation_id": STATE.simulation_id,
                        "publish_state": "pending",
                        "$or": [
                            {"last_publish_at": None},
                            {"last_publish_at": {"$lt": cutoff}},
                        ],
                    }
                )
                .sort("seq", 1)
                .limit(BATCH_SIZE)
            )
            for doc in cursor:
                publish_doc(doc)
        time.sleep(LOOP_INTERVAL)


def wait_validation() -> None:
    STATE.validation_request_id = str(uuid4())
    deadline = time.time() + VALIDATION_TIMEOUT

    while not stop_event.is_set() and not STATE.validation_ok and STATE.validation_error is None:
        if time.time() >= deadline:
            STATE.validation_error = "pc2_no_response"
            return

        MQTT_CLIENT.publish(
            SIMCHECK_REQ_TOPIC,
            json.dumps(
                {
                    "request_id": STATE.validation_request_id,
                    "simulation_id": STATE.simulation_id,
                }
            ),
            qos=1,
        )
        time.sleep(RETRY_INTERVAL)


def handle_simcheck_response(data: dict) -> None:
    if data.get("request_id") != STATE.validation_request_id:
        return

    status = data.get("status")
    if status == "ok":
        STATE.validation_ok = True
        set_raw_subscription(True)
        print(f"PC1: simulation {STATE.simulation_id} validated")
    else:
        STATE.validation_error = status


def handle_ack(data: dict) -> None:
    if int(data.get("simulation_id", -1)) != STATE.simulation_id:
        return

    mongo_events.update_one(
        {
            "simulation_id": STATE.simulation_id,
            "seq": int(data["seq"]),
            "publish_state": "pending",
        },
        {
            "$set": {
                "publish_state": "done" if data.get("result") == "success" else "invalid",
                "ack_result": data.get("result"),
                "ack_error": data.get("error"),
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
        if msg.topic == SIMCHECK_RESP_TOPIC:
            handle_simcheck_response(data)
        elif msg.topic == ACK_TOPIC:
            handle_ack(data)
        elif msg.topic == GAME_END_TOPIC:
            handle_game_end(data)
        elif STATE.validation_ok and msg.topic in RAW_TOPICS:
            enqueue_raw_event(msg.topic, data)
    except Exception as exc:
        print("Erro PC1:", exc)


def on_connect(client, userdata, flags, reason_code, properties) -> None:
    client.subscribe(SIMCHECK_RESP_TOPIC, qos=1)
    client.subscribe(ACK_TOPIC, qos=1)
    client.subscribe(GAME_END_TOPIC, qos=1)

    if STATE.validation_ok and not STATE.simulation_finished:
        set_raw_subscription(True)


def load_last_state_from_mongo() -> None:
    last_doc = mongo_events.find_one({"simulation_id": STATE.simulation_id}, sort=[("seq", -1)])
    STATE.current_seq = last_doc["seq"] if last_doc else 0


def buffer_is_empty() -> bool:
    with buffer_lock:
        return not STATE.ingest_buffer


def pending_count() -> int:
    return mongo_events.count_documents(
        {
            "simulation_id": STATE.simulation_id,
            "publish_state": "pending",
        }
    )


def can_exit() -> bool:
    return STATE.simulation_finished and buffer_is_empty() and pending_count() == 0


def shutdown(flush_thread: threading.Thread, publish_thread: threading.Thread) -> None:
    set_raw_subscription(False)
    stop_event.set()
    flush_thread.join(timeout=2)
    publish_thread.join(timeout=2)
    MQTT_CLIENT.loop_stop()
    MQTT_CLIENT.disconnect()


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

    wait_validation()
    if not STATE.validation_ok:
        MQTT_CLIENT.loop_stop()
        MQTT_CLIENT.disconnect()
        print(f"ERRO: {STATE.validation_error or 'validation_failed'}")
        sys.exit(1)

    flush_thread = threading.Thread(target=flush_buffer_to_mongo, daemon=True)
    publish_thread = threading.Thread(target=publish_pending, daemon=True)
    flush_thread.start()
    publish_thread.start()

    try:
        while not can_exit():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        shutdown(flush_thread, publish_thread)


if __name__ == "__main__":
    main()
