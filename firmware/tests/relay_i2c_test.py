from machine import I2C, Pin
import time

i2c = I2C(1, scl=Pin(27), sda=Pin(26), freq=100000)
addr = 0x21

i2c.writeto(addr, bytes([0xFF]))  # wszystko wyłączone

for bit in range(8):
    mask = 0xFF & ~(1 << bit)  # zeruj tylko jeden bit
    print(f"Testuję bit {bit} (IN{bit+1})")
    i2c.writeto(addr, bytes([mask]))
    time.sleep(2)
    i2c.writeto(addr, bytes([0xFF]))
    time.sleep(0.5)