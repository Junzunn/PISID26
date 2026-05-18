import json
import time
import threading
import uuid
from queue import PriorityQueue, Empty

import mysql.connector
import paho.mqtt.client as mqtt
from config_loader import load_config


CONFIG = load_config()
MQTT_CONFIG = CONFIG.get("mqtt", {})
MIGRATION_CONFIG = CONFIG.get("migration", {})

MQTT_BROKER = MQTT_CONFIG.get("broker", "broker.emqx.io")
MQTT_PORT = int(MQTT_CONFIG.get("port", 1883))
TOPICO_PC1_PC2 = MQTT_CONFIG.get("topic_pc1_pc2", "PC1_PC2")
READY_INTERVAL = float(MIGRATION_CONFIG.get("ready_interval", 2.0))
MYSQL_RETRY_INTERVAL = float(MIGRATION_CONFIG.get("mysql_retry_interval", 2.0))

CLIENT_ID = f"mqtt-mysql-{uuid.uuid4().hex[:8]}"

MYSQL_CONFIG = CONFIG.get("mysql", {})
MYSQL = {
    "host": MYSQL_CONFIG.get("host", "127.0.0.1"),
    "port": int(MYSQL_CONFIG.get("port", 3306)),
    "user": MYSQL_CONFIG.get("user", "software@pisid.pt"),
    "password": MYSQL_CONFIG.get("password", "softwarepisid"),
    "database": MYSQL_CONFIG.get("database", "Marsabirinto"),
    "charset": MYSQL_CONFIG.get("charset", "utf8mb4"),
}

filas = {}
ids_em_fila = set()
simulacoes_ocupadas = set()
ultimo_ready = 0.0

lock = threading.Lock()
mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)


def publicar(payload):
    msg = json.dumps(payload, ensure_ascii=False)
    mqtt_client.publish(TOPICO_PC1_PC2, msg, qos=1).wait_for_publish()
    print(f"[MQTT OUT] {msg}")


def publicar_ready(forcar=False):
    global ultimo_ready

    agora = time.time()

    with lock:
        if simulacoes_ocupadas:
            return

        if not forcar and agora - ultimo_ready < READY_INTERVAL:
            return

        ultimo_ready = agora

    publicar({
        "from": "PC2",
        "type": "READY",
        "busy": [],
    })


def ready_loop():
    publicar_ready(forcar=True)

    while True:
        time.sleep(0.2)
        publicar_ready()


def ligar_mysql():
    conn = mysql.connector.connect(**MYSQL)
    cur = conn.cursor()
    return conn, cur


def fechar_mysql(conn, cur):
    try:
        if cur is not None:
            cur.close()
    except Exception:
        pass

    try:
        if conn is not None:
            conn.close()
    except Exception:
        pass


def ligar_mysql_com_retry(simulacao_id=None, seq=None):
    while True:
        try:
            return ligar_mysql()
        except mysql.connector.Error as erro:
            detalhe = ""
            if simulacao_id is not None and seq is not None:
                detalhe = f" simulacaoID={simulacao_id} seq={seq}"
            print(f"[MySQL] indisponivel{detalhe}; nova tentativa em {MYSQL_RETRY_INTERVAL:.1f}s: {erro}")
            time.sleep(MYSQL_RETRY_INTERVAL)


def chamar_sp(conn, cur, nome, args):
    cur.callproc(nome, args)
    conn.commit()


def hora(doc):
    return doc["payload"].get("Hour", doc["received_at"].replace("T", " ").split(".")[0])


def registar_fim_jogo(conn, cur, simulacao_id):
    try:
        chamar_sp(conn, cur, "simulacao_registar_fim", [simulacao_id])
    except mysql.connector.Error as erro:
        if "ja foi registado" not in str(erro):
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


def migrar_com_retry(conn, cur, doc):
    sid = int(doc["simulacaoID"])
    seq = int(doc["seq"])

    while True:
        try:
            migrar(conn, cur, doc)
            return conn, cur

        except mysql.connector.Error as erro:
            print(f"[MySQL] falha ao migrar simulacaoID={sid} seq={seq}; documento fica pendente: {erro}")
            fechar_mysql(conn, cur)
            conn, cur = ligar_mysql_com_retry(sid, seq)


def worker(simulacao_id):
    fila = filas[simulacao_id]
    conn, cur = ligar_mysql_com_retry()

    try:
        while True:
            try:
                seq, mongo_id, doc = fila.get(timeout=0.5)

            except Empty:
                ficou_livre = False

                with lock:
                    if fila.empty() and simulacao_id in simulacoes_ocupadas:
                        simulacoes_ocupadas.discard(simulacao_id)
                        ficou_livre = True

                if ficou_livre:
                    publicar_ready(forcar=True)

                continue

            conn, cur = migrar_com_retry(conn, cur, doc)

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
                publicar_ready(forcar=True)
                return

    finally:
        fechar_mysql(conn, cur)


def criar_worker(simulacao_id):
    if simulacao_id in filas:
        return

    filas[simulacao_id] = PriorityQueue()

    threading.Thread(
        target=worker,
        args=(simulacao_id,),
        daemon=True,
        name=f"mysql_worker_{simulacao_id}",
    ).start()


def receber_docs(docs):
    recebidos = 0

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
            recebidos += 1

    print(f"[DATA] recebidos {len(docs)} docs, aceites {recebidos}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
    except Exception as erro:
        print(f"[MQTT ignorado] JSON invalido: {erro}")
        return

    if payload.get("from") == "PC2":
        return

    if payload.get("type") == "DATA":
        receber_docs(payload.get("docs", []))


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
