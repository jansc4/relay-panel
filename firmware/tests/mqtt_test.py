import network
import time
import ujson
from umqtt.simple import MQTTClient

from config import WIFI_SSID, WIFI_PASS, MQTT_BROKER, DEVICE_ID

TOPIC_CMD = f"home/{DEVICE_ID}/cmd".encode()
TOPIC_STATUS = f"home/{DEVICE_ID}/status".encode()

def wifi_connect():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.connect(WIFI_SSID, WIFI_PASS)
    while not wlan.isconnected():
        time.sleep(0.5)
    print("WiFi OK:", wlan.ifconfig())

def on_message(topic, msg):
    print("Odebrano:", topic, msg)
    client.publish(TOPIC_STATUS, f"echo: {msg.decode()}")

wifi_connect()

client = MQTTClient(DEVICE_ID, MQTT_BROKER)
client.set_callback(on_message)
client.connect()
client.subscribe(TOPIC_CMD)
client.publish(TOPIC_STATUS, "online")
print("Subskrybuję:", TOPIC_CMD)

while True:
    client.wait_msg()