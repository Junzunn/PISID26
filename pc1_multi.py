import os
import json
import time
import threading
import subprocess
from datetime import datetime
from typing import Any, Dict, Optional

import paho.mqtt.client as mqtt


MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883

TOPIC_FROM_PHP = "msgPHP"
TOPIC_TO_SERVER = "PISID"

CLIENT_ID = f"pc1-runner-{int(time.time())}"

import sys

if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MAZERUN_PATH = os.path.join(BASE_DIR, "mazerun")
LOG_DIR = os.path.join(BASE_DIR, "logs")


state_lock = threading.Lock()

simulation_params_by_equipa: Dict[int, Dict[str, Any]] = {}

running_by_equipa: Dict[int, Dict[str, Any]] = {}


def publish_json(client: mqtt.Client, topic: str, payload: Dict[str, Any]) -> None:
    message = json.dumps(payload, ensure_ascii=False)

    result = client.publish(topic, message, qos=1)
    result.wait_for_publish()

    print(f"[MQTT OUT] topic={topic} payload={message}")


def ensure_mazerun_ready() -> None:
    if not os.path.exists(MAZERUN_PATH):
        raise FileNotFoundError(f"mazerun not found: {MAZERUN_PATH}")

    if not os.access(MAZERUN_PATH, os.X_OK):
        raise PermissionError(
            f"mazerun exists but is not executable. Run: chmod +x {MAZERUN_PATH}"
        )


def get_value(data: Dict[str, Any], *names: str) -> Optional[Any]:
    for name in names:
        if name in data:
            return data[name]
    return None


def to_int(value: Any, field_name: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field_name} must be an integer")


def thread2_mazerun_worker(
    client: mqtt.Client,
    equipa: int,
    id_simulacao: int
) -> None:
    os.makedirs(LOG_DIR, exist_ok=True)

    log_path = os.path.join(
        LOG_DIR,
        f"mazerun_{id_simulacao}_{equipa}.log"
    )

    return_code: Optional[int] = None
    error_message: Optional[str] = None

    try:
        ensure_mazerun_ready()

        print(f"[THREAD2] starting mazerun equipa={equipa}, IDSimulacao={id_simulacao}")

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

    except Exception as e:
        error_message = str(e)
        print(
            f"[THREAD2 ERROR] equipa={equipa}, "
            f"IDSimulacao={id_simulacao}, error={error_message}"
        )

        with open(log_path, "a", encoding="utf-8") as log_file:
            log_file.write("\n==============================\n")
            log_file.write(f"Error: {datetime.now().isoformat()}\n")
            log_file.write(f"{error_message}\n")
            log_file.write("==============================\n")

    finally:
        with state_lock:
            current = running_by_equipa.get(equipa)

            if current and current["IDSimulacao"] == id_simulacao:
                del running_by_equipa[equipa]

        if error_message is None and return_code == 0:
            payload = {
                "type": "End",
                "event": "end_game",
                "status": "ok",
                "Equipa": equipa,
                "playerid": equipa,
                "IDSimulacao": id_simulacao
            }
        else:
            payload = {
                "type": "End",
                "event": "end_game",
                "status": "error",
                "Equipa": equipa,
                "playerid": equipa,
                "IDSimulacao": id_simulacao,
                "returnCode": return_code,
                "error": error_message
            }

        publish_json(client, TOPIC_TO_SERVER, payload)

        print(f"[THREAD2] finished equipa={equipa}, IDSimulacao={id_simulacao}")
        print(f"[THREAD2] log saved at: {log_path}")


def handle_start_message(client: mqtt.Client, data: Dict[str, Any]) -> None:
    message_type = get_value(data, "type", "event")

    if message_type not in ("Start", "start_game"):
        print(f"[IGNORED] message type not Start: {message_type}")
        return

    id_simulacao_raw = get_value(data, "IDSimulacao", "idSimulacao", "idsimulacao")
    equipa_raw = get_value(data, "Equipa", "equipa", "playerid", "playerID")

    if id_simulacao_raw is None or equipa_raw is None:
        publish_json(client, TOPIC_TO_SERVER, {
            "type": "StartRejected",
            "event": "start_game_rejected",
            "status": "error",
            "reason": "Missing IDSimulacao or Equipa",
            "received": data
        })
        return

    try:
        id_simulacao = to_int(id_simulacao_raw, "IDSimulacao")
        equipa = to_int(equipa_raw, "Equipa")
    except ValueError as e:
        publish_json(client, TOPIC_TO_SERVER, {
            "type": "StartRejected",
            "event": "start_game_rejected",
            "status": "error",
            "reason": str(e),
            "received": data
        })
        return

    with state_lock:
        if equipa in running_by_equipa:
            current = running_by_equipa[equipa]

            publish_json(client, TOPIC_TO_SERVER, {
                "type": "StartRejected",
                "event": "start_game_rejected",
                "status": "busy",
                "reason": "This equipa is already running",
                "Equipa": equipa,
                "current_IDSimulacao": current["IDSimulacao"],
                "new_IDSimulacao": id_simulacao
            })

            print(f"[REJECTED] equipa={equipa} already running")
            return

        simulation_params_by_equipa[equipa] = dict(data)

        thread = threading.Thread(
            target=thread2_mazerun_worker,
            args=(client, equipa, id_simulacao),
            daemon=True
        )

        running_by_equipa[equipa] = {
            "IDSimulacao": id_simulacao,
            "started_at": datetime.now().isoformat(),
            "thread": thread
        }

        thread.start()

    print(f"[ACCEPTED] equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[PARAMS SAVED] {json.dumps(data, ensure_ascii=False)}")


def on_connect(client: mqtt.Client, userdata: Any, flags: Any, reason_code: Any, properties: Any = None) -> None:
    print(f"[MQTT] connected to {MQTT_BROKER}:{MQTT_PORT}, reason={reason_code}")

    client.subscribe(TOPIC_FROM_PHP, qos=1)

    print(f"[MQTT] subscribed topic: {TOPIC_FROM_PHP}")


def on_message(client: mqtt.Client, userdata: Any, msg: mqtt.MQTTMessage) -> None:
    try:
        payload_text = msg.payload.decode("utf-8")
        print(f"[MQTT IN] topic={msg.topic} payload={payload_text}")

        data = json.loads(payload_text)

        if msg.topic == TOPIC_FROM_PHP:
            handle_start_message(client, data)

    except json.JSONDecodeError:
        publish_json(client, TOPIC_TO_SERVER, {
            "type": "StartRejected",
            "event": "start_game_rejected",
            "status": "error",
            "reason": "Invalid JSON",
            "raw": msg.payload.decode("utf-8", errors="ignore")
        })

    except Exception as e:
        publish_json(client, TOPIC_TO_SERVER, {
            "type": "PC1Error",
            "event": "pc1_error",
            "status": "error",
            "error": str(e)
        })


def create_mqtt_client() -> mqtt.Client:
    try:
        client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=CLIENT_ID
        )
    except AttributeError:
        client = mqtt.Client(client_id=CLIENT_ID)

    client.on_connect = on_connect
    client.on_message = on_message

    return client


def main() -> None:
    print("[PC1] starting...")
    print(f"[PC1] base dir: {BASE_DIR}")
    print(f"[PC1] mazerun path: {MAZERUN_PATH}")
    print(f"[PC1] log dir: {LOG_DIR}")

    client = create_mqtt_client()
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)

    print("[PC1] waiting for MQTT messages...")
    client.loop_forever()


if __name__ == "__main__":
    main()