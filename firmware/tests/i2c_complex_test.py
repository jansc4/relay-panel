from machine import I2C, Pin
import time
from lcd import I2cLcd




i2c = I2C(1, scl=Pin(27), sda=Pin(26), freq=100000)
lcd = I2cLcd(i2c, 0x27, 2, 16)  # dopasuj rows,cols jeśli inny rozmiar
lcd.putstr("Pico dziala!")
addr = 0x21
time.sleep(1)
i2c.writeto(addr, bytes([0xFF]))  # wszystko wyłączone

for bit in range(8):
    mask = 0xFF & ~(1 << bit)  # zeruj tylko jeden bit
    lcd.clear()
    print(f"Testuję bit {bit} (IN{bit+1})")
    lcd.putstr(f"Testuję (IN{bit+1})")
    i2c.writeto(addr, bytes([mask]))
    time.sleep(2)
    lcd.clear()
    i2c.writeto(addr, bytes([0xFF]))
    time.sleep(0.5)


