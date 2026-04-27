# pc2.py
import time
import os
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "PISID"   # 要和 pc1 一样
CLIENT_ID = "pc2_receiver"

# 模拟“处理慢”
PROCESS_DELAY_SECONDS = 0

# 模拟“程序突然断掉”
# 例如改成 10，表示收到第 10 条后直接退出
CRASH_AFTER_COUNT = None

recv_count = 0


def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("session present =", flags.get("session present", 0))
        client.subscribe(TOPIC, qos=1)
    else:
        print("连接失败，rc =", rc)


def on_message(client, userdata, msg):
    global recv_count
    recv_count += 1
    text = msg.payload.decode("utf-8", errors="ignore")
    now = time.strftime("%H:%M:%S", time.localtime())

    print(f"[{now}] | qos={msg.qos} | Mensagem recebida={text}")

    if recv_count == 16:
        print("---- pc2  sleep  17 seg ----")
        time.sleep(17)
        print("---- pc2 恢复正常 ----")

    # 模拟接收端很慢
    if PROCESS_DELAY_SECONDS > 0:
        time.sleep(PROCESS_DELAY_SECONDS)

    # 模拟程序突然崩掉/被杀
    if CRASH_AFTER_COUNT is not None and recv_count >= CRASH_AFTER_COUNT:
        print("模拟 pc2 直接退出")
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