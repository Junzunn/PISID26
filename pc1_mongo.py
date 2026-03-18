from __future__ import annotations
import argparse
import json
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import uuid4

import paho.mqtt.client as mqtt
from pymongo import ASCENDING, MongoClient
from pymongo.errors import DuplicateKeyError, OperationFailure

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883
VALIDATION_TIMEOUT = 20
SEC_TRANSPORTE = 0.5
SEC_RETRANSMISSAO = 2
BATCH_SIZE = 50
MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"

mongo = MongoClient(MONGO_URI)
mongo_events = mongo["pisid"]["sensor_events"]
MQTT_CLIENT = None
stop_event = threading.Event()


@dataclass
class RuntimeState:
    simulation_id: int | None = None
    current_seq: int = 0
    validation_ok: bool = False
    validation_error: str | None = None
    validation_request_id: str | None = None
    raw_subscribed: bool = False
    simulation_finished: bool = False


STATE = RuntimeState()


def raw_topics():
    return [
        f"pisid_mazemov_{GROUP_ID}",
        f"pisid_mazetemp_{GROUP_ID}",
        f"pisid_mazesound_{GROUP_ID}",
    ]


def stage2_topic(): return f"pisid_pc2_stage2_{GROUP_ID}"
def ack_topic(): return f"pisid_pc2_ack_{GROUP_ID}"
def simcheck_req_topic(): return f"pisid_simcheck_req_{GROUP_ID}"
def simcheck_resp_topic(): return f"pisid_simcheck_resp_{GROUP_ID}"
def game_end_topic(): return f"pisid_game_end_{GROUP_ID}"


def ensure_indexes():
    mongo_events.create_index([("event_id", ASCENDING)], unique=True)
    try:
        mongo_events.create_index(
            [("simulation_id", ASCENDING), ("seq", ASCENDING)],
            unique=True,
            partialFilterExpression={"seq": {"$exists": True}},
        )
    except OperationFailure as e:
        if getattr(e, "code", None) != 86:
            raise
    mongo_events.create_index([("publish_state", ASCENDING), ("simulation_id", ASCENDING), ("seq", ASCENDING)])


def is_primary():
    try:
        return mongo.admin.command("hello").get("isWritablePrimary", False)
    except Exception:
        return False


def set_raw_subscription(enabled: bool):
    if enabled == STATE.raw_subscribed:
        return
    action = MQTT_CLIENT.subscribe if enabled else MQTT_CLIENT.unsubscribe
    for topic in raw_topics():
        action(topic, qos=1) if enabled else action(topic)
    STATE.raw_subscribed = enabled
    print(f"PC1: raw topics {'subscribed' if enabled else 'unsubscribed'}")


def payload_code(payload):
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)


def is_consecutive_duplicate(topic, payload):
    now = datetime.now()

    last_doc = mongo_events.find_one(
        {
            "simulation_id": STATE.simulation_id,
            "topic": topic,
        },
        sort=[("received_at", -1)],
    )
    if not last_doc:
        return None

    same_payload = payload_code(last_doc["payload"]) == payload_code(payload)
    if not same_payload:
        return None

    if "mazemov" in topic:
        return last_doc

    if "mazetemp" in topic or "mazesound" in topic:
        if (now - last_doc["received_at"]).total_seconds() <= 1:
            return last_doc

    return None


def save_raw_event(topic, payload):
    if STATE.simulation_finished:
        return

    dup_doc = is_consecutive_duplicate(topic, payload)
    if dup_doc:
        print("Bomdia!!!!")
        try:
            mongo_events.insert_one(
                {
                    "event_id": f"{STATE.simulation_id}:{dup_doc['seq']}:dup:{datetime.now().timestamp()}",
                    "simulation_id": STATE.simulation_id,
                    "topic": topic,
                    "payload": payload,
                    "received_at": datetime.now(),
                    "publish_state": "duplicate",
                    "last_publish_at": None,
                    "ack_result": None,
                    "ack_error": None,
                }
            )
            print(f"PC1: duplicate of seq={dup_doc['seq']}, {payload}")
        except DuplicateKeyError as e:
            print("PC1 duplicate insert error:", e)
        return

    STATE.current_seq += 1
    seq = STATE.current_seq

    try:
        mongo_events.insert_one(
            {
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
        )
        print(f"PC1: saved seq={seq}, {payload}")
    except DuplicateKeyError as e:
        print("PC1 insert error:", e)


def publish_doc(doc):
    MQTT_CLIENT.publish(
        stage2_topic(),
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


def publish_pending():
    while not stop_event.is_set():
        if STATE.validation_ok and is_primary():
            cutoff = datetime.now() - timedelta(seconds=SEC_RETRANSMISSAO)
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
        time.sleep(SEC_TRANSPORTE)


def wait_validation():
    STATE.validation_request_id = str(uuid4())
    deadline = time.time() + VALIDATION_TIMEOUT

    while not stop_event.is_set() and not STATE.validation_ok and STATE.validation_error is None:
        if time.time() >= deadline:
            STATE.validation_error = "pc2_no_response"
            return
        MQTT_CLIENT.publish(
            simcheck_req_topic(),
            json.dumps({
                "request_id": STATE.validation_request_id,
                "simulation_id": STATE.simulation_id,
            }),
            qos=1,
        )
        time.sleep(2)


def handle_simcheck_response(data):
    if data.get("request_id") != STATE.validation_request_id:
        return
    status = data.get("status")
    if status == "ok":
        STATE.validation_ok = True
        set_raw_subscription(True)
        print(f"PC1: simulation {STATE.simulation_id} validated")
    else:
        STATE.validation_error = status


def handle_ack(data):
    if int(data.get("simulation_id", -1)) != STATE.simulation_id or not is_primary():
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


def handle_game_end(data):
    if int(data.get("simulation_id", -1)) != STATE.simulation_id:
        return
    STATE.simulation_finished = True
    set_raw_subscription(False)
    print(f"PC1: simulation {STATE.simulation_id} finished")
    stop_event.set()


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
        if msg.topic == simcheck_resp_topic():
            handle_simcheck_response(data)
        elif msg.topic == ack_topic():
            handle_ack(data)
        elif msg.topic == game_end_topic():
            handle_game_end(data)
        elif STATE.validation_ok and is_primary() and msg.topic in raw_topics():
            save_raw_event(msg.topic, data)
    except Exception as e:
        print("Erro PC1:", e)


def on_connect(client, userdata, flags, reason_code, properties):
    client.subscribe(simcheck_resp_topic(), qos=1)
    client.subscribe(ack_topic(), qos=1)
    client.subscribe(game_end_topic(), qos=1)


def main():
    global MQTT_CLIENT

    parser = argparse.ArgumentParser()
    parser.add_argument("--simulation-id", type=int, required=True)
    STATE.simulation_id = parser.parse_args().simulation_id

    ensure_indexes()
    last_doc = mongo_events.find_one({"simulation_id": STATE.simulation_id}, sort=[("seq", -1)])
    STATE.current_seq = last_doc["seq"] if last_doc else 0

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

    threading.Thread(target=publish_pending, daemon=True).start()

    try:
        while not stop_event.is_set():
            set_raw_subscription(STATE.validation_ok and is_primary() and not STATE.simulation_finished)
            time.sleep(1)
    except KeyboardInterrupt:
        pass

    MQTT_CLIENT.loop_stop()
    MQTT_CLIENT.disconnect()


if __name__ == "__main__":
    main()
