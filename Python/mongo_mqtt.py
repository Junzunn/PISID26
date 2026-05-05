import json
import time
import threading
import uuid
from queue import PriorityQueue, Empty
from datetime import datetime

import mysql.connector
import paho.mqtt.client as mqtt
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, AutoReconnect

MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883

TOPICO_PHP = "msgPHP"
TOPICO_PC1_PC2 = "PC1_PC2"
TOPICO_ATUADOR = "pisid_mazeact"

CLIENT_ID = f"mongo-mqtt-{uuid.uuid4().hex[:8]}"

MAZE_DB = {
    "host": "194.210.86.10",
    "user": "aluno",
    "password": "aluno",
    "database": "maze",
}

MONGO_URI = "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0"
MONGO_DB = "Marsabirinto"

BATCH_SIZE = 200


setupmaze = {}
saidas_por_sala = {}

db = MongoClient(MONGO_URI)[MONGO_DB]
dados_sensores = db["dados_sensores"]
dados_nao_migrados = db["dados_naoMigrados"]

lock = threading.Lock()

filas = {}
threads = {}
estados = {}
parametros = {}
ids_em_fila = set()

ultimo_envio = 0.0

mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)


def carregar_maze():
    global setupmaze, saidas_por_sala

    conn = mysql.connector.connect(**MAZE_DB)
    cur = conn.cursor(dictionary=True)

    cur.execute("SELECT * FROM setupmaze LIMIT 1")
    setupmaze = cur.fetchone()

    cur.execute("SELECT Rooma, Roomb FROM corridor WHERE active = 1")
    saidas_por_sala = {}

    for row in cur.fetchall():
        saidas_por_sala.setdefault(int(row["Rooma"]), []).append(int(row["Roomb"]))

    cur.close()
    conn.close()

    print("[Maze] setupmaze e corridor carregados")


def publicar(topic, texto):
    mqtt_client.publish(topic, texto, qos=1)
    print(f"[MQTT OUT] {topic}: {texto}")


def enviar_pc2(payload):
    publicar(TOPICO_PC1_PC2, json.dumps(payload, ensure_ascii=False))


def comando_score(player, sala):
    return f"{{Type: Score, Player:{player}, Room: {sala}}}"


def comando_close_door(player, origem, destino):
    return f"{{Type: CloseDoor, Player:{player}, RoomOrigin: {origem}, RoomDestiny: {destino}}}"


def comando_open_all_door(player):
    return f"{{Type: OpenAllDoor, Player:{player}}}"


def comando_ac_on(player):
    return f"{{Type: AcOn, Player:{player}}}"


def comando_ac_off(player):
    return f"{{Type: AcOff, Player:{player}}}"

def insert_nao_migrado_com_retry(doc):
    while True:
        try:
            dados_nao_migrados.insert_one(doc)
            return
        except ServerSelectionTimeoutError as e:
            print(f"[Mongo retry] dados_naoMigrados: {e}")
            time.sleep(1)
        except AutoReconnect as e:
            print(f"[Mongo retry] a aguardar primary: {e}")
            time.sleep(1)

def registar_atuador(simulacao_id, equipa, tipo, comando, origem):
    publicar(TOPICO_ATUADOR, comando)

    doc = {
        "simulacaoID": simulacao_id,
        "tipo": "atuador",
        "payload": {
            "equipa": equipa,
            "tipo_acao": tipo,
            "comando": comando,
            "payload_origem": origem,
        },
        "received_at": datetime.now(),
        "categoria": "acao do atuador",
    }

    insert_nao_migrado_com_retry(doc)


def detectar_alerta(tipo, valor, simulacao_id):
    if tipo not in ("temperatura", "som"):
        return False

    estado = estados[simulacao_id]
    params = parametros.get(simulacao_id, {})
    agora = time.time()

    if tipo == "temperatura":
        normal = float(setupmaze["normaltemperature"])
        tolerancia = float(setupmaze["temperaturevarhightoleration"])

        tempo_max = float(params.get("tempo_max_temp", 20))
        tempo_min = float(params.get("tempo_min_temp", 2))
        threshold = float(params.get("threshold_temp", 0.25))

    else:
        normal = float(setupmaze["normalnoise"])
        tolerancia = float(setupmaze["noisevartoleration"])

        tempo_max = float(params.get("tempo_max_ruido", 20))
        tempo_min = float(params.get("tempo_min_ruido", 2))
        threshold = float(params.get("threshold_ruido", 0.25))

    if tempo_min > tempo_max:
        tempo_min, tempo_max = tempo_max, tempo_min

    if threshold > 1:
        threshold = threshold / 100

    if threshold < 0:
        threshold = 0

    if valor <= normal:
        estado["prox_alerta"][tipo] = 0.0
        return False

    if tolerancia <= 0:
        risco = 1.0
    else:
        risco = (valor - normal) / tolerancia

    if risco < threshold:
        estado["prox_alerta"][tipo] = 0.0
        return False

    if agora < estado["prox_alerta"][tipo]:
        return False

    if risco >= 1 or threshold >= 1:
        tempo_espera = tempo_min
    else:
        progresso = (risco - threshold) / (1 - threshold)
        tempo_espera = tempo_max - progresso * (tempo_max - tempo_min)

        if tempo_espera < tempo_min:
            tempo_espera = tempo_min

        if tempo_espera > tempo_max:
            tempo_espera = tempo_max

    estado["prox_alerta"][tipo] = agora + tempo_espera

    print(
        f"[alerta] simulacaoID={simulacao_id} tipo={tipo} "
        f"valor={valor} risco={risco:.2f} espera={tempo_espera:.1f}s"
    )

    return True


def criar_estado(simulacao_id):
    estados[simulacao_id] = {
        "ocupacao": {},
        "score": {},
        "ac_ligado": False,
        "portas_fechadas": set(),
        "prox_alerta": {
            "temperatura": 0.0,
            "som": 0.0,
        },
    }


def start_php(payload):
    simulacao_id = int(payload["IDSimulacao"])

    with lock:
        parametros[simulacao_id] = payload
        criar_estado(simulacao_id)
        criar_worker(simulacao_id)

    print(f"[Start] simulacaoID={simulacao_id} equipa={payload['Equipa']}")


def escolher_porta_para_fechar(estado):
    candidatas = []

    for origem, destinos in saidas_por_sala.items():
        abertas = [
            destino for destino in destinos
            if (origem, destino) not in estado["portas_fechadas"]
        ]

        if abertas:
            candidatas.append((len(abertas), origem, abertas[0]))

    if not candidatas:
        return None

    _, origem, destino = max(candidatas)
    return origem, destino


def tratar_temperatura(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    equipa = int(parametros[simulacao_id]["Equipa"])

    valor = float(payload["Temperature"])
    alerta = detectar_alerta("temperatura", valor, simulacao_id)

    if alerta and not estado["ac_ligado"]:
        registar_atuador(simulacao_id, equipa, "temperatura", comando_ac_on(equipa), payload)
        estado["ac_ligado"] = True

    if valor < float(setupmaze["normaltemperature"]) and estado["ac_ligado"]:
        registar_atuador(simulacao_id, equipa, "temperatura", comando_ac_off(equipa), payload)
        estado["ac_ligado"] = False

    return alerta


def tratar_som(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    equipa = int(parametros[simulacao_id]["Equipa"])

    valor = float(payload["Sound"])
    alerta = detectar_alerta("som", valor, simulacao_id)

    if alerta:
        porta = escolher_porta_para_fechar(estado)

        if porta is not None:
            origem, destino = porta
            registar_atuador(simulacao_id, equipa, "som", comando_close_door(equipa, origem, destino), payload)
            estado["portas_fechadas"].add((origem, destino))

    if valor < float(setupmaze["normalnoise"]) and estado["portas_fechadas"]:
        registar_atuador(simulacao_id, equipa, "som", comando_open_all_door(equipa), payload)
        estado["portas_fechadas"].clear()

    return alerta


def mudar_ocupacao(ocupacao, sala, grupo, delta):
    ocupacao.setdefault(sala, {"odd": 0, "even": 0})
    ocupacao[sala][grupo] += delta


def tentar_score(simulacao_id, equipa, sala, payload):
    ocupacao = estados[simulacao_id]["ocupacao"].get(sala)

    if not ocupacao:
        return

    if ocupacao["odd"] == ocupacao["even"] and ocupacao["odd"] != 0:
        tentativas = estados[simulacao_id]["score"].get(sala, 0)

        if tentativas < 3:
            registar_atuador(simulacao_id, equipa, "score", comando_score(equipa, sala), payload)
            estados[simulacao_id]["score"][sala] = tentativas + 1


def tratar_movimento(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    equipa = int(parametros[simulacao_id]["Equipa"])

    origem = int(payload["RoomOrigin"])
    destino = int(payload["RoomDestiny"])
    marsami = int(payload["Marsami"])
    status = int(payload["Status"])

    if status == 2:
        return

    grupo = "odd" if marsami % 2 == 0 else "even"
    ocupacao = estados[simulacao_id]["ocupacao"]

    if origem != 0:
        mudar_ocupacao(ocupacao, origem, grupo, -1)
        tentar_score(simulacao_id, equipa, origem, payload)

    if destino != 0:
        mudar_ocupacao(ocupacao, destino, grupo, 1)
        tentar_score(simulacao_id, equipa, destino, payload)


def worker(simulacao_id):
    fila = filas[simulacao_id]

    while True:
        try:
            seq, mongo_id, doc = fila.get(timeout=0.5)
        except Empty:
            if fim_jogo_migrado(simulacao_id):
                limpar_simulacao(simulacao_id)
                return

            continue

        alerta = False

        if doc["tipo"] == "temperatura":
            alerta = tratar_temperatura(doc)

        elif doc["tipo"] == "som":
            alerta = tratar_som(doc)

        elif doc["tipo"] == "movimento":
            tratar_movimento(doc)

        elif doc["tipo"] == "fim_jogo":
            pass

        dados_sensores.update_one(
            {"_id": doc["_id"]},
            {"$set": {"checked": True, "alerta": bool(alerta)}}
        )

        with lock:
            ids_em_fila.discard(mongo_id)

        fila.task_done()
        print(f"[checked] simulacaoID={simulacao_id} seq={seq}")


def criar_worker(simulacao_id):
    if simulacao_id in filas:
        return

    filas[simulacao_id] = PriorityQueue()

    thread = threading.Thread(
        target=worker,
        args=(simulacao_id,),
        daemon=True,
        name=f"mongo_worker_{simulacao_id}",
    )

    threads[simulacao_id] = thread
    thread.start()


def distribuir_docs():
    with lock:
        simulacoes = list(estados.keys())

    for simulacao_id in simulacoes:
        docs = dados_sensores.find({
            "simulacaoID": simulacao_id,
            "checked": False,
        }).sort("seq", 1)

        for doc in docs:
            mongo_id = str(doc["_id"])

            with lock:
                if simulacao_id not in estados or mongo_id in ids_em_fila:
                    continue

                criar_worker(simulacao_id)
                ids_em_fila.add(mongo_id)
                filas[simulacao_id].put((int(doc["seq"]), mongo_id, doc))


def serializar(doc):
    return {
        "_id": str(doc["_id"]),
        "simulacaoID": doc["simulacaoID"],
        "seq": doc["seq"],
        "tipo": doc["tipo"],
        "payload": doc["payload"],
        "received_at": doc["received_at"].isoformat(),
        "alerta": doc["alerta"],
    }


def enviar_lote(payload_ready):
    global ultimo_envio

    if time.time() - ultimo_envio < 1:
        return

    busy = set(int(x) for x in payload_ready.get("busy", []))

    with lock:
        simulacoes = [
            simulacao_id for simulacao_id in estados.keys()
            if simulacao_id not in busy
        ]

    docs_para_enviar = []

    for simulacao_id in simulacoes:
        limite = BATCH_SIZE - len(docs_para_enviar)

        if limite <= 0:
            break

        docs = list(
            dados_sensores
            .find({
                "simulacaoID": simulacao_id,
                "checked": True,
                "migrated": False,
            })
            .sort("seq", 1)
            .limit(limite)
        )
        docs_para_enviar.extend(docs)

    if docs_para_enviar:
        enviar_pc2({
            "from": "PC1",
            "type": "DATA",
            "docs": [serializar(doc) for doc in docs_para_enviar],
        })

    ultimo_envio = time.time()

def marcar_migrados(ids):
    dados_sensores.update_many(
        {"_id": {"$in": ids}},
        {"$set": {"migrated": True}}
    )


def fim_jogo_migrado(simulacao_id):
    return dados_sensores.count_documents({
        "simulacaoID": simulacao_id,
        "tipo": "fim_jogo",
        "migrated": True,
    }) > 0


def limpar_simulacao(simulacao_id):
    with lock:
        filas.pop(simulacao_id, None)
        threads.pop(simulacao_id, None)
        estados.pop(simulacao_id, None)
        parametros.pop(simulacao_id, None)

    print(f"[cleanup] mongo_mqtt simulacaoID={simulacao_id}")


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PHP, qos=1)
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode())

    if msg.topic == TOPICO_PHP and payload["type"] == "Start":
        start_php(payload)

    if msg.topic == TOPICO_PC1_PC2 and payload["from"] == "PC2":
        if payload["type"] == "READY":
            enviar_lote(payload)

        if payload["type"] == "ACK":
            marcar_migrados(payload["ids"])


def main():
    carregar_maze()

    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    mqtt_client.loop_start()

    print("[mongo_mqtt] ativo")

    while True:
        distribuir_docs()
        time.sleep(0.1)

if __name__ == "__main__":
    main()
    