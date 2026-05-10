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
TOKEN = MANAGER.get("token", "ALTERAR_ESTA_SENHA")
PEDIDOS_TRATADOS = set()
PROCESSO = None
PROCESSO_LOCK = threading.Lock()


def iniciar_processo():
    global PROCESSO
    with PROCESSO_LOCK:
        if PROCESSO is not None and PROCESSO.poll() is None:
            return False
        PROCESSO = subprocess.Popen([sys.executable, str(BASE_DIR / SCRIPT)], cwd=str(BASE_DIR))
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
    iniciar_processo()


def monitor_loop():
    iniciar_processo()
    while True:
        if not processo_ok():
            print(f"[gestor] {SCRIPT} parado; a reiniciar")
            iniciar_processo()
        time.sleep(2)


def estado_mongo():
    try:
        mongo = CONFIG.get("mongo", {})
        client = MongoClient(mongo.get("uri"), serverSelectionTimeoutMS=800)
        client.admin.command("ping")
        return "OK"
    except (PyMongoError, Exception):
        return "ERRO"


def contagens_mongo():
    try:
        mongo = CONFIG.get("mongo", {})
        client = MongoClient(mongo.get("uri"), serverSelectionTimeoutMS=800)
        db = client[mongo.get("database", "Marsabirinto")]
        col = db["dados_sensores"]
        return {
            "documentos_por_tratar": col.count_documents({"checked": False}),
            "documentos_por_migrar": col.count_documents({"checked": True, "migrated": False}),
        }
    except Exception:
        return {"documentos_por_tratar": None, "documentos_por_migrar": None}


def status_payload():
    payload = {
        "pc": ROLE,
        "processo": SCRIPT,
        "processo_estado": "OK" if processo_ok() else "ERRO",
        "mongo": estado_mongo(),
    }
    payload.update(contagens_mongo())
    return payload


class Handler(BaseHTTPRequestHandler):
    def enviar_json(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

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

        if dados.get("token") != TOKEN:
            self.enviar_json(403, {"erro": "token invalido"})
            return

        request_id = str(dados.get("request_id", ""))
        if request_id and request_id in PEDIDOS_TRATADOS:
            self.enviar_json(200, {"resultado": "pedido repetido ignorado", "status": status_payload()})
            return
        if request_id:
            PEDIDOS_TRATADOS.add(request_id)

        if processo_ok() and not bool(dados.get("force", False)):
            self.enviar_json(200, {"resultado": "processo ja ativo", "status": status_payload()})
            return

        reiniciar_processo()
        self.enviar_json(200, {"resultado": "processo reiniciado", "status": status_payload()})

    def log_message(self, format, *args):
        return


def main():
    port = int(MANAGER.get(PORT_KEY, DEFAULT_PORT))
    threading.Thread(target=monitor_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[gestor] PC1 ativo em http://0.0.0.0:{port}, a gerir {SCRIPT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
