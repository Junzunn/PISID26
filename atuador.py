import time
from typing import Optional

import mysql.connector
import paho.mqtt.client as mqtt

# =========================
# Configuracao
# =========================
BROKER = "broker.emqx.io"
PORT = 1883
MQTT_TOPIC_ACTION = "pisid_mazeact"
PLAYER_ID = 5

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "pisid",
}

POLL_INTERVAL_SECONDS = 2

# Alertas que devem originar acao automatica.
ALERT_TEMPERATURE = "ALERTA_TEMPERATURA"
ALERT_SOUND = "ALERTA_SOM"
BLOCK_TEMPERATURE = "BLOQUEIO_TEMPERATURA"
BLOCK_SOUND = "BLOQUEIO_SOM"


class Atuador:
    def __init__(self) -> None:
        self.last_message_id = 0
        self.last_close_all_sim: Optional[int] = None
        self.last_ac_on_sim: Optional[int] = None

        self.mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
        self.mqtt_connected = False

    # =========================
    # MQTT
    # =========================
    def connect_mqtt(self) -> None:
        if self.mqtt_connected:
            return
        self.mqtt_client.connect(BROKER, PORT, 60)
        self.mqtt_client.loop_start()
        self.mqtt_connected = True
        print(f"[MQTT] Ligado a {BROKER}:{PORT}")

    def disconnect_mqtt(self) -> None:
        if not self.mqtt_connected:
            return
        self.mqtt_client.loop_stop()
        self.mqtt_client.disconnect()
        self.mqtt_connected = False
        print("[MQTT] Desligado")

    def publish_close_all(self) -> None:
        payload = f"{{Type: CloseAllDoor, Player: {PLAYER_ID}}}"
        info = self.mqtt_client.publish(MQTT_TOPIC_ACTION, payload, qos=1)
        info.wait_for_publish()
        print(f"[MQTT] Enviado: {payload}")

    def publish_ac_on(self) -> None:
        payload = f"{{Type: AcOn, Player: {PLAYER_ID}}}"
        info = self.mqtt_client.publish(MQTT_TOPIC_ACTION, payload, qos=1)
        info.wait_for_publish()
        print(f"[MQTT] Enviado: {payload}")

    # =========================
    # Base de dados
    # =========================
    def db(self):
        return mysql.connector.connect(**DB_CONFIG)

    def load_last_message_id(self) -> int:
        conn = self.db()
        cur = conn.cursor()
        try:
            cur.execute("SELECT COALESCE(MAX(ID), 0) FROM Mensagens")
            row = cur.fetchone()
            return int(row[0] or 0)
        finally:
            cur.close()
            conn.close()

    def simulation_finished(self, sim_id: int) -> bool:
        conn = self.db()
        cur = conn.cursor()
        try:
            cur.execute(
                "SELECT Estado FROM Simulacao WHERE IDSimulacao = %s",
                (sim_id,),
            )
            row = cur.fetchone()
            if row is None:
                return True
            return row[0] in ("Terminada",)
        finally:
            cur.close()
            conn.close()

    def fetch_new_messages(self):
        conn = self.db()
        cur = conn.cursor(dictionary=True)
        try:
            cur.execute(
                """
                SELECT ID, IDSimulacao, TipoAlerta, Msg, Hora, HoraEscrita
                FROM Mensagens
                WHERE ID > %s
                ORDER BY ID ASC
                """,
                (self.last_message_id,),
            )
            return cur.fetchall()
        finally:
            cur.close()
            conn.close()

    # =========================
    # Regras do atuador
    # =========================
    def should_send_close_all(self, sim_id: int, alert_type: str) -> bool:
        if alert_type not in (BLOCK_TEMPERATURE, BLOCK_SOUND):
            return False
        return self.last_close_all_sim != sim_id

    def should_send_ac_on(self, sim_id: int, alert_type: str) -> bool:
        if alert_type != ALERT_TEMPERATURE:
            return False
        return self.last_ac_on_sim != sim_id

    def mark_close_all_sent(self, sim_id: int) -> None:
        self.last_close_all_sim = sim_id

    def mark_ac_on_sent(self, sim_id: int) -> None:
        self.last_ac_on_sim = sim_id

    def process_message(self, row: dict) -> None:
        msg_id = int(row["ID"])
        sim_id = int(row["IDSimulacao"])
        alert_type = row["TipoAlerta"]

        if alert_type not in (ALERT_TEMPERATURE, BLOCK_TEMPERATURE, BLOCK_SOUND):
            self.last_message_id = msg_id
            return

        if self.simulation_finished(sim_id):
            print(f"[SKIP] sim={sim_id} estado final; alerta {alert_type} ignorado")
            self.last_message_id = msg_id
            return

        if alert_type == ALERT_TEMPERATURE:
            if not self.should_send_ac_on(sim_id, alert_type):
                print(f"[SKIP] sim={sim_id} AcOn ja enviado")
                self.last_message_id = msg_id
                return

            print(f"[MYSQL] ID={msg_id} sim={sim_id} alerta={alert_type} -> comando=AcOn")
            self.publish_ac_on()
            self.mark_ac_on_sent(sim_id)
            self.last_message_id = msg_id
            return

        if alert_type in (BLOCK_TEMPERATURE, BLOCK_SOUND):
            if not self.should_send_close_all(sim_id, alert_type):
                print(f"[SKIP] sim={sim_id} CloseAllDoor ja enviado")
                self.last_message_id = msg_id
                return

            print(f"[MYSQL] ID={msg_id} sim={sim_id} alerta={alert_type} -> comando=CloseAllDoor")
            self.publish_close_all()
            self.mark_close_all_sent(sim_id)
            self.last_message_id = msg_id
            return

    # =========================
    # Ciclo principal
    # =========================
    def run(self) -> None:
        self.last_message_id = self.load_last_message_id()
        print(f"[INIT] Ultimo ID atual em Mensagens: {self.last_message_id}")
        self.connect_mqtt()

        try:
            while True:
                rows = self.fetch_new_messages()
                for row in rows:
                    self.process_message(row)
                time.sleep(POLL_INTERVAL_SECONDS)
        finally:
            self.disconnect_mqtt()


def main() -> None:
    atuador = Atuador()
    atuador.run()


if __name__ == "__main__":
    main()
