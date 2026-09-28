import socket
from config import MQTT_BROKER

addr = socket.getaddrinfo(MQTT_BROKER, 1883)[0][-1]
print("Adres:", addr)
s = socket.socket()
s.connect(addr)
print("TCP polaczony!")
s.close()