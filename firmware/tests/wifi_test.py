import network
import time

from config import WIFI_SSID, WIFI_PASS as WIFI_PASSWORD

wlan = network.WLAN(network.STA_IF)
wlan.active(True)
wlan.connect(WIFI_SSID, WIFI_PASSWORD)

print("Łączenie", end="")
timeout = 15
while not wlan.isconnected() and timeout > 0:
    print(".", end="")
    time.sleep(1)
    timeout -= 1

if wlan.isconnected():
    print("\nOK:", wlan.ifconfig())
    import mip
    mip.install("github:dhylands/python_lcd/lcd_api.py")
    mip.install("github:dhylands/python_lcd/pico_i2c_lcd.py")
    print("Połączono z WiFi, zainstalowano biblioteki LCD")
else:
    print("\nNie połączono, status:", wlan.status())