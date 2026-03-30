import json
from datetime import date, datetime

import mysql.connector
import paho.mqtt.client as mqtt

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883
MYSQL_CONFIG = {"host": "localhost", "user": "root", "password": "", "database": "pisid"}

MQTT_CLIENT = None
sim_states = {}
finished_sent = set()

EVENT_TOPICS = {
    "mazetemp": "temperature",
    "mazesound": "sound",
    "mazemov": "movement",
}

EVENT_SPECS = {
    "temperature": {
        "required": ("Hour", "Player", "Temperature"),
        "parser": lambda p: {
            "type": "temperature",
            "hora": parse_event_time(p["Hour"]),
            "player": int(p["Player"]),
            "value": float(p["Temperature"]),
        },
        "proc": lambda sim_id, e: ("sp_processar_temperatura", (sim_id, e["hora"], e["value"])),
    },
    "sound": {
        "required": ("Hour", "Player", "Sound"),
        "parser": lambda p: {
            "type": "sound",
            "hora": parse_event_time(p["Hour"]),
            "player": int(p["Player"]),
            "value": float(p["Sound"]),
        },
        "proc": lambda sim_id, e: ("sp_processar_ruido", (sim_id, e["hora"], e["value"])),
    },
    "movement": {
        "required": ("Player", "Marsami", "RoomOrigin", "RoomDestiny", "Status"),
        "parser": lambda p: {
            "type": "movement",
            "hora": parse_event_time(p["Hour"]) if p.get("Hour") else datetime.now(),
            "player": int(p["Player"]),
            "marsami": int(p["Marsami"]),
            "origin": int(p["RoomOrigin"]),
            "destiny": int(p["RoomDestiny"]),
            "status": int(p["Status"]),
        },
        "proc": lambda sim_id, e: (
            "sp_processar_movimento",
            (sim_id, e["player"], e["marsami"], e["origin"], e["destiny"], e["status"], e["hora"]),
        ),
    },
}


class InvalidEventError(Exception): pass

def db(): return mysql.connector.connect(**MYSQL_CONFIG)

def bridge_topic(): return f"pisid_pc_bridge_{GROUP_ID}"

def publish_bridge(message: dict):
    MQTT_CLIENT.publish(bridge_topic(), json.dumps(message), qos=1)


def publish_simcheck_response(request_id, simulation_id, status):
    publish_bridge(
        {
            "kind": "simcheck_resp",
            "src": "pc2",
            "request_id": request_id,
            "simulation_id": simulation_id,
            "status": status,
        }
    )


def publish_receipt(simulation_id, seq, event_id, state, error=None):
    publish_bridge(
        {
            "kind": "receipt",
            "src": "pc2",
            "simulation_id": simulation_id,
            "seq": seq,
            "event_id": event_id,
            "state": state,
            "error": error,
        }
    )


def publish_game_end(simulation_id):
    publish_bridge({"kind": "game_end", "src": "pc2", "simulation_id": simulation_id})
    print(f"A simulacao terminada {simulation_id} com sucesso")


def topic_to_event_type(topic: str) -> str:
    for marker, event_type in EVENT_TOPICS.items():
        if marker in topic:
            return event_type
    raise InvalidEventError(f"Unknown topic: {topic}")


def check_simulation(simulation_id):
    conn = db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT Estado FROM Simulacao WHERE IDSimulacao = %s LIMIT 1", (simulation_id,))
        row = cur.fetchone()
        if not row:
            return f"A simulacao {simulation_id} nao existe"
        estado = row[0]
        if estado == "PorIniciar":
            return f"A simulacao {simulation_id} nao esta iniciada"
        if estado == "Terminada":
            return f"A simulacao {simulation_id} ja foi terminada"
        return "ok"
    finally:
        cur.close()
        conn.close()


def simulation_finished(cur, simulation_id):
    cur.execute("SELECT Estado FROM Simulacao WHERE IDSimulacao = %s LIMIT 1", (simulation_id,))
    row = cur.fetchone()
    return bool(row and row[0] == "Terminada")


def load_expected_seq(sim_id):
    conn = db()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(EventID, ':', -1) AS UNSIGNED)), 0)
            FROM EventosProcessados
            WHERE IDSimulacao = %s
              AND EstadoProcessamento IN ('DONE', 'INVALID')
            """,
            (sim_id,),
        )
        last_seq = cur.fetchone()[0] or 0
        return last_seq + 1
    finally:
        cur.close()
        conn.close()


def parse_event_time(value):
    if isinstance(value, datetime):
        return value
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value)
    text = str(value).strip()
    if not text:
        raise InvalidEventError("Hour invalid")
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=None)
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%H:%M:%S"):
        try:
            parsed = datetime.strptime(text, fmt)
            return datetime.combine(date.today(), parsed.time()) if fmt == "%H:%M:%S" else parsed
        except Exception:
            pass
    raise InvalidEventError("Hour invalid")


def validate_event(msg_data):
    event_type = topic_to_event_type(msg_data["topic"])
    payload = msg_data["payload"]
    spec = EVENT_SPECS[event_type]
    for field in spec["required"]:
        if payload.get(field) in (None, ""):
            raise InvalidEventError(f"{event_type.capitalize()} event missing {field}")
    try:
        return spec["parser"](payload)
    except KeyError as e:
        raise InvalidEventError(f"{event_type.capitalize()} event missing {e.args[0]}") from e
    except (TypeError, ValueError) as e:
        raise InvalidEventError(f"{event_type.capitalize()} event invalid: {e}") from e


def dispatch_event(cur, sim_id, event_data):
    proc_name, params = EVENT_SPECS[event_data["type"]]["proc"](sim_id, event_data)
    cur.callproc(proc_name, params)


def mark_event(cur, event_id, state, error=None):
    cur.execute(
        """
        UPDATE EventosProcessados
           SET EstadoProcessamento=%s,
               ProcessedAt=NOW(),
               ErrorMessage=%s
         WHERE EventID=%s
        """,
        (state, error[:255] if error else None, event_id),
    )


def finalize_success(conn, cur, sim_id, seq, event_id):
    mark_event(cur, event_id, "DONE")
    conn.commit()
    print(f"[MYSQL OK] sim={sim_id} seq={seq}")
    if sim_id not in finished_sent and simulation_finished(cur, sim_id):
        finished_sent.add(sim_id)
        publish_game_end(sim_id)
    publish_receipt(sim_id, seq, event_id, "done")
    return True


def finalize_invalid(conn, cur, sim_id, seq, event_id, sensor, message):
    cur.callproc(
        "sp_log_message",
        (sim_id, sensor or "system", "DADO_INVALIDO", str(message)[:255], datetime.now(), None),
    )
    mark_event(cur, event_id, "INVALID", message)
    conn.commit()
    print(f"[MYSQL INVALID] sim={sim_id} seq={seq} error={message}")
    if sim_id not in finished_sent and simulation_finished(cur, sim_id):
        finished_sent.add(sim_id)
        publish_game_end(sim_id)
    publish_receipt(sim_id, seq, event_id, "invalid", message)
    return True


def process_stage2_message(msg_data):
    sim_id = int(msg_data["simulation_id"])
    seq = int(msg_data["seq"])
    event_id = msg_data["event_id"]
    conn = db()
    cur = conn.cursor()
    event_type = None
    try:
        conn.start_transaction()
        event_type = topic_to_event_type(msg_data["topic"])
        cur.execute(
            """
            INSERT IGNORE INTO EventosProcessados
                (EventID, IDSimulacao, TipoEvento, EstadoProcessamento, ProcessedAt)
            VALUES
                (%s, %s, %s, 'PROCESSING', NOW())
            """,
            (event_id, sim_id, event_type),
        )
        if cur.rowcount == 0:
            conn.rollback()
            publish_receipt(sim_id, seq, event_id, "done")
            return True
        sim_status = check_simulation(sim_id)
        if sim_status != "ok":
            return finalize_invalid(conn, cur, sim_id, seq, event_id, event_type, sim_status)
        event_data = validate_event(msg_data)
        dispatch_event(cur, sim_id, event_data)
        return finalize_success(conn, cur, sim_id, seq, event_id)
    except InvalidEventError as e:
        return finalize_invalid(conn, cur, sim_id, seq, event_id, event_type, str(e))
    except mysql.connector.Error as e:
        if getattr(e, "sqlstate", None) == "45000":
            return finalize_invalid(conn, cur, sim_id, seq, event_id, event_type, getattr(e, "msg", str(e)))
        conn.rollback()
        print("Process Error:", e)
        return False
    except Exception as e:
        conn.rollback()
        print("Process Error:", e)
        return False
    finally:
        cur.close()
        conn.close()


def handle_stage2_sequence(msg_data):
    sim_id = int(msg_data["simulation_id"])
    seq = int(msg_data["seq"])
    state = sim_states.setdefault(sim_id, {"expected": load_expected_seq(sim_id), "buf": {}})
    if seq < state["expected"]:
        publish_receipt(sim_id, seq, msg_data["event_id"], "done")
        return
    if seq > state["expected"]:
        state["buf"][seq] = msg_data
        return
    if not process_stage2_message(msg_data):
        return
    state["expected"] += 1
    while state["expected"] in state["buf"]:
        next_msg = state["buf"].pop(state["expected"])
        if not process_stage2_message(next_msg):
            return
        state["expected"] += 1


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        if msg.topic != bridge_topic() or payload.get("src") == "pc2":
            return
        kind = payload.get("kind")
        if kind == "simcheck_req":
            sim_id = int(payload["simulation_id"])
            publish_simcheck_response(payload["request_id"], sim_id, check_simulation(sim_id))
        elif kind == "event":
            handle_stage2_sequence(payload)
    except Exception as e:
        print("Erro PC2:", e)


def on_connect(client, userdata, flags, reason_code, properties):
    client.subscribe(bridge_topic(), qos=1)


def main():
    global MQTT_CLIENT
    MQTT_CLIENT = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    MQTT_CLIENT.on_connect = on_connect
    MQTT_CLIENT.on_message = on_message
    MQTT_CLIENT.connect(BROKER, PORT)
    MQTT_CLIENT.loop_forever()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("PC2 stopped manualmente")
