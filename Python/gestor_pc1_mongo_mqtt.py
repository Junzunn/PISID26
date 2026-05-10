import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from pymongo import MongoClient
from pymongo.errors import PyMongoError

from config_loader import BASE_DIR, load_config

ROLE = "pc1"
SCRIPT = "mongo_mqtt.py"
PORT_KEY = "pc1_port"
DEFAULT_PORT = 8081

CONFIG = load_config()
MANAGER = CONFIG.get("manager", {})
PEDIDOS_TRATADOS = set()
PROCESSO = None
PROCESSO_LOCK = threading.Lock()
ULTIMO_AVISO_MONGO = 0.0


def abrir_mongo():
    mongo_cfg = CONFIG.get("mongo", {})
    client = MongoClient(mongo_cfg.get("uri"), serverSelectionTimeoutMS=500)
    client.admin.command("ping")
    return client, mongo_cfg.get("database", "Marsabirinto")


def mongo_disponivel():
    try:
        client, _ = abrir_mongo()
        client.close()
        return True
    except Exception:
        return False


def avisar_mongo_inativo():
    global ULTIMO_AVISO_MONGO
    agora = time.time()

    if agora - ULTIMO_AVISO_MONGO >= 10:
        print("[gestor PC1] O servico Mongo nao esta ativo, por favor, verifique o estado do MongoDB.")
        ULTIMO_AVISO_MONGO = agora


def iniciar_processo():
    global PROCESSO

    with PROCESSO_LOCK:
        if PROCESSO is not None and PROCESSO.poll() is None:
            return False

        if not mongo_disponivel():
            avisar_mongo_inativo()
            return False

        PROCESSO = subprocess.Popen(
            [sys.executable, str(BASE_DIR / SCRIPT)],
            cwd=str(BASE_DIR),
        )
        return True


def parar_processo():
    global PROCESSO

    with PROCESSO_LOCK:
        if PROCESSO is None or PROCESSO.poll() is not None:
            return

        PROCESSO.terminate()

        try:
            PROCESSO.wait(timeout=5)
        except subprocess.TimeoutExpired:
            PROCESSO.kill()
            PROCESSO.wait(timeout=5)


def processo_ok():
    with PROCESSO_LOCK:
        return PROCESSO is not None and PROCESSO.poll() is None


def reiniciar_processo():
    parar_processo()
    return iniciar_processo()


def monitor_loop():
    iniciar_processo()

    while True:
        if not processo_ok():
            iniciou = iniciar_processo()

            if iniciou:
                print(f"[gestor PC1] {SCRIPT} iniciado")

        time.sleep(2)


def status_payload():
    payload = {
        "pc": ROLE,
        "manager": "OK",
        "processo": SCRIPT,
        "processo_estado": "OK" if processo_ok() else "ERRO",
        "mongo": "ERRO",
        "mongo_erro": None,
        "documentos_por_tratar": None,
        "documentos_por_migrar": None,
        "nota": "Este gestor reinicia apenas o mongo_mqtt.py; o nuvem_mongo.py não é gerido por esta página.",
    }

    try:
        client, database = abrir_mongo()
        col = client[database]["dados_sensores"]

        payload["mongo"] = "OK"
        payload["documentos_por_tratar"] = col.count_documents({"checked": False})
        payload["documentos_por_migrar"] = col.count_documents({"checked": True, "migrated": False})

        client.close()

    except Exception as erro:
        payload["mongo_erro"] = f"{type(erro).__name__}: {erro}"

    return payload


class Handler(BaseHTTPRequestHandler):
    def enviar_json(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path.split("?", 1)[0] != "/status":
            self.enviar_json(404, {"erro": "endpoint desconhecido"})
            return

        self.enviar_json(200, status_payload())

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/restart":
            self.enviar_json(404, {"erro": "endpoint desconhecido"})
            return

        tamanho = int(self.headers.get("Content-Length", "0") or 0)

        try:
            dados = json.loads(self.rfile.read(tamanho).decode("utf-8") or "{}")
        except Exception:
            self.enviar_json(400, {"erro": "json invalido"})
            return

        request_id = str(dados.get("request_id", ""))

        if request_id and request_id in PEDIDOS_TRATADOS:
            self.enviar_json(200, {
                "resultado": "pedido repetido ignorado",
                "status": status_payload(),
            })
            return

        if request_id:
            PEDIDOS_TRATADOS.add(request_id)

        if processo_ok() and not bool(dados.get("force", False)):
            self.enviar_json(200, {
                "resultado": "mongo_mqtt.py ja ativo",
                "status": status_payload(),
            })
            return

        iniciou = reiniciar_processo()

        if iniciou:
            resultado = "mongo_mqtt.py reiniciado"
        else:
            resultado = "mongo_mqtt.py nao iniciado porque o MongoDB nao esta ativo"

        print("--------------------------------------------")
        print(resultado)

        self.enviar_json(200, {
            "resultado": resultado,
            "status": status_payload(),
        })

    def log_message(self, format, *args):
        return


def main():
    port = int(MANAGER.get(PORT_KEY, DEFAULT_PORT))

    threading.Thread(target=monitor_loop, daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    print(f"[gestor PC1] ativo em http://0.0.0.0:{port}, a gerir apenas {SCRIPT}")

    server.serve_forever()


if __name__ == "__main__":
    main()