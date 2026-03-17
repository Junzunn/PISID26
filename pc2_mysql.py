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
def stage2_topic(): return f"pisid_pc2_stage2_{GROUP_ID}"
def ack_topic(): return f"pisid_pc2_ack_{GROUP_ID}"
def simcheck_req_topic(): return f"pisid_simcheck_req_{GROUP_ID}"
def simcheck_resp_topic(): return f"pisid_simcheck_resp_{GROUP_ID}"
def game_end_topic(): return f"pisid_game_end_{GROUP_ID}"


def log_message(simulation_id, tipo_alerta, msg, sensor=None, cur=None):
    conn = None; own = False
    try:
        if cur is None: conn = db(); cur = conn.cursor(); own = True
        cur.execute("""
            INSERT INTO Mensagens (Hora, Sensor, TipoAlerta, Msg, HoraEscrita, IDSimulacao)
            VALUES (NOW(), %s, %s, %s, NOW(), %s)
        """, (sensor, tipo_alerta, str(msg)[:100], simulation_id))
        if own: conn.commit()
    except Exception as e:
        print("Error logging:", e)
    finally:
        if own: cur.close(); conn.close()


def check_simulation(simulation_id):
    conn = db(); cur = conn.cursor()
    try:
        cur.execute("SELECT DataHoraInicio, DataHoraFim FROM Simulacao WHERE IDSimulacao = %s LIMIT 1", (simulation_id,))
        row = cur.fetchone()
        if not row: return f"A simulacao{simulation_id} nao existe"
        if row[1]: return f"A simulacao{simulation_id} ja foi terminada"
        if not row[0]: return f"A simulacao{simulation_id} nao esta iniciada"
        return "ok"
    finally:
        cur.close(); conn.close()


def simulation_finished(cur, simulation_id):
    cur.execute("SELECT DataHoraFim FROM Simulacao WHERE IDSimulacao = %s LIMIT 1", (simulation_id,))
    row = cur.fetchone()
    return bool(row and row[0])


def publish_simcheck_response(request_id, status):
    MQTT_CLIENT.publish(simcheck_resp_topic(), json.dumps({"request_id": request_id, "status": status}), qos=1)


def publish_ack(simulation_id, seq, result, error=None):
    MQTT_CLIENT.publish(ack_topic(), json.dumps({"simulation_id": simulation_id, "seq": seq, "result": result, "error": error}), qos=1)


def publish_game_end(simulation_id):
    MQTT_CLIENT.publish(game_end_topic(), json.dumps({"simulation_id": simulation_id}), qos=1)
    print(f"A simulacao terminada{simulation_id} com sucesso")


def parse_event_time(value):
    if isinstance(value, datetime): return value
    if isinstance(value, (int, float)): return datetime.fromtimestamp(value)
    text = str(value).strip()
    if not text: raise InvalidEventError("Hour invalid")
    try: return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=None)
    except: pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%H:%M:%S"):
        try:
            parsed = datetime.strptime(text, fmt)
            return datetime.combine(date.today(), parsed.time()) if fmt == "%H:%M:%S" else parsed
        except: pass
    raise InvalidEventError("Hour invalid")


def validate_event(msg_data):
    p = msg_data["payload"]; t = msg_data["tipo"]
    if t in ("temperature", "sound"):
        if not p.get("Hour"): raise InvalidEventError("Hour missing")
        return {"type": t, "hora": parse_event_time(p["Hour"]), "value": float(p["Temperature"] if t == "temperature" else p["Sound"])}
    if t == "movement":
        return {"type": "movement", "hora": parse_event_time(p["Hour"]) if p.get("Hour") else None,
                "marsami": int(p["Marsami"]), "origin": int(p["RoomOrigin"]), "destiny": int(p["RoomDestiny"]), "status": int(p["Status"])}
    raise InvalidEventError(f"Unknown: {t}")


def process_stage2_message(msg_data):
    sim_id, seq, ev_id, tipo = int(msg_data["simulation_id"]), int(msg_data["seq"]), msg_data["event_id"], msg_data["tipo"]
    if check_simulation(sim_id) != "ok":
        publish_ack(sim_id, seq, "invalid", "A simulacao ja foi terminada ou invalida")
        return True

    conn = db(); cur = conn.cursor()
    try:
        conn.start_transaction()
        cur.execute(
            "INSERT IGNORE INTO EventosProcessados (EventID, IDSimulacao, TipoEvento, EstadoProcessamento, ProcessedAt) VALUES (%s, %s, %s, 'PROCESSING', NOW())",
            (ev_id, sim_id, tipo)
        )
        if cur.rowcount == 0:
            conn.rollback()
            publish_ack(sim_id, seq, "success")
            return True

        try:
            d = validate_event(msg_data)
            if d["type"] == "temperature":
                cur.callproc("sp_record_temperature", (sim_id, d["value"], d["hora"]))
            elif d["type"] == "sound":
                cur.callproc("sp_record_sound", (sim_id, d["value"], d["hora"]))
            else:
                cur.execute("""
                    INSERT INTO MedicoesPassagens (Hora, SalaOrigem, SalaDestino, Marsami, Status, IDSimulacao)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (d["hora"], d["origin"], d["destiny"], d["marsami"], d["status"], sim_id))

            cur.execute("UPDATE EventosProcessados SET EstadoProcessamento='DONE' WHERE EventID=%s", (ev_id,))
            conn.commit()
            print(f"[MYSQL OK] sim={sim_id} seq={seq}")

            if sim_id not in finished_sent and simulation_finished(cur, sim_id):
                finished_sent.add(sim_id)
                publish_game_end(sim_id)

            publish_ack(sim_id, seq, "success")
            return True

        except InvalidEventError as e:
            log_message(sim_id, "DADO_INVALIDO", str(e), sensor=tipo, cur=cur)
            cur.execute("UPDATE EventosProcessados SET EstadoProcessamento='INVALID' WHERE EventID=%s", (ev_id,))
            conn.commit()
            print(f"[MYSQL INVALID] sim={sim_id} seq={seq}")

            if sim_id not in finished_sent and simulation_finished(cur, sim_id):
                finished_sent.add(sim_id)
                publish_game_end(sim_id)

            publish_ack(sim_id, seq, "invalid", str(e))
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


def main():
    global MQTT_CLIENT
    MQTT_CLIENT = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    MQTT_CLIENT.on_connect = lambda c, u, f, rc, p: [c.subscribe(simcheck_req_topic(), qos=1), c.subscribe(stage2_topic(), qos=1)]
    MQTT_CLIENT.on_message = on_message
    MQTT_CLIENT.connect(BROKER, PORT)
    MQTT_CLIENT.loop_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("PC2 stopped manualmente")
