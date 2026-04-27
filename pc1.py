# pc1.py
import time
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "PISID"   # 如果怕和别人撞 topic，可以改成 A/he76612/test

client = mqtt.Client(client_id="pc1_sender", protocol=mqtt.MQTTv311)

client.connect(BROKER, PORT, keepalive=60)
client.loop_start()

for i in range(1, 68):
    msg = f"Number {i}"
    info = client.publish(TOPIC, payload=msg, qos=1)
    info.wait_for_publish()   # 等待至少送到 broker
    now = time.strftime("%H:%M:%S", time.localtime())
    print(f"[{now}] Enviado：", msg)
    time.sleep(1)

client.loop_stop()
client.disconnect()
print("发送结束")