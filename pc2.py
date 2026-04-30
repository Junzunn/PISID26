# pc2.py
import time
import os
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "PISID"
CLIENT_ID = "pc22_receiver"

# monitorizar o processamento lento
PROCESS_DELAY_SECONDS = 0

# monitorizar que o pc2 morre depois de receber #nr de mensagens
CRASH_AFTER_COUNT = None

recv_count = 0


def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("session present =", flags.get("session present", 0))
        client.subscribe(TOPIC, qos=1)
    else:
        print("Eroo na ligacao，rc =", rc)


def on_message(client, userdata, msg):
    global recv_count
    #recv_count += 1
    text = msg.payload.decode("utf-8", errors="ignore")
    now = time.strftime("%H:%M:%S", time.localtime())

    print(f"[{now}] | qos={msg.qos} | Mensagem recebida={text}")

    if recv_count == 16:
        print("---- pc2  sleep  17 seg ----")
        time.sleep(17)
        print("---- pc2 recuperou ----")

    #
    if PROCESS_DELAY_SECONDS > 0:
        time.sleep(PROCESS_DELAY_SECONDS)

    #
    if CRASH_AFTER_COUNT is not None and recv_count >= CRASH_AFTER_COUNT:
        print("pc2 foi interrompido")
        os._exit(0)


client = mqtt.Client(
    client_id=CLIENT_ID,
    clean_session=False,
    protocol=mqtt.MQTTv311
)

client.on_connect = on_connect
client.on_message = on_message
client.reconnect_delay_set(min_delay=1, max_delay=5)

client.connect(BROKER, PORT, keepalive=60)
client.loop_forever()