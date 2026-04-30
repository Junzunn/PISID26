import os
import sys
import json
import time
import threading
import subprocess
from datetime import datetime

import paho.mqtt.client as mqtt


MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883

TOPIC_FROM_PHP = "msgPHP"
TOPIC_TO_SERVER = "PISID"

CLIENT_ID = f"pc1-{int(time.time())}"


if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MAZERUN_PATH = os.path.join(BASE_DIR, "mazerun")
LOG_DIR = os.path.join(BASE_DIR, "logs")


state_lock = threading.Lock()

simulation_params_by_equipa = {}
running_by_equipa = {}


def publish_json(client, topic, payload):
    message = json.dumps(payload, ensure_ascii=False)
    result = client.publish(topic, message, qos=1)
    result.wait_for_publish()
    print(f"[MQTT OUT] {topic}: {message}")


def mazerun_worker(client, equipa, id_simulacao):
    os.makedirs(LOG_DIR, exist_ok=True)

    log_path = os.path.join(
        LOG_DIR,
        f"mazerun_{id_simulacao}_{equipa}.log"
    )

    print(f"[Mazerun Worker] start mazerun equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[Mazerun Worker] log: {log_path}")

    with open(log_path, "a", encoding="utf-8") as log_file:
        log_file.write("\n==============================\n")
        log_file.write(f"Start: {datetime.now().isoformat()}\n")
        log_file.write(f"IDSimulacao: {id_simulacao}\n")
        log_file.write(f"Equipa: {equipa}\n")
        log_file.write(f"Command: {MAZERUN_PATH} {equipa} --flagMessage 1\n")
        log_file.write("==============================\n")
        log_file.flush()

        process = subprocess.Popen(
            [MAZERUN_PATH, str(equipa), "--flagMessage", "1"],
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True
        )

        return_code = process.wait()

        log_file.write("\n==============================\n")
        log_file.write(f"End: {datetime.now().isoformat()}\n")
        log_file.write(f"Return code: {return_code}\n")
        log_file.write("==============================\n")
        log_file.flush()

    with state_lock:
        running_by_equipa.pop(equipa, None)

    publish_json(client, TOPIC_TO_SERVER, {
        "type": "End",
        "event": "end_game",
        "Equipa": equipa,
        "playerid": equipa,
        "IDSimulacao": id_simulacao
    })

    print(f"[Mazerun Worker] finished equipa={equipa}, IDSimulacao={id_simulacao}")


def handle_start(client, data):
    id_simulacao = int(data["IDSimulacao"])
    equipa = int(data["Equipa"])

    with state_lock:
        if equipa in running_by_equipa:
            print(f"[IGNORED] equipa={equipa} already running")
            return

        simulation_params_by_equipa[equipa] = data

        thread = threading.Thread(
            target=mazerun_worker,
            args=(client, equipa, id_simulacao),
            daemon=True
        )

        running_by_equipa[equipa] = {
            "IDSimulacao": id_simulacao,
            "thread": thread
        }

        thread.start()

    print(f"[START] equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[PARAMS] {json.dumps(data, ensure_ascii=False)}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[MQTT] connected to {MQTT_BROKER}:{MQTT_PORT}")
    client.subscribe(TOPIC_FROM_PHP, qos=1)
    print(f"[MQTT] subscribed: {TOPIC_FROM_PHP}")


def on_message(client, userdata, msg):
    payload = msg.payload.decode("utf-8")
    print(f"[MQTT IN] {msg.topic}: {payload}")

    data = json.loads(payload)

    if msg.topic == TOPIC_FROM_PHP and data["type"] == "Start":
        handle_start(client, data)


def main():
    print("[PC1] starting")
    print(f"[PC1] base dir: {BASE_DIR}")
    print(f"[PC1] mazerun: {MAZERUN_PATH}")
    print(f"[PC1] log dir: {LOG_DIR}")

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=CLIENT_ID
    )

    client.on_connect = on_connect
    client.on_message = on_message

    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)

    print("[PC1] waiting for MQTT messages")
    client.loop_forever()


if __name__ == "__main__":
    main()