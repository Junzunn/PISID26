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
from pymongo.errors import DuplicateKeyError
from config_loader import load_config

CONFIG = load_config()
MQTT_CONFIG = CONFIG.get("mqtt", {})
MIGRATION_CONFIG = CONFIG.get("migration", {})

MQTT_BROKER = MQTT_CONFIG.get("broker", "broker.emqx.io")
MQTT_PORT = int(MQTT_CONFIG.get("port", 1883))
TOPICO_PHP = MQTT_CONFIG.get("topic_php", "msgPHP")
TOPICO_PC1_PC2 = MQTT_CONFIG.get("topic_pc1_pc2", "PC1_PC2")
TOPICO_ATUADOR = MQTT_CONFIG.get("topic_atuador", "pisid_mazeact")
CLIENT_ID = f"mongo-mqtt-{uuid.uuid4().hex[:8]}"

MAZE_DB = CONFIG.get("maze_db", {"host": "194.210.86.10", "user": "aluno", "password": "aluno", "database": "maze"})
MONGO_CONFIG = CONFIG.get("mongo", {})
MONGO_URI = MONGO_CONFIG.get("uri", "mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/?replicaSet=rs0")
MONGO_DB = MONGO_CONFIG.get("database", "Marsabirinto")
BATCH_SIZE = int(MIGRATION_CONFIG.get("batch_size", 200))
intervalo_min_envio = float(MIGRATION_CONFIG.get("min_send_interval", 0.2))
mongo_scan_interval = float(MIGRATION_CONFIG.get("mongo_scan_interval", 0.1))

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
    saidas_por_sala, entradas_por_sala = {}, {}
    for row in cur.fetchall():
        origem, destino = int(row["Rooma"]), int(row["Roomb"])
        saidas_por_sala.setdefault(origem, []).append(destino)
        entradas_por_sala.setdefault(destino, []).append(origem)
    cur.close()
    conn.close()
    print("[Maze] setupmaze e corridor carregados")


def criar_indices_mongo():
    dados_sensores.create_index([("simulacaoID", 1), ("checked", 1), ("seq", 1)], name="idx_checked_seq")
    dados_sensores.create_index([("simulacaoID", 1), ("checked", 1), ("migrated", 1), ("seq", 1)], name="idx_migrated_seq")
    dados_nao_migrados.create_index([("simulacaoID", 1), ("tipo", 1), ("payload.tipo_acao", 1), ("payload.comando", 1)], name="idx_atuador_comando")


def criar_estado(simulacao_id, payload):
    estados[simulacao_id] = {
        "params": payload,
        "fila": PriorityQueue(),
        "thread": None,
        "ocupacao": {},
        "ac_ligado": False,
        "portas_score_fechadas": set(),
        "scores_por_sala": {},
        "ruido_global_fechado": False,
        "proxima_atuacao_ruido": 0.0,
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


def comando_all_door(tipo, equipa):
    return f"{{Type: {tipo}, Player:{equipa}}}"


def comando_ac(tipo, equipa):
    return f"{{Type: {tipo}, Player:{equipa}}}"


def insert_nao_migrado_com_retry(doc):
    while True:
        try:
            dados_nao_migrados.insert_one(doc)
            return
        except (ServerSelectionTimeoutError, AutoReconnect) as erro:
            print(f"[Mongo retry] dados_naoMigrados: {erro}")
            time.sleep(1)


def registar_atuador(simulacao_id, equipa, tipo_acao, comando, payload_origem, enviar=True):
    if enviar:
        publicar(TOPICO_ATUADOR, comando)
    insert_nao_migrado_com_retry({
        "simulacaoID": int(simulacao_id),
        "tipo": "atuador",
        "payload": {"equipa": int(equipa), "tipo_acao": tipo_acao, "comando": comando, "payload_origem": payload_origem, "enviado": bool(enviar)},
        "received_at": datetime.now(),
        "categoria": "acao do atuador",
    })


def registar_start_simulacao(simulacao_id, payload):
    try:
        dados_nao_migrados.update_one(
            {"_id": f"start:{int(simulacao_id)}"},
            {"$set": {
                "simulacaoID": int(simulacao_id),
                "tipo": "controlo",
                "payload": payload,
                "received_at": datetime.now(),
                "categoria": "start_simulacao",
            }},
            upsert=True,
        )
    except DuplicateKeyError:
        pass


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
    return normal, tolerancia, tempo_min, tempo_max, max(0, threshold)


def calcular_risco(tipo, valor, simulacao_id):
    normal, tolerancia, _, _, _ = normal_tolerancia_tempos_threshold(tipo, simulacao_id)
    if valor <= normal:
        return 0.0
    if tolerancia <= 0:
        return 1.0
    return (valor - normal) / tolerancia


def calcular_tempo_alerta(tipo, valor, simulacao_id):
    _, _, tempo_min, tempo_max, threshold = normal_tolerancia_tempos_threshold(tipo, simulacao_id)
    risco = calcular_risco(tipo, valor, simulacao_id)
    if risco >= 1 or threshold >= 1:
        return tempo_min
    progresso = (risco - threshold) / (1 - threshold)
    return max(tempo_min, min(tempo_max, tempo_max - progresso * (tempo_max - tempo_min)))


def calcular_tempo_fecho_ruido(valor, simulacao_id):
    _, _, tempo_min, tempo_max, threshold = normal_tolerancia_tempos_threshold("som", simulacao_id)
    risco = calcular_risco("som", valor, simulacao_id)
    if risco >= 1 or threshold >= 1:
        return tempo_max
    progresso = (risco - threshold) / (1 - threshold)
    return max(tempo_min, min(tempo_max, tempo_min + progresso * (tempo_max - tempo_min)))


def detectar_alerta(tipo, valor, simulacao_id):
    estado = estados[simulacao_id]
    _, _, _, _, threshold = normal_tolerancia_tempos_threshold(tipo, simulacao_id)
    risco = calcular_risco(tipo, valor, simulacao_id)
    agora = time.time()
    if risco <= 0 or risco < threshold:
        estado["prox_alerta"][tipo] = 0.0
        return False
    if agora < estado["prox_alerta"][tipo]:
        if not (tipo == "som" and risco >= 1):
            return False
    tempo_espera = calcular_tempo_alerta(tipo, valor, simulacao_id)
    estado["prox_alerta"][tipo] = agora + tempo_espera
    print(f"[alerta] simulacaoID={simulacao_id} tipo={tipo} valor={valor} risco={risco:.2f} espera={tempo_espera:.1f}s")
    return True


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
    return estados[simulacao_id]["scores_por_sala"].get(int(sala), 0)


def controlar_portas_score(simulacao_id, equipa, sala, payload, fechar):
    estado = estados[simulacao_id]
    portas = [(origem, sala) for origem in entradas_por_sala.get(sala, [])]
    portas += [(sala, destino) for destino in saidas_por_sala.get(sala, [])]
    for origem, destino in portas:
        porta = (origem, destino)
        if fechar and porta in estado["portas_score_fechadas"]:
            continue
        if not fechar and porta not in estado["portas_score_fechadas"]:
            continue
        if fechar:
            estado["portas_score_fechadas"].add(porta)
            tipo_porta = "CloseDoor"
        else:
            estado["portas_score_fechadas"].discard(porta)
            tipo_porta = "OpenDoor"
        registar_atuador(simulacao_id, equipa, "porta_score", comando_porta(tipo_porta, equipa, origem, destino), payload, enviar=not estado["ruido_global_fechado"])


def abrir_portas_sem_score(simulacao_id, equipa, payload):
    estado = estados[simulacao_id]

    registar_atuador(
        simulacao_id,
        equipa,
        "porta_ruido_global",
        comando_all_door("OpenAllDoor", equipa),
        payload,
    )
    estado["ruido_global_fechado"] = False

    for origem, destino in sorted(estado["portas_score_fechadas"]):
        registar_atuador(
            simulacao_id,
            equipa,
            "porta_score",
            comando_porta("CloseDoor", equipa, origem, destino),
            payload,
        )


def tentar_score_sala(simulacao_id, equipa, sala, payload):
    estado = estados[simulacao_id]
    ocupacao = estado["ocupacao"].get(sala)
    if not ocupacao or ocupacao["odd"] != ocupacao["even"] or ocupacao["odd"] == 0:
        return
    tentativas = contar_scores(simulacao_id, equipa, sala)
    if tentativas >= 3:
        return
    nova_tentativa = tentativas + 1
    registar_atuador(simulacao_id, equipa, "score", comando_score(equipa, sala), payload)
    estado["scores_por_sala"][int(sala)] = nova_tentativa

    if not estado["largada_finalizada"]:
        return

    controlar_portas_score(simulacao_id, equipa, sala, payload, fechar=(nova_tentativa < 3))


def tentar_score_todas_salas(simulacao_id, payload):
    equipa = get_equipa(simulacao_id)
    for sala in sorted(estados[simulacao_id]["ocupacao"].keys()):
        tentar_score_sala(simulacao_id, equipa, sala, payload)


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
    if valor <= float(setupmaze["normaltemperature"]) and estado["ac_ligado"]:
        registar_atuador(simulacao_id, equipa, "temperatura", comando_ac("AcOff", equipa), payload)
        estado["ac_ligado"] = False
    return tem_alerta


def tratar_som(doc):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    equipa = get_equipa(simulacao_id)
    valor = float(payload["Sound"])
    agora = time.time()
    tem_alerta = detectar_alerta("som", valor, simulacao_id)

    normalnoise = float(setupmaze["normalnoise"])

    if tem_alerta and not estado["ruido_global_fechado"]:
        registar_atuador(simulacao_id, equipa, "porta_ruido_global", comando_all_door("CloseAllDoor", equipa), payload)
        estado["ruido_global_fechado"] = True
        estado["proxima_atuacao_ruido"] = agora + calcular_tempo_fecho_ruido(valor, simulacao_id)

    elif estado["ruido_global_fechado"] and (valor <= normalnoise or agora >= estado["proxima_atuacao_ruido"]):
        abrir_portas_sem_score(simulacao_id, equipa, payload)
        _, _, tempo_min_ruido, tempo_max_ruido, threshold = normal_tolerancia_tempos_threshold("som", simulacao_id)
        estado["proxima_atuacao_ruido"] = agora + tempo_min_ruido
        estado["prox_alerta"]["som"] = agora + tempo_min_ruido + threshold * (tempo_max_ruido - tempo_min_ruido)

    return tem_alerta


def tratar_movimento(doc, emitir_score=True):
    simulacao_id = int(doc["simulacaoID"])
    payload = doc["payload"]
    estado = estados[simulacao_id]
    origem, destino = int(payload["RoomOrigin"]), int(payload["RoomDestiny"])
    marsami, status = int(payload["Marsami"]), int(payload["Status"])
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
            tem_alerta = False
            if doc["tipo"] == "temperatura":
                tem_alerta = tratar_temperatura(doc)
            elif doc["tipo"] == "som":
                tem_alerta = tratar_som(doc)
            elif doc["tipo"] == "movimento":
                tratar_movimento(doc)
            dados_sensores.update_one({"_id": doc["_id"]}, {"$set": {"checked": True, "alerta": bool(tem_alerta)}})
            print(f"[checked] simulacaoID={simulacao_id} seq={seq}")
        except Exception as erro:
            print(f"[erro worker] simulacaoID={simulacao_id} seq={seq}: {type(erro).__name__}: {erro}")
        finally:
            with lock:
                ids_em_fila.discard(mongo_id)
            fila.task_done()


def reconstruir_atuadores(simulacao_id):
    estado = estados[simulacao_id]
    docs = dados_nao_migrados.find({"simulacaoID": int(simulacao_id), "tipo": "atuador", "payload.tipo_acao": {"$in": ["score", "porta_score", "porta_ruido_global", "temperatura"]}}).sort("received_at", 1)
    for doc in docs:
        payload = doc.get("payload", {})
        tipo_acao = payload.get("tipo_acao", "")
        comando = payload.get("comando", "")
        if tipo_acao == "score":
            try:
                sala = int(comando.split("Room:")[1].split("}")[0].strip())
                estado["scores_por_sala"][sala] = estado["scores_por_sala"].get(sala, 0) + 1
            except Exception:
                pass
        elif tipo_acao == "temperatura":
            if "AcOn" in comando:
                estado["ac_ligado"] = True
            elif "AcOff" in comando:
                estado["ac_ligado"] = False
        elif tipo_acao == "porta_ruido_global":
            if "CloseAllDoor" in comando:
                estado["ruido_global_fechado"] = True
            elif "OpenAllDoor" in comando or "OpenDoor" in comando:
                estado["ruido_global_fechado"] = False
        elif tipo_acao == "porta_score":
            porta = porta_do_comando(comando)
            if porta and "CloseDoor" in comando:
                estado["portas_score_fechadas"].add(porta)
            elif porta and "OpenDoor" in comando:
                estado["portas_score_fechadas"].discard(porta)


def reconstruir_estado(simulacao_id):
    docs = dados_sensores.find({"simulacaoID": int(simulacao_id), "tipo": "movimento", "checked": True}).sort("seq", 1)
    for doc in docs:
        tratar_movimento(doc, emitir_score=False)
    reconstruir_atuadores(simulacao_id)
    print(f"[Recover] simulacaoID={simulacao_id} ocupacao={estados[simulacao_id]['ocupacao']} scores={estados[simulacao_id]['scores_por_sala']} portas_score={estados[simulacao_id]['portas_score_fechadas']} ruido_global={estados[simulacao_id]['ruido_global_fechado']}")


def recuperar_simulacoes_do_mongo():
    starts = dados_nao_migrados.find({"tipo": "controlo", "categoria": "start_simulacao"})
    recuperadas = 0

    for doc in starts:
        simulacao_id = int(doc["simulacaoID"])

        fim_migrado = dados_sensores.count_documents({
            "simulacaoID": simulacao_id,
            "tipo": "fim_jogo",
            "migrated": True,
        }) > 0

        if fim_migrado or simulacao_id in estados:
            continue

        payload = doc.get("payload", {})
        if not payload:
            continue

        criar_estado(simulacao_id, payload)
        reconstruir_estado(simulacao_id)
        criar_worker(simulacao_id)
        recuperadas += 1

    if recuperadas:
        print(f"[Recover automatico] {recuperadas} simulacao(oes) retomadas a partir do Mongo")


def criar_worker(simulacao_id):
    estado = estados.get(simulacao_id)
    if estado is None:
        return
    thread = estado.get("thread")
    if thread is not None and thread.is_alive():
        return
    thread = threading.Thread(target=worker, args=(simulacao_id,), daemon=True, name=f"mongo_worker_{simulacao_id}")
    estado["thread"] = thread
    thread.start()


def start_php(payload):
    simulacao_id = int(payload["IDSimulacao"])
    with lock:
        if simulacao_id in estados:
            print(f"[Start/Recover ignorado] simulacaoID={simulacao_id} ja esta ativo")
            return
        criar_estado(simulacao_id, payload)
        registar_start_simulacao(simulacao_id, payload)
        criar_worker(simulacao_id)
    print(f"[Start] simulacaoID={simulacao_id} equipa={payload['Equipa']}")


def limpar_simulacao(simulacao_id):
    with lock:
        estados.pop(simulacao_id, None)
    print(f"[cleanup] mongo_mqtt simulacaoID={simulacao_id}")


def distribuir_docs():
    with lock:
        simulacoes = list(estados.keys())
    for simulacao_id in simulacoes:
        docs = dados_sensores.find({"simulacaoID": simulacao_id, "checked": False}).sort("seq", 1).limit(BATCH_SIZE)
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
    return {"_id": str(doc["_id"]), "simulacaoID": doc["simulacaoID"], "seq": doc["seq"], "tipo": doc["tipo"], "payload": doc["payload"], "received_at": doc["received_at"].isoformat(), "alerta": doc.get("alerta", False)}


def enviar_lote(payload_ready):
    global ultimo_envio
    if time.time() - ultimo_envio < intervalo_min_envio:
        return
    busy = set(int(x) for x in payload_ready.get("busy", []))
    with lock:
        simulacoes = [simulacao_id for simulacao_id in estados.keys() if simulacao_id not in busy]
    docs_para_enviar = []
    for simulacao_id in simulacoes:
        limite = BATCH_SIZE - len(docs_para_enviar)
        if limite <= 0:
            break
        docs = dados_sensores.find({"simulacaoID": simulacao_id, "checked": True, "migrated": False}).sort("seq", 1).limit(limite)
        docs_para_enviar.extend(list(docs))
    if docs_para_enviar:
        enviar_pc2({"from": "PC1", "type": "DATA", "docs": [serializar(doc) for doc in docs_para_enviar]})
    ultimo_envio = time.time()


def marcar_migrados(ids):
    if ids:
        dados_sensores.update_many({"_id": {"$in": ids}}, {"$set": {"migrated": True}})


def fim_jogo_migrado(simulacao_id):
    return dados_sensores.count_documents({"simulacaoID": simulacao_id, "tipo": "fim_jogo", "migrated": True}) > 0


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(TOPICO_PHP, qos=1)
    client.subscribe(TOPICO_PC1_PC2, qos=1)
    print("[MQTT] ligado")


def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode())
    if msg.topic == TOPICO_PHP:
        if payload.get("type") == "Start":
            start_php(payload)
        return
    if msg.topic == TOPICO_PC1_PC2 and payload.get("from") == "PC2":
        if payload.get("type") == "READY":
            enviar_lote(payload)
        elif payload.get("type") == "ACK":
            marcar_migrados(payload.get("ids", []))


def main():
    carregar_maze()
    criar_indices_mongo()
    recuperar_simulacoes_do_mongo()
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    mqtt_client.loop_start()
    print("[mongo_mqtt] ativo")
    while True:
        distribuir_docs()
        time.sleep(mongo_scan_interval)

if __name__ == "__main__":
    main()
