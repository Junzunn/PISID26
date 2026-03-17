import argparse, json, threading, time, sys
from datetime import datetime, timedelta
from uuid import uuid4

import paho.mqtt.client as mqtt
from pymongo import MongoClient, ASCENDING
from pymongo.errors import DuplicateKeyError, OperationFailure

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883
VALIDATION_TIMEOUT = 20
REPUBLISH_INTERVAL = 0.2
REPUBLISH_GAP_SECONDS = 1
BATCH_SIZE = 100

MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"
mongo = MongoClient(MONGO_URI)
mongo_events = mongo["pisid"]["sensor_events"]

SIMULATION_ID = None
MQTT_CLIENT = None
CURRENT_SEQ = 0
stop_event = threading.Event()
validation_ok = False
validation_error = None
validation_request_id = None
raw_subscribed = False
simulation_finished = False


def raw_topics():return [f"pisid_mazemov_{GROUP_ID}", f"pisid_mazetemp_{GROUP_ID}", f"pisid_mazesound_{GROUP_ID}"]

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
    except:
        return False


def subscribe_raw_topics():
    global raw_subscribed
    if raw_subscribed:
        return
    for t in raw_topics():
        MQTT_CLIENT.subscribe(t, qos=1)
    raw_subscribed = True
    print("PC1: raw topics subscribed")


def unsubscribe_raw_topics():
    global raw_subscribed
    if not raw_subscribed:
        return
    for t in raw_topics():
        MQTT_CLIENT.unsubscribe(t)
    raw_subscribed = False
    print("PC1: raw topics unsubscribed")


def save_raw_event(topic, payload):
    if simulation_finished:
        return
    global CURRENT_SEQ
    CURRENT_SEQ += 1
    seq = CURRENT_SEQ
    tipo = "movement" if "mov" in topic else "temperature" if "temp" in topic else "sound"
    try:
        mongo_events.insert_one({
            "event_id": f"{SIMULATION_ID}:{seq}",
            "simulation_id": SIMULATION_ID,
            "seq": seq,
            "tipo": tipo,
            "payload": payload,
            "received_at": datetime.now(),
            "publish_state": "pending",
            "last_publish_at": None,
        })
        print(f"PC1: saved seq={seq}, payload={payload}")
    except DuplicateKeyError:
        pass


def publish_doc(doc):
    MQTT_CLIENT.publish(stage2_topic(), json.dumps({
        "event_id": doc["event_id"],
        "simulation_id": doc["simulation_id"],
        "seq": doc["seq"],
        "tipo": doc["tipo"],
        "payload": doc["payload"],
    }, default=str), qos=1)
    mongo_events.update_one({"_id": doc["_id"]}, {"$set": {"last_publish_at": datetime.now()}})


def publish_pending():
    while not stop_event.is_set():
        if validation_ok and is_primary():
            cutoff = datetime.now() - timedelta(seconds=REPUBLISH_GAP_SECONDS)
            docs = mongo_events.find({
                "simulation_id": SIMULATION_ID,
                "publish_state": "pending",
                "$or": [{"last_publish_at": None}, {"last_publish_at": {"$lt": cutoff}}],
            }).sort("seq", 1).limit(BATCH_SIZE)
            for doc in docs:
                publish_doc(doc)
        time.sleep(REPUBLISH_INTERVAL)


def wait_validation():
    global validation_request_id, validation_error
    validation_request_id = str(uuid4())
    start = time.time()
    while not stop_event.is_set() and not validation_ok and validation_error is None:
        if time.time() - start >= VALIDATION_TIMEOUT:
            validation_error = "pc2_no_response"
            return
        MQTT_CLIENT.publish(simcheck_req_topic(), json.dumps({"request_id": validation_request_id, "simulation_id": SIMULATION_ID}), qos=1)
        time.sleep(2)


def on_message(client, userdata, msg):
    global validation_ok, validation_error, simulation_finished
    try:
        data = json.loads(msg.payload.decode())
        if msg.topic == simcheck_resp_topic() and data.get("request_id") == validation_request_id:
            if data.get("status") == "ok":
                validation_ok = True
                subscribe_raw_topics()
                print(f"PC1: simulation {SIMULATION_ID} validated")
            else:
                validation_error = data.get("status")
        elif msg.topic == ack_topic() and int(data.get("simulation_id", -1)) == SIMULATION_ID and is_primary():
            mongo_events.update_one(
                {"simulation_id": SIMULATION_ID, "seq": int(data["seq"]), "publish_state": "pending"},
                {"$set": {
                    "publish_state": "done" if data.get("result") == "success" else "invalid",
                    "ack_result": data.get("result"), "ack_error": data.get("error")
                }}
            )
        elif msg.topic == game_end_topic() and int(data.get("simulation_id", -1)) == SIMULATION_ID:
            simulation_finished = True
            unsubscribe_raw_topics()
            print(f"PC1: simulation {SIMULATION_ID} finished")
            stop_event.set()
        elif validation_ok and is_primary() and msg.topic in raw_topics():
            save_raw_event(msg.topic, data)
    except Exception as e:
        print("Erro PC1:", e)


def main():
    global SIMULATION_ID, MQTT_CLIENT, CURRENT_SEQ
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulation-id", type=int, required=True)
    SIMULATION_ID = parser.parse_args().simulation_id

    ensure_indexes()
    last_doc = mongo_events.find_one({"simulation_id": SIMULATION_ID}, sort=[("seq", -1)])
    CURRENT_SEQ = last_doc["seq"] if last_doc else 0

    MQTT_CLIENT = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    MQTT_CLIENT.on_connect = lambda c, u, f, rc, p: [
        c.subscribe(simcheck_resp_topic(), qos=1),
        c.subscribe(ack_topic(), qos=1),
        c.subscribe(game_end_topic(), qos=1)
    ]
    MQTT_CLIENT.on_message = on_message
    MQTT_CLIENT.connect(BROKER, PORT)
    MQTT_CLIENT.loop_start()

    wait_validation()
    if not validation_ok:
        MQTT_CLIENT.loop_stop(); MQTT_CLIENT.disconnect()
        print(f"ERRO: {validation_error or 'validation_failed'}")
        sys.exit(1)

    threading.Thread(target=publish_pending, daemon=True).start()
    try:
        while not stop_event.is_set():
            if not is_primary() and raw_subscribed:
                unsubscribe_raw_topics()
            elif validation_ok and is_primary() and not raw_subscribed:
                subscribe_raw_topics()
            time.sleep(1)
    except KeyboardInterrupt:
        pass

    MQTT_CLIENT.loop_stop()
    MQTT_CLIENT.disconnect()


if __name__ == "__main__":
    main()
