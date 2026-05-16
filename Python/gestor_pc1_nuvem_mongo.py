import json
import os
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from pymongo import MongoClient

from config_loader import BASE_DIR, load_config

ROLE = "pc1"
SCRIPT = "nuvem_mongo.py"
PORT_KEY = "pc1_nuvem_port"
DEFAULT_PORT = 8083

CONFIG = load_config()
MANAGER = CONFIG.get("manager", {})
PEDIDOS_TRATADOS = set()
PROCESSO = None
PROCESSO_LOCK = threading.Lock()


def abrir_mongo():
    mongo_cfg = CONFIG.get("mongo", {})
    client = MongoClient(mongo_cfg.get("uri"), serverSelectionTimeoutMS=500)
    client.admin.command("ping")
    return client


def estado_mongo():
    try:
        client = abrir_mongo()
        client.close()
        return "OK", None
    except Exception as erro:
        return "ERRO", f"{type(erro).__name__}: {erro}"


def iniciar_processo():
    global PROCESSO

    with PROCESSO_LOCK:
        if PROCESSO is not None and PROCESSO.poll() is None:
            return False

        kwargs = {"cwd": str(BASE_DIR)}
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kwargs["start_new_session"] = True

        PROCESSO = subprocess.Popen(
            [sys.executable, str(BASE_DIR / SCRIPT)],
            **kwargs,
        )
        return True


def parar_processo():
    global PROCESSO

    with PROCESSO_LOCK:
        if PROCESSO is None or PROCESSO.poll() is not None:
            return

        if os.name == "nt":
            PROCESSO.terminate()
        else:
            try:
                os.killpg(os.getpgid(PROCESSO.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass

        try:
            PROCESSO.wait(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                PROCESSO.kill()
            else:
                try:
                    os.killpg(os.getpgid(PROCESSO.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
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
            print(f"[gestor PC1 nuvem] {SCRIPT} parado; a reiniciar")
            iniciar_processo()
        time.sleep(2)


def status_payload():
    mongo_estado, mongo_erro = estado_mongo()
    return {
        "pc": ROLE,
        "manager": "OK",
        "processo": SCRIPT,
        "processo_estado": "OK" if processo_ok() else "ERRO",
        "mongo": mongo_estado,
        "mongo_erro": mongo_erro,
        "nota": "Bros, atenção ao reiniciar este processo: se o mazerun ainda estiver ativo, o reinício pode interromper a receção de mensagens do jogo.",
    }


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

        reiniciar_processo()

        print("--------------------------------------------")
        print("nuvem_mongo.py reiniciado")

        self.enviar_json(200, {
            "resultado": "nuvem_mongo.py reiniciado",
            "status": status_payload(),
        })

    def log_message(self, format, *args):
        return


def main():
    port = int(MANAGER.get(PORT_KEY, DEFAULT_PORT))
    threading.Thread(target=monitor_loop, daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[gestor PC1 nuvem] ativo em http://0.0.0.0:{port}, a gerir apenas {SCRIPT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
