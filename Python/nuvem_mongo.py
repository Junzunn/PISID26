import json
import os
import subprocess
import sys
import threading
import time
import uuid
from collections import deque
from datetime import datetime
from queue import Queue, Empty

import mysql.connector
import paho.mqtt.client as mqtt
from pymongo import MongoClient
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError, AutoReconnect, DuplicateKeyError
from config_loader import load_config

CONFIG = load_config()
MQTT_CONFIG = CONFIG.get("mqtt", {})

MQTT_BROKER = MQTT_CONFIG.get("broker", "broker.emqx.io")
MQTT_PORT = int(MQTT_CONFIG.get("port", 1883))
TOPICO_PHP = MQTT_CONFIG.get("topic_php", "msgPHP")
TOPICOS_SENSORES_BASE = ["pisid_mazemov", "pisid_mazetemp", "pisid_mazesound"]
CLIENT_ID = f"nuvem-mongo-{uuid.uuid4().hex[:8]}"

MAZE_DB_CONFIG = CONFIG.get("maze_db", {
    "host": "194.210.86.10",
    "user": "aluno",
    "password": "aluno",
    "database": "maze",
})

MONGO_CONFIG = CONFIG.get("mongo", {})
MONGO_URI = MONGO_CONFIG.get(
    "uri",
    "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0&retryWrites=true&serverSelectionTimeoutMS=200&connectTimeoutMS=1000"
)
MONGO_DB = MONGO_CONFIG.get("database", "Marsabirinto")

BASE_DIR = os.path.dirname(sys.executable) if getattr(sys, "frozen", False) else os.path.dirname(os.path.abspath(__file__))
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
estados_por_equipa = {}


def carregar_dados_maze():
    global setupmaze, corredores

    conn = mysql.connector.connect(**MAZE_DB_CONFIG)
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM setupmaze LIMIT 1")
    setupmaze = cursor.fetchone()

    cursor.execute("SELECT Rooma, Roomb FROM corridor WHERE active = 1")
    corredores = {(int(row["Rooma"]), int(row["Roomb"])) for row in cursor.fetchall()}

    cursor.close()
    conn.close()

    print(f"[Maze DB] setupmaze: {setupmaze}")
    print(f"[Maze DB] corredores ativos: {corredores}")


def ligar_mongo():
    global mongo_client, dados_sensores, dados_nao_migrados

    try:
        mongo_client = MongoClient(MONGO_URI)
        mongo_client.admin.command("ping")
    except ServerSelectionTimeoutError:
        raise RuntimeError("[Mongo ERRO] MongoDB sem servico ou replica set sem primary")
    except PyMongoError as erro:
        raise RuntimeError(f"[Mongo ERRO] falha ao ligar ao MongoDB: {erro}")

    db = mongo_client[MONGO_DB]
    dados_sensores = db["dados_sensores"]
    dados_nao_migrados = db["dados_naoMigrados"]
    print(f"[Mongo] ligado a {MONGO_DB}")


def topicos_da_equipa(equipa):
    return [f"{base}_{equipa}" for base in TOPICOS_SENSORES_BASE]


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


def validar_posicao_marsami(equipa, marsami, origem, status):
    if status != 1:
        return None

    sala_atual = estados_por_equipa[equipa]["sala_atual_marsami"].get(marsami)

    if origem == 0:
        return "largada inicial repetida para o mesmo marsami" if sala_atual is not None else None

    if sala_atual is None:
        return "marsami sem sala atual conhecida"

    if sala_atual != origem:
        return f"RoomOrigin nao corresponde a sala atual do marsami (atual={sala_atual}, origem={origem})"

    return None


def validar_mensagem(tipo, payload, received_at, equipa):
    erros = []
    campos_em_falta = CAMPOS_OBRIGATORIOS[tipo] - set(payload.keys())

    if campos_em_falta:
        return ["campos em falta: " + ", ".join(sorted(campos_em_falta))]

    player = to_int(payload.get("Player"))
    if player is None:
        return ["Player invalido"]
    if player != equipa:
        erros.append("Player nao corresponde ao topico MQTT")

    corrigir_hora_se_necessario(payload, received_at)

    if tipo == "temperatura":
        temperatura = to_float(payload.get("Temperature"))
        if temperatura is None:
            erros.append("Temperature invalido")
        elif temperatura < float(setupmaze["normaltemperature"]) - float(setupmaze["temperaturevarlowtoleration"]):
            erros.append("Valor de temperatura inferior ao valor minimo permitido")
        return erros

    if tipo == "som":
        som = to_float(payload.get("Sound"))
        if som is None:
            erros.append("Som invalido")
        elif som < 0:
            erros.append("som negativo")
        elif som < float(setupmaze["normalnoise"]) - float(setupmaze["noisevartoleration"]):
            erros.append("Valor de som inferior ao valor minimo permitido")
        return erros

    marsami = to_int(payload.get("Marsami"))
    origem = to_int(payload.get("RoomOrigin"))
    destino = to_int(payload.get("RoomDestiny"))
    status = to_int(payload.get("Status"))

    numero_marsamis = int(setupmaze["numbermarsamis"])
    numero_salas = int(setupmaze["numberrooms"])

    if marsami is None or marsami < 1 or marsami > numero_marsamis:
        erros.append("Marsami invalido")
    if origem is None or origem < 0 or origem > numero_salas:
        erros.append("RoomOrigin invalido")
    if destino is None or destino < 0 or destino > numero_salas:
        erros.append("RoomDestiny invalido")
    if status is None or status not in (0, 1, 2):
        erros.append("Status invalido")

    if erros:
        return erros

    if status == 1 and destino == 0:
        erros.append("RoomDestiny 0 invalido para movimento normal")

    if status == 2 and (origem != 0 or destino != 0):
        erros.append("Status 2 deve usar RoomOrigin 0 e RoomDestiny 0")

    if status != 2 and origem != 0 and destino != 0 and (origem, destino) not in corredores:
        erros.append("movimento nao corresponde a corredor ativo")

    if not erros:
        erro_posicao = validar_posicao_marsami(equipa, marsami, origem, status)
        if erro_posicao:
            erros.append(erro_posicao)

    return erros


def atualizar_posicao_marsami(equipa, payload):
    status = to_int(payload.get("Status"))
    marsami = to_int(payload.get("Marsami"))
    destino = to_int(payload.get("RoomDestiny"))

    if status != 1 or marsami is None or destino is None:
        return

    estados_por_equipa[equipa]["sala_atual_marsami"][marsami] = destino


def detetar_outlier(tipo, payload, equipa):
    if tipo not in ("temperatura", "som"):
        return False

    if tipo == "temperatura":
        valor = to_float(payload.get("Temperature"))
        normal = to_float(setupmaze.get("normaltemperature"))
        tolerancia_inicial = to_float(setupmaze.get("temperaturevarhightoleration"))
    else:
        valor = to_float(payload.get("Sound"))
        normal = to_float(setupmaze.get("normalnoise"))
        tolerancia_inicial = to_float(setupmaze.get("noisevartoleration"))

    if valor is None:
        return False

    estado = estados_por_equipa[equipa]
    variacao = to_float(estado["params"].get("variacao_outlier"))

    if variacao is None or variacao < 0:
        return False
    if variacao > 1:
        variacao = variacao / 100

    historico = estado["historico_outliers"][tipo]

    if not historico:
        if normal is not None and tolerancia_inicial is not None and valor > normal + tolerancia_inicial:
            print(f"[outlier inicial] equipa={equipa} tipo={tipo} valor={valor} limite={normal + tolerancia_inicial}")
            return True
        historico.append(valor)
        return False

    referencia = historico[-1] if len(historico) == 1 else sum(historico) / len(historico)
    outlier = abs(valor - referencia) > variacao if referencia == 0 else abs(valor - referencia) / abs(referencia) > variacao

    if outlier:
        print(f"[outlier] equipa={equipa} tipo={tipo} valor={valor} referencia={referencia}")
        return True

    historico.append(valor)
    return False


def proximo_seq(equipa):
    estados_por_equipa[equipa]["seq"] += 1
    return estados_por_equipa[equipa]["seq"]


def insert_com_retry(collection, doc):
    while True:
        try:
            collection.insert_one(doc)
            return
        except DuplicateKeyError:
            return
        except ServerSelectionTimeoutError as erro:
            print(f"[Mongo retry] replica set sem primary: {erro}")
            time.sleep(1)
        except AutoReconnect as erro:
            print(f"[Mongo retry] a aguardar primary: {erro}")
            time.sleep(1)


def guardar_mensagem_valida(equipa, tipo, payload, received_at):
    estado = estados_por_equipa[equipa]
    seq = proximo_seq(equipa)

    insert_com_retry(dados_sensores, {
        "_id": f"{estado['IDSimulacao']}:{seq}",
        "simulacaoID": estado["IDSimulacao"],
        "seq": seq,
        "tipo": tipo,
        "payload": payload,
        "received_at": received_at,
        "alerta": False,
        "checked": False,
        "migrated": False,
    })

    print(f"[dados_sensores] simulacaoID={estado['IDSimulacao']} seq={seq} tipo={tipo}")


def guardar_mensagem_invalida(equipa, tipo, payload, received_at, categoria):
    estado = estados_por_equipa[equipa]

    insert_com_retry(dados_nao_migrados, {
        "simulacaoID": estado["IDSimulacao"],
        "tipo": tipo,
        "payload": payload,
        "received_at": received_at,
        "categoria": categoria,
    })

    print(f"[dados_naoMigrados] simulacaoID={estado['IDSimulacao']} tipo={tipo} categoria={categoria}")


def guardar_fim_jogo(equipa):
    estado = estados_por_equipa[equipa]
    seq = proximo_seq(equipa)

    insert_com_retry(dados_sensores, {
        "_id": f"{estado['IDSimulacao']}:{seq}",
        "simulacaoID": estado["IDSimulacao"],
        "seq": seq,
        "tipo": "fim_jogo",
        "payload": {"Equipa": equipa},
        "received_at": datetime.now(),
        "alerta": False,
        "checked": False,
        "migrated": False,
    })

    print(f"[fim_jogo] simulacaoID={estado['IDSimulacao']} seq={seq}")


def processar_mensagem(equipa, mensagem):
    tipo = mensagem["tipo"]
    payload = mensagem["payload"]
    received_at = mensagem["received_at"]

    erros = validar_mensagem(tipo, payload, received_at, equipa)
    if erros:
        guardar_mensagem_invalida(equipa, tipo, payload, received_at, "invalido: " + "; ".join(erros))
        return

    if detetar_outlier(tipo, payload, equipa):
        guardar_mensagem_invalida(equipa, tipo, payload, received_at, "outlier")
        return

    guardar_mensagem_valida(equipa, tipo, payload, received_at)

    if tipo == "movimento":
        atualizar_posicao_marsami(equipa, payload)


def worker_equipa(client, equipa):
    estado = estados_por_equipa[equipa]
    fila = estado["fila"]
    id_simulacao = estado["IDSimulacao"]

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
            except Exception as erro:
                print(f"[erro mensagem] equipa={equipa}: {type(erro).__name__}: {erro}")
            finally:
                fila.task_done()

        guardar_fim_jogo(equipa)

    with lock:
        estados_por_equipa.pop(equipa, None)

    print(f"[cleanup] nuvem_mongo equipa={equipa}, IDSimulacao={id_simulacao}")

def tratar_start_php(client, payload):
    id_simulacao = int(payload["IDSimulacao"])
    equipa = int(payload["Equipa"])

    with lock:
        if equipa in estados_por_equipa:
            print(f"[Start ignorado] equipa={equipa} ja esta a correr")
            return

        janela = to_int(payload.get("janela_outliers"))
        if janela is None or janela < 1:
            janela = 1

        estados_por_equipa[equipa] = {
            "IDSimulacao": id_simulacao,
            "Equipa": equipa,
            "params": payload,
            "fila": Queue(),
            "seq": 0,
            "historico_outliers": {
                "temperatura": deque(maxlen=janela),
                "som": deque(maxlen=janela),
            },
            "sala_atual_marsami": {},
        }

        thread = threading.Thread(
            target=worker_equipa,
            args=(client, equipa),
            daemon=True,
            name=f"worker_equipa_{equipa}",
        )
        estados_por_equipa[equipa]["thread"] = thread
        thread.start()

    print(f"[Start] equipa={equipa}, IDSimulacao={id_simulacao}")
    print(f"[Parametros] {json.dumps(payload, ensure_ascii=False)}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[MQTT] ligado a {MQTT_BROKER}:{MQTT_PORT}")
    client.subscribe(TOPICO_PHP, qos=1)
    print(f"[MQTT] subscrito: {TOPICO_PHP}")

    with lock:
        equipas = list(estados_por_equipa.keys())

    for equipa in equipas:
        subscrever_equipa(client, equipa)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except Exception as erro:
        print(f"[MQTT ignorado] payload invalido: {erro}")
        return

    received_at = datetime.now()

    if msg.topic == TOPICO_PHP:
        if payload.get("type") == "Start":
            tratar_start_php(client, payload)
        return

    tipo, equipa = tipo_e_equipa_do_topico(msg.topic)

    with lock:
        estado = estados_por_equipa.get(equipa)

    if estado is not None:
        estado["fila"].put({
            "tipo": tipo,
            "payload": payload,
            "received_at": received_at,
        })

def main():
    print("[nuvem_mongo] start")
    carregar_dados_maze()
    ligar_mongo()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)
    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)

    print("[nuvem_mongo] a aguardar mensagens MQTT")
    client.loop_forever()

if __name__ == "__main__":
    main()
