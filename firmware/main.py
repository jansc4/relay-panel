import network
import time
import ujson
from machine import I2C, Pin
from umqtt.simple import MQTTClient
from config import WIFI_SSID, WIFI_PASS, MQTT_BROKER, DEVICE_ID

I2C_ADDR = 0x21
i2c = I2C(1, scl=Pin(27), sda=Pin(26), freq=100000)

relay_state = 0xFF  # wszystko wyłączone (active-low)
i2c.writeto(I2C_ADDR, bytes([relay_state]))

TOPIC_CMD = f"home/{DEVICE_ID}/relay/set".encode()
TOPIC_STATUS = f"home/{DEVICE_ID}/status".encode()

def wifi_connect():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.connect(WIFI_SSID, WIFI_PASS)
    while not wlan.isconnected():
        time.sleep(0.5)
    print("WiFi OK:", wlan.ifconfig())

def set_relay(index, state):
    """index: 0-7, state: True=wł, False=wył"""
    global relay_state
    if state:
        relay_state &= ~(1 << index)
    else:
        relay_state |= (1 << index)
    i2c.writeto(I2C_ADDR, bytes([relay_state]))

def on_message(topic, msg):
    try:
        data = ujson.loads(msg)
        idx = data["relay"]
        state = data["state"]
        set_relay(idx, state)
        client.publish(TOPIC_STATUS, f"relay {idx} -> {'ON' if state else 'OFF'}")
        print(f"relay {idx} -> {state}")
    except Exception as e:
        client.publish(TOPIC_STATUS, f"ERR {e}")
        print("Blad:", e)

wifi_connect()
time.sleep(1)  # daj stosowi sieciowemu chwilę na ustabilizowanie się po WiFi

client = MQTTClient(DEVICE_ID, MQTT_BROKER)
client.set_callback(on_message)

for attempt in range(5):
    try:
        client.connect()
        print("MQTT polaczony")
        break
    except OSError as e:
        print(f"Proba {attempt + 1} nieudana: {e}")
        time.sleep(2)
else:
    raise RuntimeError("Nie udalo sie polaczyc z MQTT po 5 probach")

client.subscribe(TOPIC_CMD)
client.publish(TOPIC_STATUS, "online")
print("Nasluchuje:", TOPIC_CMD)

while True:
    client.wait_msg()