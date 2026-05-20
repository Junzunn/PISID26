import atexit
import json
import os
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime
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
LOG_HANDLE = None
PROCESSO_LOCK = threading.Lock()
LOG_DIR = BASE_DIR / "logs"
LOG_PATH = LOG_DIR / f"{SCRIPT}.log"


RUNTIME_DIR = BASE_DIR / "runtime"
GESTOR_LOCK_PATH = RUNTIME_DIR / "gestor_pc1_nuvem_mongo.lock"
GESTOR_LOCK_FD = None


def _pid_ativo(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except Exception:
        return False


def _ler_primeiro_pid(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            linha = f.readline().strip()
        return int(linha) if linha else None
    except Exception:
        return None


def adquirir_lock_gestor():
    global GESTOR_LOCK_FD
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    while True:
        try:
            GESTOR_LOCK_FD = os.open(str(GESTOR_LOCK_PATH), os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o644)
            os.write(GESTOR_LOCK_FD, f"{os.getpid()}\nstarted_at={datetime.now().isoformat()}\n".encode("utf-8"))
            return
        except FileExistsError:
            pid = _ler_primeiro_pid(GESTOR_LOCK_PATH)
            if pid and _pid_ativo(pid):
                print(f"[gestor PC1 nuvem] ja existe outro gestor ativo pid={pid}; este gestor vai sair", flush=True)
                sys.exit(0)
            try:
                GESTOR_LOCK_PATH.unlink()
            except FileNotFoundError:
                pass


def libertar_lock_gestor():
    global GESTOR_LOCK_FD
    try:
        if GESTOR_LOCK_FD is not None:
            os.close(GESTOR_LOCK_FD)
    except OSError:
        pass
    GESTOR_LOCK_FD = None
    try:
        GESTOR_LOCK_PATH.unlink()
    except FileNotFoundError:
        pass


def _command_of_pid(pid):
    if os.name == "nt":
        return ""
    try:
        r = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, timeout=1)
        return r.stdout.strip()
    except Exception:
        return ""


def _pgrep(pattern):
    if os.name == "nt":
        return []
    try:
        r = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True, timeout=2)
    except Exception:
        return []
    pids = []
    for linha in r.stdout.splitlines():
        try:
            pids.append(int(linha.strip()))
        except ValueError:
            pass
    return pids


def _terminar_pid(pid, motivo, timeout=3.0):
    if pid == os.getpid() or not _pid_ativo(pid):
        return
    print(f"[gestor PC1 nuvem] a terminar processo antigo pid={pid} ({motivo})", flush=True)
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except Exception as erro:
        print(f"[gestor PC1 nuvem] nao foi possivel enviar SIGTERM pid={pid}: {erro}", flush=True)
        return

    limite = time.time() + timeout
    while time.time() < limite:
        if not _pid_ativo(pid):
            return
        time.sleep(0.1)

    if _pid_ativo(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except Exception as erro:
            print(f"[gestor PC1 nuvem] nao foi possivel enviar SIGKILL pid={pid}: {erro}", flush=True)


def limpar_processos_antigos_nuvem():
    processo_atual = PROCESSO.pid if PROCESSO is not None and PROCESSO.poll() is None else None

    for pid in _pgrep("nuvem_mongo.py"):
        if pid in {os.getpid(), processo_atual}:
            continue
        cmd = _command_of_pid(pid)
        if "gestor_pc1_nuvem_mongo.py" in cmd:
            continue
        if "nuvem_mongo.py" in cmd:
            _terminar_pid(pid, "nuvem_mongo.py antigo")

    for pid in _pgrep("mazerun"):
        if pid == os.getpid():
            continue
        cmd = _command_of_pid(pid)
        if "mazerun" in cmd and "grep" not in cmd:
            _terminar_pid(pid, "mazerun antigo/orfao")

    try:
        for lock_file in RUNTIME_DIR.glob("nuvem_mongo*.lock"):
            old_pid = _ler_primeiro_pid(lock_file)
            if not old_pid or not _pid_ativo(old_pid):
                try:
                    lock_file.unlink()
                except FileNotFoundError:
                    pass
        for lock_file in RUNTIME_DIR.glob("mazerun_*.lock"):
            old_pid = _ler_primeiro_pid(lock_file)
            if not old_pid or not _pid_ativo(old_pid):
                try:
                    lock_file.unlink()
                except FileNotFoundError:
                    pass
    except Exception:
        pass


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


def fechar_log_handle():
    global LOG_HANDLE

    if LOG_HANDLE is None:
        return

    try:
        LOG_HANDLE.flush()
        LOG_HANDLE.close()
    except Exception:
        pass
    finally:
        LOG_HANDLE = None


def abrir_log_processo():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = open(LOG_PATH, "a", encoding="utf-8", buffering=1)
    log_file.write("\n==============================\n")
    log_file.write(f"Start: {datetime.now().isoformat()}\n")
    log_file.write(f"Command: {sys.executable} -u {BASE_DIR / SCRIPT}\n")
    log_file.write("==============================\n")
    log_file.flush()
    return log_file


def iniciar_processo():
    global PROCESSO, LOG_HANDLE

    with PROCESSO_LOCK:
        if PROCESSO is not None and PROCESSO.poll() is None:
            return False

        limpar_processos_antigos_nuvem()

        fechar_log_handle()
        LOG_HANDLE = abrir_log_processo()

        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env.setdefault("PYTHONIOENCODING", "utf-8")

        kwargs = {
            "cwd": str(BASE_DIR),
            "stdout": LOG_HANDLE,
            "stderr": subprocess.STDOUT,
            "text": True,
            "bufsize": 1,
            "env": env,
        }
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kwargs["start_new_session"] = True

        PROCESSO = subprocess.Popen(
            [sys.executable, "-u", str(BASE_DIR / SCRIPT)],
            **kwargs,
        )

        LOG_HANDLE.write(f"PID: {PROCESSO.pid}\n")
        LOG_HANDLE.flush()
        print(f"[gestor PC1 nuvem] log do processo: {LOG_PATH}", flush=True)
        return True


def parar_processo():
    global PROCESSO

    with PROCESSO_LOCK:
        if PROCESSO is None or PROCESSO.poll() is not None:
            fechar_log_handle()
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
        finally:
            fechar_log_handle()


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
    adquirir_lock_gestor()
    atexit.register(libertar_lock_gestor)
    port = int(MANAGER.get(PORT_KEY, DEFAULT_PORT))
    threading.Thread(target=monitor_loop, daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[gestor PC1 nuvem] ativo em http://0.0.0.0:{port}, a gerir apenas {SCRIPT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
