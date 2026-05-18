import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import mysql.connector

from config_loader import BASE_DIR, load_config

ROLE = "pc2"
SCRIPT = "mqtt_mysql.py"
PORT_KEY = "pc2_port"
DEFAULT_PORT = 8082

CONFIG = load_config()
MANAGER = CONFIG.get("manager", {})
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
            print(f"[gestor PC2] {SCRIPT} parado; a reiniciar")
            iniciar_processo()
        time.sleep(2)


def estado_mysql():
    try:
        mysql_cfg = CONFIG.get("mysql", {})
        conn = mysql.connector.connect(
            host=mysql_cfg.get("host", "127.0.0.1"),
            port=int(mysql_cfg.get("port", 3306)),
            user=mysql_cfg.get("user"),
            password=mysql_cfg.get("password"),
            database=mysql_cfg.get("database", "Marsabirinto"),
            connection_timeout=1,
        )
        conn.close()
        return "OK", None
    except Exception as erro:
        return "ERRO", f"{type(erro).__name__}: {erro}"


def status_payload():
    mysql_estado, mysql_erro = estado_mysql()
    return {
        "pc": ROLE,
        "manager": "OK",
        "processo": SCRIPT,
        "processo_estado": "OK" if processo_ok() else "ERRO",
        "mysql": mysql_estado,
        "mysql_erro": mysql_erro,
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
            self.enviar_json(200, {"resultado": "pedido repetido ignorado", "status": status_payload()})
            return
        if request_id:
            PEDIDOS_TRATADOS.add(request_id)

        if processo_ok() and not bool(dados.get("force", False)):
            self.enviar_json(200, {"resultado": "mqtt_mysql.py ja ativo", "status": status_payload()})
            return

        reiniciar_processo()
        self.enviar_json(200, {"resultado": "mqtt_mysql.py reiniciado", "status": status_payload()})
        print("--------------------------------------------")
        print("PC2 reiniciado")

    def log_message(self, format, *args):
        return


def main():
    port = int(MANAGER.get(PORT_KEY, DEFAULT_PORT))
    threading.Thread(target=monitor_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[gestor PC2] ativo, a gerir {SCRIPT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
