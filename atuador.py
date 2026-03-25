import time
import json
from typing import Optional, Tuple

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
# Mantidos simples e alinhados com o SQL atual.
ALERT_TEMPERATURE = "ALERTA_TEMPERATURA"
ALERT_SOUND = "ALERTA_SOM"

# Comandos esperados pelo servidor do labirinto.
CMD_AC_ON = "AcOn"
CMD_CLOSE_ALL = "CloseAllDoor"


class Atuador:
    def __init__(self) -> None:
        self.last_message_id = 0
        self.last_temp_alert_sim: Optional[int] = None
        self.last_sound_alert_sim: Optional[int] = None

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

    def publish_action(self, command: str) -> None:
        payload = command
        info = self.mqtt_client.publish(MQTT_TOPIC_ACTION, payload, qos=1)
        info.wait_for_publish()
        print(f"[MQTT] Enviado para {MQTT_TOPIC_ACTION}: {payload}")

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
                "SELECT DataHoraFim FROM Simulacao WHERE IDSimulacao = %s",
                (sim_id,),
            )
            row = cur.fetchone()
            if row is None:
                return True
            return row[0] is not None
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
    def should_handle_temperature(self, sim_id: int) -> bool:
        # Evita enviar repetidamente AcOn para a mesma simulacao.
        return self.last_temp_alert_sim != sim_id

    def should_handle_sound(self, sim_id: int) -> bool:
        # Evita enviar repetidamente CloseAllDoor para a mesma simulacao.
        return self.last_sound_alert_sim != sim_id

    def map_alert_to_action(self, sim_id: int, alert_type: str) -> Tuple[Optional[str], bool]:
        if alert_type == ALERT_TEMPERATURE:
            return CMD_AC_ON, self.should_handle_temperature(sim_id)

        if alert_type == ALERT_SOUND:
            return CMD_CLOSE_ALL, self.should_handle_sound(sim_id)

        return None, False

    def mark_action_sent(self, sim_id: int, alert_type: str) -> None:
        if alert_type == ALERT_TEMPERATURE:
            self.last_temp_alert_sim = sim_id
        elif alert_type == ALERT_SOUND:
            self.last_sound_alert_sim = sim_id

    def process_message(self, row: dict) -> None:
        msg_id = int(row["ID"])
        sim_id = int(row["IDSimulacao"])
        alert_type = row["TipoAlerta"]

        command, should_send = self.map_alert_to_action(sim_id, alert_type)
        if command is None:
            self.last_message_id = msg_id
            return

        if self.simulation_finished(sim_id):
            print(f"[SKIP] sim={sim_id} terminada; alerta {alert_type} ignorado")
            self.last_message_id = msg_id
            return

        if not should_send:
            print(f"[SKIP] sim={sim_id} alerta repetido {alert_type}")
            self.last_message_id = msg_id
            return

        print(f"[MYSQL] ID={msg_id} sim={sim_id} alerta={alert_type} -> comando={command}")
        self.publish_action(command)
        self.mark_action_sent(sim_id, alert_type)
        self.last_message_id = msg_id

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
