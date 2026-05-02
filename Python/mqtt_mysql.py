import json
import time
import threading
from queue import PriorityQueue, Empty

import mysql.connector
import paho.mqtt.client as mqtt


MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
TOPICO_PC1_PC2 = "PC1_PC2"

MYSQL = {
    "host": "127.0.0.1",
    "user": "software@pisid.pt",
    "password": "password",
    "database": "Marsabirinto",
}

filas = {}
threads = {}
fim_pendente = set()
ids_em_fila = set()

lock = threading.Lock()

mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="mqtt_mysql")


def publicar(payload):
    msg = json.dumps(payload, ensure_ascii=False)
    mqtt_client.publish(TOPICO_PC1_PC2, msg, qos=1).wait_for_publish()
    print(f"[MQTT OUT] {msg}")


def ready_loop():
    while True:
        with lock:
            ocupado = bool(ids_em_fila) or bool(fim_pendente)

        if not ocupado:
            publicar({"from": "PC2", "type": "READY"})

        time.sleep(1.5)


def chamar_sp(nome, args):
    conn = mysql.connector.connect(**MYSQL)
    cur = conn.cursor()
    cur.callproc(nome, args)
    conn.commit()
    cur.close()
    conn.close()


def hora(doc):
    return doc["payload"].get("Hour", doc["received_at"].replace("T", " ").split(".")[0])


def migrar(doc):
    sid = int(doc["simulacaoID"])
    seq = int(doc["seq"])
    tipo = doc["tipo"]
    payload = doc["payload"]
    h = hora(doc)

    if tipo == "temperatura":
        valor = str(payload["Temperature"])
        chamar_sp("sp_registar_temperatura", [sid, seq, h, valor])

        if doc["alerta"]:
            chamar_sp("sp_registar_mensagem", [
                sid,
                seq,
                h,
                "1",
                float(valor),
                "Temperatura",
                "Alerta de temperatura",
            ])

    elif tipo == "som":
        valor = str(payload["Sound"])
        chamar_sp("sp_registar_som", [sid, seq, h, valor])

        if doc["alerta"]:
            chamar_sp("sp_registar_mensagem", [
                sid,
                seq,
                h,
                "2",
                float(valor),
                "Som",
                "Alerta de som",
            ])

    elif tipo == "movimento":
        chamar_sp("sp_registar_movimento", [
            sid,
            seq,
            h,
            int(payload["RoomOrigin"]),
            int(payload["RoomDestiny"]),
            int(payload["Marsami"]),
            int(payload["Status"]),
        ])


def worker(simulacao_id):
    fila = filas[simulacao_id]

    while True:
        try:
            seq, mongo_id, doc = fila.get(timeout=0.5)
        except Empty:
            with lock:
                terminar = simulacao_id in fim_pendente

            if terminar:
                chamar_sp("simulacao_registar_fim", [simulacao_id])

                with lock:
                    fim_pendente.discard(simulacao_id)
                    filas.pop(simulacao_id, None)
                    threads.pop(simulacao_id, None)

                print(f"[cleanup] mqtt_mysql simulacaoID={simulacao_id}")
                return

            continue

        while True:
            try:
                migrar(doc)
                break
            except mysql.connector.Error as e:
                print(f"[MySQL retry] simulacaoID={simulacao_id} seq={seq}: {e}")
                time.sleep(2)

        publicar({"from": "PC2", "type": "ACK", "ids": [mongo_id]})

        with lock:
            ids_em_fila.discard(mongo_id)

        fila.task_done()
        print(f"[migrado] simulacaoID={simulacao_id} seq={seq}")


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

    threads[simulacao_id] = thread
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
            filas[sid].put((int(doc["seq"]), mongo_id, doc))

    print(f"[DATA] recebidos {len(docs)} docs")


def receber_end(payload):
    sid = int(payload["IDSimulacao"])

    with lock:
        criar_worker(sid)
        fim_pendente.add(sid)

    print(f"[END_READY] simulacaoID={sid}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode())

    if payload["from"] == "PC2":
        return

    if payload["type"] == "DATA":
        receber_docs(payload["docs"])

    if payload["type"] == "END_READY":
        receber_end(payload)


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
