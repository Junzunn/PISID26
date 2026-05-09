import json
import time
import threading
import uuid
from queue import PriorityQueue, Empty

import mysql.connector
import paho.mqtt.client as mqtt


MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
TOPICO_PC1_PC2 = "PC1_PC2"

CLIENT_ID = f"mqtt-mysql-{uuid.uuid4().hex[:8]}"

MYSQL = {
    "host": "192.168.1.228",
    "user": "software@pisid.pt",
    "password": "softwarepisid",
    "database": "Marsabirinto",
}

filas = {}
ids_em_fila = set()
simulacoes_ocupadas = set()

lock = threading.Lock()

mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)


def publicar(payload):
    msg = json.dumps(payload, ensure_ascii=False)
    mqtt_client.publish(TOPICO_PC1_PC2, msg, qos=1).wait_for_publish()
    #print(f"[MQTT OUT] {msg}")


def ready_loop():
    while True:
        with lock:
            busy = sorted(simulacoes_ocupadas)

        publicar({
            "from": "PC2",
            "type": "READY",
            "busy": busy,
        })

        time.sleep(1.5)


def ligar_mysql():
    conn = mysql.connector.connect(**MYSQL)
    cur = conn.cursor()
    return conn, cur


def chamar_sp(conn, cur, nome, args):
    conn.ping(reconnect=True, attempts=3, delay=2)
    cur.callproc(nome, args)
    conn.commit()


def hora(doc):
    return doc["payload"].get("Hour", doc["received_at"].replace("T", " ").split(".")[0])


def registar_fim_jogo(conn, cur, simulacao_id):
    try:
        chamar_sp(conn, cur, "simulacao_registar_fim", [simulacao_id])
    except mysql.connector.Error as e:
        if "ja foi registado" not in str(e):
            raise

def migrar(conn, cur, doc):
    sid = int(doc["simulacaoID"])
    seq = int(doc["seq"])
    tipo = doc["tipo"]
    payload = doc["payload"]
    h = hora(doc)

    if tipo == "temperatura":
        valor = str(payload["Temperature"])
        chamar_sp(conn, cur, "sp_registar_temperatura", [sid, seq, h, valor])

        if doc["alerta"]:
            chamar_sp(conn, cur, "sp_registar_mensagem", [
                sid,
                seq,
                h,
                "1",
                valor,
                "Temperatura",
                "Alerta de temperatura",
            ])

    elif tipo == "som":
        valor = str(payload["Sound"])
        chamar_sp(conn, cur, "sp_registar_som", [sid, seq, h, valor])

        if doc["alerta"]:
            chamar_sp(conn, cur, "sp_registar_mensagem", [
                sid,
                seq,
                h,
                "2",
                valor,
                "Som",
                "Alerta de som",
            ])

    elif tipo == "movimento":
        chamar_sp(conn, cur, "sp_registar_movimento", [
            sid,
            seq,
            h,
            int(payload["RoomOrigin"]),
            int(payload["RoomDestiny"]),
            int(payload["Marsami"]),
            int(payload["Status"]),
        ])

    elif tipo == "fim_jogo":
        registar_fim_jogo(conn, cur, sid)


def worker(simulacao_id):
    fila = filas[simulacao_id]
    conn, cur = ligar_mysql()

    try:
        while True:
            try:
                seq, mongo_id, doc = fila.get(timeout=0.5)
            except Empty:
                with lock:
                    if fila.empty():
                        simulacoes_ocupadas.discard(simulacao_id)
                continue

            while True:
                try:
                    migrar(conn, cur, doc)
                    break
                except mysql.connector.Error as e:
                    print(f"[MySQL retry] simulacaoID={simulacao_id} seq={seq}: {e}")
                    cur.close()
                    conn.close()
                    time.sleep(2)
                    conn, cur = ligar_mysql()

            publicar({
                "from": "PC2",
                "type": "ACK",
                "ids": [mongo_id],
            })

            with lock:
                ids_em_fila.discard(mongo_id)

            fila.task_done()
            print(f"[migrado] simulacaoID={simulacao_id} seq={seq} tipo={doc['tipo']}")

            if doc["tipo"] == "fim_jogo":
                with lock:
                    filas.pop(simulacao_id, None)
                    simulacoes_ocupadas.discard(simulacao_id)

                print(f"[cleanup] mqtt_mysql simulacaoID={simulacao_id}")
                return

    finally:
        cur.close()
        conn.close()


def criar_worker(simulacao_id):
    if simulacao_id in filas:
        return

    filas[simulacao_id] = PriorityQueue()

    thread = threading.Thread(
        target=worker,
        args=(simulacao_id,),
        daemon=True,
        name=f"mysql_worker_{simulacao_id}",
    )
    thread.start()


def receber_docs(docs):
    with lock:
        for doc in docs:
            sid = int(doc["simulacaoID"])
            mongo_id = doc["_id"]

            if mongo_id in ids_em_fila:
                continue

            criar_worker(sid)
            ids_em_fila.add(mongo_id)
            simulacoes_ocupadas.add(sid)
            filas[sid].put((int(doc["seq"]), mongo_id, doc))

    print(f"[DATA] recebidos {len(docs)} docs")


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode())

    if payload["from"] == "PC2":
        return

    if payload["type"] == "DATA":
        receber_docs(payload["docs"])


def main():
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    mqtt_client.loop_start()

    threading.Thread(target=ready_loop, daemon=True).start()

    print("[mqtt_mysql] ativo")

    while True:
        time.sleep(1)


if __name__ == "__main__":
    main()
