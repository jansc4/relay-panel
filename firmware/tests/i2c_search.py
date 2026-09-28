from machine import Pin, I2C

i2c = I2C(1, scl=Pin(27), sda=Pin(26), freq=100000)
devices = i2c.scan()
print("Znaleziono:", [hex(d) for d in devices])