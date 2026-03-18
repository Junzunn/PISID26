import json
from datetime import datetime, date

import mysql.connector
import paho.mqtt.client as mqtt

GROUP_ID = 5
BROKER = "broker.emqx.io"
PORT = 1883

MYSQL_CONFIG = {"host": "localhost", "user": "root", "password": "", "database": "pisid"}
MQTT_CLIENT = None
sim_states = {}
finished_sent = set()


class InvalidEventError(Exception):
    pass


def db():
    return mysql.connector.connect(**MYSQL_CONFIG)


def stage2_topic():
    return f"pisid_pc2_stage2_{GROUP_ID}"


def ack_topic():
    return f"pisid_pc2_ack_{GROUP_ID}"


def simcheck_req_topic():
    return f"pisid_simcheck_req_{GROUP_ID}"


def simcheck_resp_topic():
    return f"pisid_simcheck_resp_{GROUP_ID}"


def game_end_topic():
    return f"pisid_game_end_{GROUP_ID}"


def topic_to_event_type(topic: str) -> str:
    if "mazetemp" in topic:
        return "temperature"
    if "mazesound" in topic:
        return "sound"
    if "mazemov" in topic:
        return "movement"
    raise InvalidEventError(f"Unknown topic: {topic}")


def log_message(simulation_id, tipo_alerta, msg, sensor=None, cur=None):
    conn = None
    own = False
    try:
        if cur is None:
            conn = db()
            cur = conn.cursor()
            own = True
        cur.execute(
            """
            INSERT INTO Mensagens (Hora, Sensor, TipoAlerta, Msg, HoraEscrita, IDSimulacao)
            VALUES (NOW(), %s, %s, %s, NOW(), %s)
            """,
            (sensor, tipo_alerta, str(msg)[:100], simulation_id),
        )
        if own:
            conn.commit()
    except Exception as e:
        print("Error logging:", e)
    finally:
        if own:
            cur.close()
            conn.close()


def check_simulation(simulation_id):
    conn = db()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT DataHoraInicio, DataHoraFim FROM Simulacao WHERE IDSimulacao = %s LIMIT 1",
            (simulation_id,),
        )
        row = cur.fetchone()
        if not row:
            return f"A simulacao{simulation_id} nao existe"
        if row[1]:
            return f"A simulacao{simulation_id} ja foi terminada"
        if not row[0]:
            return f"A simulacao{simulation_id} nao esta iniciada"
        return "ok"
    finally:
        cur.close()
        conn.close()


def simulation_finished(cur, simulation_id):
    cur.execute("SELECT DataHoraFim FROM Simulacao WHERE IDSimulacao = %s LIMIT 1", (simulation_id,))
    row = cur.fetchone()
    return bool(row and row[0])


def publish_simcheck_response(request_id, status):
    MQTT_CLIENT.publish(
        simcheck_resp_topic(),
        json.dumps({"request_id": request_id, "status": status}),
        qos=1,
    )


def publish_ack(simulation_id, seq, result, error=None):
    MQTT_CLIENT.publish(
        ack_topic(),
        json.dumps(
            {
                "simulation_id": simulation_id,
                "seq": seq,
                "result": result,
                "error": error,
            }
        ),
        qos=1,
    )


def publish_game_end(simulation_id):
    MQTT_CLIENT.publish(game_end_topic(), json.dumps({"simulation_id": simulation_id}), qos=1)
    print(f"A simulacao terminada{simulation_id} com sucesso")


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
    payload = msg_data["payload"]
    event_type = topic_to_event_type(msg_data["topic"])

    if event_type == "temperature":
        if "Hour" not in payload:
            raise InvalidEventError("Temperature event missing Hour")
        if "Temperature" not in payload:
            raise InvalidEventError("Temperature event missing Temperature")
        return {
            "type": "temperature",
            "hora": parse_event_time(payload["Hour"]),
            "player": int(payload["Player"]),
            "value": float(payload["Temperature"]),
        }

    if event_type == "sound":
        if "Hour" not in payload:
            raise InvalidEventError("Sound event missing Hour")
        if "Sound" not in payload:
            raise InvalidEventError("Sound event missing Sound")
        return {
            "type": "sound",
            "hora": parse_event_time(payload["Hour"]),
            "player": int(payload["Player"]),
            "value": float(payload["Sound"]),
        }

    if event_type == "movement":
        return {
            "type": "movement",
            "hora": parse_event_time(payload["Hour"]) if payload.get("Hour") else None,
            "player": int(payload["Player"]),
            "marsami": int(payload["Marsami"]),
            "origin": int(payload["RoomOrigin"]),
            "destiny": int(payload["RoomDestiny"]),
            "status": int(payload["Status"]),
        }

    raise InvalidEventError(f"Unknown event type from topic: {msg_data['topic']}")


def dispatch_event(cur, sim_id, event_data):
    if event_data["type"] == "temperature":
        cur.callproc("sp_record_temperature", (sim_id, event_data["player"], event_data["value"], event_data["hora"]))
        return "temperature"

    if event_data["type"] == "sound":
        cur.callproc("sp_record_sound", (sim_id, event_data["player"], event_data["value"], event_data["hora"]))
        return "sound"

    if event_data["type"] == "movement":
        cur.callproc(
            "sp_record_movement",
            (
                sim_id,
                event_data["player"],
                event_data["marsami"],
                event_data["origin"],
                event_data["destiny"],
                event_data["status"],
                event_data["hora"],
            ),
        )
        return "movement"

    raise InvalidEventError(f"Unhandled dispatcher type: {event_data['type']}")


def process_stage2_message(msg_data):
    sim_id = int(msg_data["simulation_id"])
    seq = int(msg_data["seq"])
    ev_id = msg_data["event_id"]
    tipo_evento = None

    sim_status = check_simulation(sim_id)
    if sim_status != "ok":
        publish_ack(sim_id, seq, "invalid", sim_status)
        return True

    conn = db()
    cur = conn.cursor()

    try:
        conn.start_transaction()

        tipo_evento = topic_to_event_type(msg_data["topic"])
        event_data = validate_event(msg_data)

        cur.execute(
            """
            INSERT IGNORE INTO EventosProcessados
                (EventID, IDSimulacao, TipoEvento, EstadoProcessamento, ProcessedAt)
            VALUES
                (%s, %s, %s, 'PROCESSING', NOW())
            """,
            (ev_id, sim_id, tipo_evento),
        )

        if cur.rowcount == 0:
            conn.rollback()
            publish_ack(sim_id, seq, "success")
            return True

        try:
            dispatch_event(cur, sim_id, event_data)

            cur.execute(
                """
                UPDATE EventosProcessados
                   SET EstadoProcessamento='DONE',
                       ProcessedAt=NOW(),
                       ErrorMessage=NULL
                 WHERE EventID=%s
                """,
                (ev_id,),
            )

            conn.commit()
            print(f"[MYSQL OK] sim={sim_id} seq={seq}")

            if sim_id not in finished_sent and simulation_finished(cur, sim_id):
                finished_sent.add(sim_id)
                publish_game_end(sim_id)

            publish_ack(sim_id, seq, "success")
            return True

        except mysql.connector.Error as e:
            message = getattr(e, "msg", str(e))

            if getattr(e, "sqlstate", None) == "45000":
                log_message(sim_id, "DADO_INVALIDO", message, sensor=tipo_evento, cur=cur)

                cur.execute(
                    """
                    UPDATE EventosProcessados
                       SET EstadoProcessamento='INVALID',
                           ProcessedAt=NOW(),
                           ErrorMessage=%s
                     WHERE EventID=%s
                    """,
                    (message[:255], ev_id),
                )

                conn.commit()
                print(f"[MYSQL INVALID] sim={sim_id} seq={seq} error={message}")

                if sim_id not in finished_sent and simulation_finished(cur, sim_id):
                    finished_sent.add(sim_id)
                    publish_game_end(sim_id)

                publish_ack(sim_id, seq, "invalid", message)
                return True

            raise

        except InvalidEventError as e:
            message = str(e)

            log_message(sim_id, "DADO_INVALIDO", message, sensor=tipo_evento, cur=cur)

            cur.execute(
                """
                UPDATE EventosProcessados
                   SET EstadoProcessamento='INVALID',
                       ProcessedAt=NOW(),
                       ErrorMessage=%s
                 WHERE EventID=%s
                """,
                (message[:255], ev_id),
            )

            conn.commit()
            print(f"[MYSQL INVALID] sim={sim_id} seq={seq} error={message}")
            publish_ack(sim_id, seq, "invalid", message)
            return True

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
    state = sim_states.setdefault(sim_id, {"expected": 1, "buf": {}})

    if seq < state["expected"]:
        publish_ack(sim_id, seq, "success")
        return

    if seq > state["expected"]:
        state["buf"][seq] = msg_data
        return

    if not process_stage2_message(msg_data):
        return

    state["expected"] += 1
    while state["expected"] in state["buf"]:
        nxt = state["buf"][state["expected"]]
        if not process_stage2_message(nxt):
            return
        del state["buf"][state["expected"]]
        state["expected"] += 1


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        if msg.topic == simcheck_req_topic():
            publish_simcheck_response(payload["request_id"], check_simulation(int(payload["simulation_id"])))
        elif msg.topic == stage2_topic():
            handle_stage2_sequence(payload)
    except Exception as e:
        print("Erro PC2:", e)


def on_connect(client, userdata, flags, reason_code, properties):
    client.subscribe(simcheck_req_topic(), qos=1)
    client.subscribe(stage2_topic(), qos=1)


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
