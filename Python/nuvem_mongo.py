import os
import sys
import json
import time
import threading
import subprocess
from collections import deque
from datetime import datetime

import mysql.connector
import paho.mqtt.client as mqtt
from pymongo import MongoClient

MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883

TOPICO_PHP = "msgPHP"
TOPICO_PC2 = "PISID"

TOPICOS_SENSORES = [
    ("pisid_mazemov_+", "movimento"),
    ("pisid_mazetemp_+", "temperatura"),
    ("pisid_mazesound_+", "som"),
]

CLIENT_ID = f"pc1-{int(time.time())}"

MAZE_DB_CONFIG = {
    "host": "194.210.86.10",
    "user": "aluno",
    "password": "aluno",
    "database": "maze",
}

MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"
MONGO_DB = "Marsabirinto"

if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MAZERUN_PATH = os.path.join(BASE_DIR, "mazerun")
LOG_DIR = os.path.join(BASE_DIR, "logs")

CAMPOS_OBRIGATORIOS = {
    "movimento": {"Marsami", "Player", "RoomOrigin", "RoomDestiny", "Status"},
    "temperatura": {"Player", "Hour", "Temperature"},
    "som": {"Player", "Hour", "Sound"},
}

FORMATOS_HORA = [
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M:%SZ",
    "%Y-%m-%d %H:%M:%S.%f",
]


# =========================
# GLOBAL STATE
# =========================

setupmaze = {}
corredores = set()

mensagens_deque = deque()
mensagens_lock = threading.Lock()

estado_lock = threading.Lock()
simulacao_ativa_por_equipa = {}
parametros_por_equipa = {}
seq_por_equipa = {}
mazerun_por_equipa = {}

mongo_client = None
dados_sensores = None
dados_nao_migrados = None


# =========================
# MYSQL MAZE
# =========================

def carregar_dados_maze():
    global setupmaze, corredores

    conn = mysql.connector.connect(**MAZE_DB_CONFIG)
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM setupmaze LIMIT 1")
    setupmaze = cursor.fetchone()

    cursor.execute("""
        SELECT Rooma, Roomb
        FROM corridor
        WHERE active = 1
    """)

    corredores = {
        (int(row["Rooma"]), int(row["Roomb"]))
        for row in cursor.fetchall()
    }

    cursor.close()
    conn.close()

    print(f"[Maze DB] setupmaze: {setupmaze}")
    print(f"[Maze DB] corredores ativos: {len(corredores)}")


# =========================
# MONGO
# =========================

def ligar_mongo():
    global mongo_client, dados_sensores, dados_nao_migrados

    mongo_client = MongoClient(MONGO_URI)
    db = mongo_client[MONGO_DB]

    dados_sensores = db["dados_sensores"]
    dados_nao_migrados = db["dados_naoMigrados"]

    print(f"[Mongo] ligado a {MONGO_DB}")


# =========================
# MQTT HELPERS
# =========================

def publicar_json(client, topic, payload):
    message = json.dumps(payload, ensure_ascii=False)
    result = client.publish(topic, message, qos=1)
    result.wait_for_publish()
    print(f"[MQTT OUT] {topic}: {message}")


def tipo_e_equipa_do_topico(topic):
    equipa = int(topic.rsplit("_", 1)[1])

    if "mazemov" in topic:
        return "movimento", equipa

    if "mazetemp" in topic:
        return "temperatura", equipa

    return "som", equipa


# =========================
# VALIDACAO
# =========================

def converter_hora(valor):
    for formato in FORMATOS_HORA:
        try:
            return datetime.strptime(str(valor), formato)
        except ValueError:
            pass

    return None


def corrigir_hora_se_necessario(payload, received_at):
    hora = converter_hora(payload["Hour"])

    if hora is None:
        payload["Hour"] = received_at.strftime("%Y-%m-%d %H:%M:%S")


def validar_mensagem(tipo, payload, received_at, equipa):
    erros = []

    if tipo not in ["temperatura", "som", "movimento"]:
        erros.append("Tipo de mensagem desconhecido: " + tipo)
        return erros

    campos_em_falta = CAMPOS_OBRIGATORIOS[tipo] - set(payload.keys())
    if campos_em_falta:
        erros.append("campos em falta: " + ", ".join(sorted(campos_em_falta)))
        return erros

    if int(payload["Player"]) != equipa:
        erros.append("Player nao corresponde ao topico MQTT")

    if "Hour" in payload:
        corrigir_hora_se_necessario(payload, received_at)

    if tipo == "temperatura":
        if float(payload["Temperature"]) < 0:
            erros.append("temperatura negativa")

    if tipo == "som":
        if float(payload["Sound"]) < 0:
            erros.append("som negativo")

    if tipo == "movimento":
        marsami = int(payload["Marsami"])
        player = int(payload["Player"])
        sala_origem = int(payload["RoomOrigin"])
        sala_destino = int(payload["RoomDestiny"])
        status = int(payload["Status"])

        if marsami < 0:
            erros.append("marsami negativo")

        if player < 0:
            erros.append("player negativo")

        if sala_origem < 0:
            erros.append("sala origem negativa")

        if sala_destino < 0:
            erros.append("sala destino negativa")

        if status < 0:
            erros.append("status negativo")

        if status != 2 and sala_destino != 0:
            if (sala_origem, sala_destino) not in corredores:
                erros.append("movimento nao corresponde a corredor ativo")

    return erros


def detetar_outlier(tipo, payload, equipa):
    # TODO: substituir pela funcao de outliers do colega.
    return False


# =========================
# SEQ
# =========================

def proximo_seq(equipa):
    seq_por_equipa[equipa] += 1
    return seq_por_equipa[equipa]


# =========================
# MAZERUN WORKER
# =========================

def mazerun_worker(client, equipa, id_simulacao):
    os.makedirs(LOG_DIR, exist_ok=True)

    log_path = os.path.join(LOG_DIR, f"mazerun_{id_simulacao}_{equipa}.log")

    print(f"[Mazerun Worker] start equipa={equipa}, IDSimulacao={id_simulacao}")
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
            text=True,
        )

        return_code = process.wait()

        log_file.write("\n==============================\n")
        log_file.write(f"End: {datetime.now().isoformat()}\n")
        log_file.write(f"Return code: {return_code}\n")
        log_file.write("==============================\n")
        log_file.flush()

    with estado_lock:
        mazerun_por_equipa.pop(equipa, None)
        simulacao_ativa_por_equipa.pop(equipa, None)

    publicar_json(client, TOPICO_PC2, {
        "type": "End",
        "IDSimulacao": id_simulacao,
        "Equipa": equipa,
        "playerid": equipa,
    })

    print(f"[Mazerun Worker] end equipa={equipa}, IDSimulacao={id_simulacao}")


# =========================
# PHP START
# =========================

def tratar_start_php(client, payload):
    id_simulacao = int(payload["IDSimulacao"])
    equipa = int(payload["Equipa"])

    with estado_lock:
        if equipa in mazerun_por_equipa:
            print(f"[Start ignorado] equipa={equipa} ja esta a correr")
            return

        parametros_por_equipa[equipa] = payload

        simulacao_ativa_por_equipa[equipa] = {
            "IDSimulacao": id_simulacao,
            "Equipa": equipa,
        }

        seq_por_equipa[equipa] = 0

        with mensagens_lock:
            mensagens_filtradas = [
                mensagem for mensagem in mensagens_deque
                if mensagem["equipa"] != equipa
            ]
            mensagens_deque.clear()
            mensagens_deque.extend(mensagens_filtradas)

        thread = threading.Thread(
            target=mazerun_worker,
            args=(client, equipa, id_simulacao),
            daemon=True,
        )

        mazerun_por_equipa[equipa] = thread
        thread.start()

    print(f"[Start] equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[Parametros] {json.dumps(payload, ensure_ascii=False)}")


# =========================
# THREAD1 - PROCESSAR MENSAGENS
# =========================

def processar_mensagens():
    while True:
        with mensagens_lock:
            if mensagens_deque:
                mensagem = mensagens_deque.popleft()
            else:
                mensagem = None

        if mensagem is None:
            time.sleep(0.05)
            continue

        tipo = mensagem["tipo"]
        equipa = mensagem["equipa"]
        payload = mensagem["payload"]
        received_at = mensagem["received_at"]

        with estado_lock:
            if equipa not in simulacao_ativa_por_equipa:
                continue

            id_simulacao = simulacao_ativa_por_equipa[equipa]["IDSimulacao"]

        erros = validar_mensagem(tipo, payload, received_at, equipa)
        outlier = detetar_outlier(tipo, payload, equipa)

        if erros or outlier:
            categoria = "outlier" if outlier else "invalido: " + "; ".join(erros)

            dados_nao_migrados.insert_one({
                "simulacaoID": id_simulacao,
                "tipo": tipo,
                "payload": payload,
                "received_at": received_at,
                "categoria": categoria,
            })

            print(f"[dados_naoMigrados] simulacaoID={id_simulacao} tipo={tipo} categoria={categoria}")
            continue

        with estado_lock:
            seq = proximo_seq(equipa)

        dados_sensores.insert_one({
            "simulacaoID": id_simulacao,
            "seq": seq,
            "tipo": tipo,
            "payload": payload,
            "received_at": received_at,
            "alerta": False,
            "checked": False,
            "migrated": False,
        })

        print(f"[dados_sensores] simulacaoID={id_simulacao} seq={seq} tipo={tipo}")


# =========================
# MQTT CALLBACKS
# =========================

def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[MQTT] ligado a {MQTT_BROKER}:{MQTT_PORT}")

    client.subscribe(TOPICO_PHP, qos=1)
    print(f"[MQTT] subscrito: {TOPICO_PHP}")

    for topic, _ in TOPICOS_SENSORES:
        client.subscribe(topic, qos=1)
        print(f"[MQTT] subscrito: {topic}")


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode("utf-8"))
    received_at = datetime.now()

    if msg.topic == TOPICO_PHP:
        if payload["type"] == "Start":
            tratar_start_php(client, payload)
        return

    tipo, equipa = tipo_e_equipa_do_topico(msg.topic)

    with mensagens_lock:
        mensagens_deque.append({
            "topic": msg.topic,
            "tipo": tipo,
            "equipa": equipa,
            "payload": payload,
            "received_at": received_at,
        })


# =========================
# MAIN
# =========================

def main():
    print("[PC1] start")
    print(f"[PC1] base dir: {BASE_DIR}")
    print(f"[PC1] mazerun: {MAZERUN_PATH}")
    print(f"[PC1] log dir: {LOG_DIR}")

    carregar_dados_maze()
    ligar_mongo()

    thread1 = threading.Thread(
        target=processar_mensagens,
        daemon=True,
        name="thread1_processar_mensagens",
    )
    thread1.start()

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=CLIENT_ID,
    )

    client.on_connect = on_connect
    client.on_message = on_message

    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)

    print("[PC1] a aguardar mensagens MQTT")
    client.loop_forever()


if __name__ == "__main__":
    main()
