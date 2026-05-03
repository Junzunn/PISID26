import json
import os
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime
from queue import Queue, Empty

import mysql.connector
import paho.mqtt.client as mqtt
from pymongo import MongoClient
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError, AutoReconnect, DuplicateKeyError

MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
TOPICO_PHP = "msgPHP"

TOPICOS_SENSORES_BASE = [
    "pisid_mazemov",
    "pisid_mazetemp",
    "pisid_mazesound",
]

CLIENT_ID = f"nuvem-mongo-{uuid.uuid4().hex[:8]}"

MAZE_DB_CONFIG = {
    "host": "194.210.86.10",
    "user": "aluno",
    "password": "aluno",
    "database": "maze",
}

MONGO_URI = ("mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/"
            "?replicaSet=rs0"
            "&retryWrites=true"
            "&serverSelectionTimeoutMS=200"
            "&connectTimeoutMS=1000")
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

setupmaze = {}
corredores = set()

mongo_client = None
dados_sensores = None
dados_nao_migrados = None

lock = threading.Lock()
filas_por_equipa = {}
threads_por_equipa = {}
simulacao_ativa_por_equipa = {}
parametros_por_equipa = {}
seq_por_equipa = {}


def carregar_dados_maze():
    global setupmaze, corredores

    conn = mysql.connector.connect(**MAZE_DB_CONFIG)
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM setupmaze LIMIT 1")
    setupmaze = cursor.fetchone()

    cursor.execute("SELECT Rooma, Roomb FROM corridor WHERE active = 1")
    corredores = {
        (int(row["Rooma"]), int(row["Roomb"]))
        for row in cursor.fetchall()
    }

    cursor.close()
    conn.close()

    print(f"[Maze DB] setupmaze: {setupmaze}")
    print(f"[Maze DB] corredores ativos: {len(corredores)}")


def ligar_mongo():
    global mongo_client, dados_sensores, dados_nao_migrados

    try:
        mongo_client = MongoClient(MONGO_URI)
        mongo_client.admin.command("ping")
    except ServerSelectionTimeoutError:
        raise RuntimeError("[Mongo ERRO] MongoDB sem servico ou replica set sem primary")
    except PyMongoError as e:
        raise RuntimeError(f"[Mongo ERRO] falha ao ligar ao MongoDB: {e}")

    db = mongo_client[MONGO_DB]
    dados_sensores = db["dados_sensores"]
    dados_nao_migrados = db["dados_naoMigrados"]

    print(f"[Mongo] ligado a {MONGO_DB}")


def topicos_da_equipa(equipa):
    return [
        f"{base}_{equipa}"
        for base in TOPICOS_SENSORES_BASE
    ]


def subscrever_equipa(client, equipa):
    for topic in topicos_da_equipa(equipa):
        client.subscribe(topic, qos=1)
        print(f"[MQTT] subscrito: {topic}")


def tipo_e_equipa_do_topico(topic):
    equipa = int(topic.rsplit("_", 1)[1])

    if "mazemov" in topic:
        return "movimento", equipa

    if "mazetemp" in topic:
        return "temperatura", equipa

    return "som", equipa


def converter_hora(valor):
    for formato in FORMATOS_HORA:
        try:
            return datetime.strptime(str(valor), formato)
        except ValueError:
            pass

    return None


def corrigir_hora_se_necessario(payload, received_at):
    if "Hour" in payload and converter_hora(payload["Hour"]) is None:
        payload["Hour"] = received_at.strftime("%Y-%m-%d %H:%M:%S")

def to_int(valor):
    try:
        return int(valor)
    except (TypeError, ValueError):
        return None


def to_float(valor):
    try:
        return float(valor)
    except (TypeError, ValueError):
        return None

def validar_mensagem(tipo, payload, received_at, equipa):
    erros = []

    campos_em_falta = CAMPOS_OBRIGATORIOS[tipo] - set(payload.keys())
    if campos_em_falta:
        erros.append("campos em falta: " + ", ".join(sorted(campos_em_falta)))
        return erros

    player = to_int(payload.get("Player"))
    if player is None:
        erros.append("Player invalido")
        return erros

    if player != equipa:
        erros.append("Player nao corresponde ao topico MQTT")

    corrigir_hora_se_necessario(payload, received_at)

    if tipo == "temperatura":
        temperatura = to_float(payload.get("Temperature"))

        if temperatura is None:
            erros.append("Temperature invalido")
        elif temperatura < 0:
            erros.append("temperatura negativa")

    elif tipo == "som":
        som = to_float(payload.get("Sound"))

        if som is None:
            erros.append("Sound invalido")
        elif som < 0:
            erros.append("som negativo")

    elif tipo == "movimento":
        marsami = to_int(payload.get("Marsami"))
        origem = to_int(payload.get("RoomOrigin"))
        destino = to_int(payload.get("RoomDestiny"))
        status = to_int(payload.get("Status"))

        if marsami is None:
            erros.append("Marsami invalido")
        elif marsami < 0:
            erros.append("marsami negativo")

        if origem is None:
            erros.append("RoomOrigin invalido")
        elif origem < 0:
            erros.append("sala origem negativa")

        if destino is None:
            erros.append("RoomDestiny invalido")
        elif destino < 0:
            erros.append("sala destino negativa")

        if status is None:
            erros.append("Status invalido")
        elif status < 0:
            erros.append("status negativo")

        if (status is not None
            and origem is not None
            and destino is not None
            and status != 2
            and origem != 0
            and destino != 0
            and (origem, destino) not in corredores):
                erros.append("movimento nao corresponde a corredor ativo")

    return erros


def detetar_outlier(tipo, payload, equipa):
    # TODO: substituir pela funcao de outliers do colega.
    return False


def proximo_seq(equipa):
    seq_por_equipa[equipa] += 1
    return seq_por_equipa[equipa]

def insert_com_retry(collection, doc):
    while True:
        try:
            collection.insert_one(doc)
            return
        except DuplicateKeyError:
            return
        except ServerSelectionTimeoutError as e:
            print(f"[Mongo retry] replica set sem primary: {e}")
            time.sleep(1)
        except AutoReconnect as e:
            print(f"[Mongo retry] a aguardar primary: {e}")
            time.sleep(1)

def guardar_mensagem_valida(equipa, tipo, payload, received_at):
    id_simulacao = simulacao_ativa_por_equipa[equipa]["IDSimulacao"]
    seq = proximo_seq(equipa)

    doc = {
        "_id": f"{id_simulacao}:{seq}",
        "simulacaoID": id_simulacao,
        "seq": seq,
        "tipo": tipo,
        "payload": payload,
        "received_at": received_at,
        "alerta": False,
        "checked": False,
        "migrated": False,
    }

    insert_com_retry(dados_sensores, doc)
    print(f"[dados_sensores] simulacaoID={id_simulacao} seq={seq} tipo={tipo}")


def guardar_mensagem_invalida(equipa, tipo, payload, received_at, categoria):
    id_simulacao = simulacao_ativa_por_equipa[equipa]["IDSimulacao"]

    doc = {
        "simulacaoID": id_simulacao,
        "tipo": tipo,
        "payload": payload,
        "received_at": received_at,
        "categoria": categoria,
    }

    insert_com_retry(dados_nao_migrados, doc)
    print(f"[dados_naoMigrados] simulacaoID={id_simulacao} tipo={tipo} categoria={categoria}")


def guardar_fim_jogo(equipa):
    id_simulacao = simulacao_ativa_por_equipa[equipa]["IDSimulacao"]
    seq = proximo_seq(equipa)

    doc = {
        "_id": f"{id_simulacao}:{seq}",
        "simulacaoID": id_simulacao,
        "seq": seq,
        "tipo": "fim_jogo",
        "payload": {
            "Equipa": equipa,
        },
        "received_at": datetime.now(),
        "alerta": False,
        "checked": True,
        "migrated": False,
    }

    insert_com_retry(dados_sensores, doc)
    print(f"[fim_jogo] simulacaoID={id_simulacao} seq={seq}")


def processar_mensagem(equipa, mensagem):
    tipo = mensagem["tipo"]
    payload = mensagem["payload"]
    received_at = mensagem["received_at"]

    erros = validar_mensagem(tipo, payload, received_at, equipa)
    outlier = detetar_outlier(tipo, payload, equipa)

    if erros or outlier:
        categoria = "outlier" if outlier else "invalido: " + "; ".join(erros)
        guardar_mensagem_invalida(equipa, tipo, payload, received_at, categoria)
        return

    guardar_mensagem_valida(equipa, tipo, payload, received_at)


def worker_equipa(client, equipa):
    fila = filas_por_equipa[equipa]
    id_simulacao = simulacao_ativa_por_equipa[equipa]["IDSimulacao"]

    subscrever_equipa(client, equipa)
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, f"mazerun_{id_simulacao}_{equipa}.log")

    print(f"[worker_equipa] start equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[worker_equipa] log: {log_path}")

    with open(log_path, "a", encoding="utf-8") as log_file:
        log_file.write("\n==============================\n")
        log_file.write(f"Start: {datetime.now().isoformat()}\n")
        log_file.write(f"IDSimulacao: {id_simulacao}\n")
        log_file.write(f"Equipa: {equipa}\n")
        log_file.write(f"Command: {MAZERUN_PATH} {equipa} --flagMessage 1\n")
        log_file.write("==============================\n")
        log_file.flush()

        processo = subprocess.Popen(
            [MAZERUN_PATH, str(equipa), "--flagMessage", "1"],
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
        )

        processo_terminou = False

        while True:
            if not processo_terminou and processo.poll() is not None:
                processo_terminou = True

                log_file.write("\n==============================\n")
                log_file.write(f"End: {datetime.now().isoformat()}\n")
                log_file.write(f"Return code: {processo.returncode}\n")
                log_file.write("==============================\n")
                log_file.flush()

            try:
                mensagem = fila.get(timeout=0.05)
            except Empty:
                if processo_terminou:
                    break
                continue

            try:
                processar_mensagem(equipa, mensagem)
            except Exception as e:
                print(f"[erro mensagem] equipa={equipa}: {type(e).__name__}: {e}")
            finally:
                fila.task_done()

        guardar_fim_jogo(equipa)

    with lock:
        filas_por_equipa.pop(equipa, None)
        threads_por_equipa.pop(equipa, None)
        simulacao_ativa_por_equipa.pop(equipa, None)
        parametros_por_equipa.pop(equipa, None)
        seq_por_equipa.pop(equipa, None)

    print(f"[cleanup] nuvem_mongo equipa={equipa}, IDSimulacao={id_simulacao}")


def tratar_start_php(client, payload):
    id_simulacao = int(payload["IDSimulacao"])
    equipa = int(payload["Equipa"])

    with lock:
        if equipa in threads_por_equipa:
            print(f"[Start ignorado] equipa={equipa} ja esta a correr")
            return

        filas_por_equipa[equipa] = Queue()
        parametros_por_equipa[equipa] = payload
        simulacao_ativa_por_equipa[equipa] = {
            "IDSimulacao": id_simulacao,
            "Equipa": equipa,
        }
        seq_por_equipa[equipa] = 0

        thread = threading.Thread(
            target=worker_equipa,
            args=(client, equipa),
            daemon=True,
            name=f"worker_equipa_{equipa}",
        )

        threads_por_equipa[equipa] = thread
        thread.start()

    print(f"[Start] equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[Parametros] {json.dumps(payload, ensure_ascii=False)}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[MQTT] ligado a {MQTT_BROKER}:{MQTT_PORT}")

    client.subscribe(TOPICO_PHP, qos=1)
    print(f"[MQTT] subscrito: {TOPICO_PHP}")

    with lock:
        equipas = list(filas_por_equipa.keys())

    for equipa in equipas:
        subscrever_equipa(client, equipa)


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode("utf-8"))
    received_at = datetime.now()

    if msg.topic == TOPICO_PHP:
        if payload["type"] == "Start":
            tratar_start_php(client, payload)
        return

    tipo, equipa = tipo_e_equipa_do_topico(msg.topic)

    with lock:
        fila = filas_por_equipa.get(equipa)

    if fila is not None:
        fila.put({
            "tipo": tipo,
            "payload": payload,
            "received_at": received_at,
        })


def main():
    print("[nuvem_mongo] start")
    print(f"[nuvem_mongo] base dir: {BASE_DIR}")
    print(f"[nuvem_mongo] mazerun: {MAZERUN_PATH}")
    print(f"[nuvem_mongo] log dir: {LOG_DIR}")

    carregar_dados_maze()
    ligar_mongo()

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=CLIENT_ID,
    )

    client.on_connect = on_connect
    client.on_message = on_message

    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)

    print("[nuvem_mongo] a aguardar mensagens MQTT")
    client.loop_forever()


if __name__ == "__main__":
    main()
