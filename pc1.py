# pc1.py
import time
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "msgPHP"
client = mqtt.Client(client_id="pc1_sender", protocol=mqtt.MQTTv311)

client.connect(BROKER, PORT, keepalive=60)
client.loop_start()

for i in range(1, 68):
    msg = i
    info = client.publish(TOPIC, payload=msg, qos=1)
    info.wait_for_publish()
    now = time.strftime("%H:%M:%S", time.localtime())
    print(f"[{now}] Enviado：", msg)
    time.sleep(1)

client.loop_stop()
client.disconnect()
print("发送结束")