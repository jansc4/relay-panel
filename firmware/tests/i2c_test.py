from machine import I2C, Pin
from lcd import I2cLcd

i2c = I2C(1, scl=Pin(27), sda=Pin(26), freq=100000)
lcd = I2cLcd(i2c, 0x27, 2, 16)  # dopasuj rows,cols jeśli inny rozmiar
lcd.putstr("Pico dziala!")