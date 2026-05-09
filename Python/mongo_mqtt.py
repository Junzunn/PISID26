import json
import time
import threading
import uuid
from datetime import datetime
from queue import PriorityQueue, Empty
import mysql.connector
import paho.mqtt.client as mqtt
from pymongo import MongoClient
from pymongo.errors import AutoReconnect, ServerSelectionTimeoutError

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
entradas_por_sala = {}

mongo_db = MongoClient(MONGO_URI)[MONGO_DB]
dados_sensores = mongo_db["dados_sensores"]
dados_nao_migrados = mongo_db["dados_naoMigrados"]

lock = threading.Lock()
estados = {}
ids_em_fila = set()
ultimo_envio = 0.0
mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=CLIENT_ID)

def carregar_maze():
    global setupmaze, saidas_por_sala, entradas_por_sala

    conn = mysql.connector.connect(**MAZE_DB)
    cur = conn.cursor(dictionary=True)

    cur.execute("SELECT * FROM setupmaze LIMIT 1")
    setupmaze = cur.fetchone()

    cur.execute("SELECT Rooma, Roomb FROM corridor WHERE active = 1")
    saidas_por_sala = {}
    entradas_por_sala = {}

    for row in cur.fetchall():
        origem = int(row["Rooma"])
        destino = int(row["Roomb"])
        saidas_por_sala.setdefault(origem, []).append(destino)
        entradas_por_sala.setdefault(destino, []).append(origem)
    cur.close()
    conn.close()
    print("[Maze] setupmaze e corridor carregados")

def criar_indices_mongo():
    dados_sensores.create_index(
        [("simulacaoID", 1), ("checked", 1), ("seq", 1)],
        name="idx_checked_seq",
    )
    dados_sensores.create_index(
        [("simulacaoID", 1), ("checked", 1), ("migrated", 1), ("seq", 1)],
        name="idx_migrated_seq",
    )
    dados_nao_migrados.create_index(
        [("simulacaoID", 1), ("tipo", 1), ("payload.tipo_acao", 1), ("payload.comando", 1)],
        name="idx_atuador_comando",
    )


def criar_estado(simulacao_id, payload):
    estados[simulacao_id] = {
        "params": payload,
        "fila": PriorityQueue(),
        "thread": None,
        "ocupacao": {},
        "ac_ligado": False,
        "portas_fechadas": {},
        "largada_finalizada": False,
        "prox_alerta": {"temperatura": 0.0, "som": 0.0},
    }


def get_params(simulacao_id):
    return estados[simulacao_id]["params"]

def get_equipa(simulacao_id):
    return int(get_params(simulacao_id)["Equipa"])

def publicar(topico, texto):
    mqtt_client.publish(topico, texto, qos=1)
    print(f"[MQTT OUT] {topico}: {texto}")

def enviar_pc2(payload):
    publicar(TOPICO_PC1_PC2, json.dumps(payload, ensure_ascii=False))

def comando_score(equipa, sala):
    return f"{{Type: Score, Player:{equipa}, Room: {sala}}}"

def comando_porta(tipo, equipa, origem, destino):
    return f"{{Type: {tipo}, Player:{equipa}, RoomOrigin: {origem}, RoomDestiny: {destino}}}"

def comando_ac(tipo, equipa):
    return f"{{Type: {tipo}, Player:{equipa}}}"

def insert_nao_migrado_com_retry(doc):
    while True:
        try:
            dados_nao_migrados.insert_one(doc)
            return
        except (ServerSelectionTimeoutError, AutoReconnect) as e:
            print(f"[Mongo retry] dados_naoMigrados: {e}")
            time.sleep(1)

def registar_atuador(simulacao_id, equipa, tipo_acao, comando, payload_origem):
    publicar(TOPICO_ATUADOR, comando)

    insert_nao_migrado_com_retry({
        "simulacaoID": int(simulacao_id),
        "tipo": "atuador",
        "payload": {
            "equipa": int(equipa),
            "tipo_acao": tipo_acao,
            "comando": comando,
            "payload_origem": payload_origem,
        },
        "received_at": datetime.now(),
        "categoria": "acao do atuador",
    })


def normal_tolerancia_tempos_threshold(tipo, simulacao_id):
    params = get_params(simulacao_id)

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

    return normal, tolerancia, tempo_min, tempo_max, threshold


def calcular_risco(tipo, valor, simulacao_id):
    normal, tolerancia, _, _, _ = normal_tolerancia_tempos_threshold(tipo, simulacao_id)

    if valor <= normal:
        return 0.0
    if tolerancia <= 0:
        return 1.0

    return (valor - normal) / tolerancia


def valor_controlado(tipo, valor, simulacao_id):
    _, _, _, _, threshold = normal_tolerancia_tempos_threshold(tipo, simulacao_id)
    return calcular_risco(tipo, valor, simulacao_id) < threshold

def detectar_alerta(tipo, valor, simulacao_id):
    if tipo not in ("temperatura", "som"):
        return False
    estado = estados[simulacao_id]
    _, _, tempo_min, tempo_max, threshold = normal_tolerancia_tempos_threshold(tipo, simulacao_id)
    risco = calcular_risco(tipo, valor, simulacao_id)
    agora = time.time()
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
        tempo_espera = max(tempo_min, min(tempo_max, tempo_espera))
    estado["prox_alerta"][tipo] = agora + tempo_espera
    print(
        f"[alerta] simulacaoID={simulacao_id} tipo={tipo} "
        f"valor={valor} risco={risco:.2f} espera={tempo_espera:.1f}s"
    )
    return True

def fechar_porta(simulacao_id, equipa, origem, destino, payload, motivo):
    estado = estados[simulacao_id]
    porta = (origem, destino)
    motivos = estado["portas_fechadas"].setdefault(porta, set())
    if motivo in motivos:
        return
    if not motivos:
        registar_atuador(
            simulacao_id,
            equipa,
            f"porta_{motivo}",
            comando_porta("CloseDoor", equipa, origem, destino),
            payload,
        )
    motivos.add(motivo)

def abrir_porta(simulacao_id, equipa, origem, destino, payload, motivo):
    estado = estados[simulacao_id]
    porta = (origem, destino)
    motivos = estado["portas_fechadas"].get(porta)
    if not motivos or motivo not in motivos:
        return
    motivos.discard(motivo)
    if not motivos:
        registar_atuador(
            simulacao_id,
            equipa,
            f"porta_{motivo}",
            comando_porta("OpenDoor", equipa, origem, destino),
            payload,
        )
        estado["portas_fechadas"].pop(porta, None)

def atuar_portas_sala(simulacao_id, equipa, sala, payload, motivo, fechar, entradas=False, saidas=False):
    if entradas:
        for origem in entradas_por_sala.get(sala, []):
            if fechar:
                fechar_porta(simulacao_id, equipa, origem, sala, payload, motivo)
            else:
                abrir_porta(simulacao_id, equipa, origem, sala, payload, motivo)
    if saidas:
        for destino in saidas_por_sala.get(sala, []):
            if fechar:
                fechar_porta(simulacao_id, equipa, sala, destino, payload, motivo)
            else:
                abrir_porta(simulacao_id, equipa, sala, destino, payload, motivo)

def porta_do_comando(comando):
    try:
        origem = int(comando.split("RoomOrigin:")[1].split(",")[0].strip())
        destino = int(comando.split("RoomDestiny:")[1].split("}")[0].strip())
        return origem, destino
    except Exception:
        return None

def mudar_ocupacao(ocupacao, sala, grupo, delta):
    if sala == 0:
        return
    ocupacao.setdefault(sala, {"odd": 0, "even": 0})
    ocupacao[sala][grupo] = max(0, ocupacao[sala][grupo] + delta)

def contar_scores(simulacao_id, equipa, sala):
    return dados_nao_migrados.count_documents({
        "simulacaoID": int(simulacao_id),
        "tipo": "atuador",
        "payload.tipo_acao": "score",
        "payload.comando": comando_score(int(equipa), int(sala)),
    })

def tentar_score_sala(simulacao_id, equipa, sala, payload):
    estado = estados[simulacao_id]
    ocupacao = estado["ocupacao"].get(sala)
    if not ocupacao:
        return
    if ocupacao["odd"] != ocupacao["even"] or ocupacao["odd"] == 0:
        return
    tentativas = contar_scores(simulacao_id, equipa, sala)
    if tentativas >= 3:
        return
    registar_atuador(simulacao_id, equipa, "score", comando_score(equipa, sala), payload)
    if not estado["largada_finalizada"]:
        return
    if tentativas + 1 < 3:
        atuar_portas_sala(
            simulacao_id,
            equipa,
            sala,
            payload,
            motivo="score",
            fechar=True,
            entradas=True,
            saidas=True,
        )
    else:
        atuar_portas_sala(
            simulacao_id,
            equipa,
            sala,
            payload,
            motivo="score",
            fechar=False,
            saidas=True,
        )

def tentar_score_todas_salas(simulacao_id, payload):
    equipa = get_equipa(simulacao_id)
    for sala in sorted(estados[simulacao_id]["ocupacao"].keys()):
        tentar_score_sala(simulacao_id, equipa, sala, payload)

def escolher_sala_para_reduzir_ruido(simulacao_id, equipa):
    estado = estados[simulacao_id]
    melhor_sala = None
    melhor_total = -1
    reserva_sala = None
    reserva_total = -1
    for sala, ocupacao in estado["ocupacao"].items():
        total = ocupacao["odd"] + ocupacao["even"]
        if total <= 0:
            continue
        tem_saida_aberta = any(
            (sala, destino) not in estado["portas_fechadas"]
            for destino in saidas_por_sala.get(sala, [])
        )
        if not tem_saida_aberta:
            continue
        if total > reserva_total:
            reserva_sala = sala
            reserva_total = total
        if contar_scores(simulacao_id, equipa, sala) < 3 and total > melhor_total:
            melhor_sala = sala
            melhor_total = total
    return melhor_sala if melhor_sala is not None else reserva_sala

def abrir_uma_porta_de_ruido(simulacao_id, equipa, payload):
    estado = estados[simulacao_id]
    melhor_porta = None
    menor_ocupacao_origem = None
    for porta, motivos in estado["portas_fechadas"].items():
        if "ruido" not in motivos or len(motivos) > 1:
            continue
        origem, destino = porta
        ocupacao = estado["ocupacao"].get(origem, {"odd": 0, "even": 0})
        total = ocupacao["odd"] + ocupacao["even"]
        if menor_ocupacao_origem is None or total < menor_ocupacao_origem:
            melhor_porta = (origem, destino)
            menor_ocupacao_origem = total
    if melhor_porta is not None:
        origem, destino = melhor_porta
        abrir_porta(simulacao_id, equipa, origem, destino, payload, motivo="ruido")

def tratar_temperatura(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    equipa = get_equipa(simulacao_id)
    valor = float(payload["Temperature"])
    tem_alerta = detectar_alerta("temperatura", valor, simulacao_id)
    if tem_alerta and not estado["ac_ligado"]:
        registar_atuador(simulacao_id, equipa, "temperatura", comando_ac("AcOn", equipa), payload)
        estado["ac_ligado"] = True
    if valor_controlado("temperatura", valor, simulacao_id) and estado["ac_ligado"]:
        registar_atuador(simulacao_id, equipa, "temperatura", comando_ac("AcOff", equipa), payload)
        estado["ac_ligado"] = False
    return tem_alerta

def tratar_som(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    equipa = get_equipa(simulacao_id)
    valor = float(payload["Sound"])
    tem_alerta = detectar_alerta("som", valor, simulacao_id)
    if tem_alerta:
        sala = escolher_sala_para_reduzir_ruido(simulacao_id, equipa)
        if sala is not None:
            atuar_portas_sala(
                simulacao_id,
                equipa,
                sala,
                payload,
                motivo="ruido",
                fechar=True,
                saidas=True,
            )
    elif valor_controlado("som", valor, simulacao_id):
        abrir_uma_porta_de_ruido(simulacao_id, equipa, payload)
    return tem_alerta

def tratar_movimento(doc, emitir_score=True):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    origem = int(payload["RoomOrigin"])
    destino = int(payload["RoomDestiny"])
    marsami = int(payload["Marsami"])
    status = int(payload["Status"])
    if status == 1:
        grupo = "even" if marsami % 2 == 0 else "odd"
        if origem != 0:
            estado["largada_finalizada"] = True
            mudar_ocupacao(estado["ocupacao"], origem, grupo, -1)
        if destino != 0:
            mudar_ocupacao(estado["ocupacao"], destino, grupo, 1)
    if emitir_score:
        tentar_score_todas_salas(simulacao_id, payload)

def worker(simulacao_id):
    fila = estados[simulacao_id]["fila"]
    while True:
        try:
            seq, mongo_id, doc = fila.get(timeout=0.5)
        except Empty:
            if fim_jogo_migrado(simulacao_id):
                limpar_simulacao(simulacao_id)
                return
            continue
        try:
            tipo = doc["tipo"]
            tem_alerta = False
            if tipo == "temperatura":
                tem_alerta = tratar_temperatura(doc)
            elif tipo == "som":
                tem_alerta = tratar_som(doc)
            elif tipo == "movimento":
                tratar_movimento(doc)
            elif tipo == "fim_jogo":
                pass
            dados_sensores.update_one(
                {"_id": doc["_id"]},
                {"$set": {"checked": True, "alerta": bool(tem_alerta)}},
            )
            print(f"[checked] simulacaoID={simulacao_id} seq={seq}")
        except Exception as e:
            print(f"[erro worker] simulacaoID={simulacao_id} seq={seq}: {type(e).__name__}: {e}")
        finally:
            with lock:
                ids_em_fila.discard(mongo_id)
            fila.task_done()

def reconstruir_portas(simulacao_id):
    estado = estados[simulacao_id]
    docs = dados_nao_migrados.find({
        "simulacaoID": int(simulacao_id),
        "tipo": "atuador",
        "payload.tipo_acao": {"$in": ["porta_score", "porta_ruido"]},
    }).sort("received_at", 1)
    for doc in docs:
        payload = doc.get("payload", {})
        comando = payload.get("comando", "")
        porta = porta_do_comando(comando)
        if porta is None:
            continue
        motivo = payload.get("tipo_acao", "").replace("porta_", "")
        motivos = estado["portas_fechadas"].setdefault(porta, set())
        if "CloseDoor" in comando:
            motivos.add(motivo)
        elif "OpenDoor" in comando:
            motivos.discard(motivo)
            if not motivos:
                estado["portas_fechadas"].pop(porta, None)

def reconstruir_estado(simulacao_id):
    docs = dados_sensores.find({
        "simulacaoID": int(simulacao_id),
        "tipo": "movimento",
        "checked": True,
    }).sort("seq", 1)
    for doc in docs:
        tratar_movimento(doc, emitir_score=False)
    reconstruir_portas(simulacao_id)
    print(
        f"[Recover] simulacaoID={simulacao_id} "
        f"ocupacao={estados[simulacao_id]['ocupacao']} "
        f"portas={estados[simulacao_id]['portas_fechadas']}"
    )

def criar_worker(simulacao_id):
    estado = estados.get(simulacao_id)
    if estado is None:
        return
    thread = estado.get("thread")
    if thread is not None and thread.is_alive():
        return
    thread = threading.Thread(
        target=worker,
        args=(simulacao_id,),
        daemon=True,
        name=f"mongo_worker_{simulacao_id}",
    )
    estado["thread"] = thread
    thread.start()

def start_php(payload, recover=False):
    simulacao_id = int(payload["IDSimulacao"])
    with lock:
        if simulacao_id in estados:
            print(f"[Start/Recover ignorado] simulacaoID={simulacao_id} ja esta ativo")
            return
        criar_estado(simulacao_id, payload)
        if recover:
            reconstruir_estado(simulacao_id)
        criar_worker(simulacao_id)
    print(
        f"[{'Recover' if recover else 'Start'}] "
        f"simulacaoID={simulacao_id} equipa={payload['Equipa']}"
    )

def limpar_simulacao(simulacao_id):
    with lock:
        estados.pop(simulacao_id, None)
    print(f"[cleanup] mongo_mqtt simulacaoID={simulacao_id}")

def distribuir_docs():
    with lock:
        simulacoes = list(estados.keys())
    for simulacao_id in simulacoes:
        docs = dados_sensores.find({
            "simulacaoID": simulacao_id,
            "checked": False,
        }).sort("seq", 1).limit(BATCH_SIZE)
        for doc in docs:
            mongo_id = str(doc["_id"])
            with lock:
                estado = estados.get(simulacao_id)
                if estado is None or mongo_id in ids_em_fila:
                    continue
                criar_worker(simulacao_id)
                ids_em_fila.add(mongo_id)
                estado["fila"].put((int(doc["seq"]), mongo_id, doc))

def serializar(doc):
    return {
        "_id": str(doc["_id"]),
        "simulacaoID": doc["simulacaoID"],
        "seq": doc["seq"],
        "tipo": doc["tipo"],
        "payload": doc["payload"],
        "received_at": doc["received_at"].isoformat(),
        "alerta": doc.get("alerta", False),
    }

def enviar_lote(payload_ready):
    global ultimo_envio
    if time.time() - ultimo_envio < 1:
        return
    busy = set(int(x) for x in payload_ready.get("busy", []))
    with lock:
        simulacoes = [simulacao_id for simulacao_id in estados.keys() if simulacao_id not in busy]
    docs_para_enviar = []
    for simulacao_id in simulacoes:
        limite = BATCH_SIZE - len(docs_para_enviar)
        if limite <= 0:
            break
        docs = dados_sensores.find({
            "simulacaoID": simulacao_id,
            "checked": True,
            "migrated": False,
        }).sort("seq", 1).limit(limite)
        docs_para_enviar.extend(list(docs))
    if docs_para_enviar:
        enviar_pc2({
            "from": "PC1",
            "type": "DATA",
            "docs": [serializar(doc) for doc in docs_para_enviar],
        })
    ultimo_envio = time.time()

def marcar_migrados(ids):
    if ids:
        dados_sensores.update_many({"_id": {"$in": ids}}, {"$set": {"migrated": True}})

def fim_jogo_migrado(simulacao_id):
    return dados_sensores.count_documents({
        "simulacaoID": simulacao_id,
        "tipo": "fim_jogo",
        "migrated": True,
    }) > 0

def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PHP, qos=1)
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")

def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
    except Exception as e:
        print(f"[MQTT ignorado] payload invalido: {e}")
        return
    if msg.topic == TOPICO_PHP:
        tipo = payload.get("type")
        if tipo == "Start":
            start_php(payload, recover=False)
        elif tipo == "Recover":
            start_php(payload, recover=True)
        return
    if msg.topic == TOPICO_PC1_PC2 and payload.get("from") == "PC2":
        tipo = payload.get("type")
        if tipo == "READY":
            enviar_lote(payload)
        elif tipo == "ACK":
            marcar_migrados(payload.get("ids", []))

def main():
    carregar_maze()
    criar_indices_mongo()
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
