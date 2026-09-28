from machine import I2C
import time

# Bity na PCF8574 -> piny LCD
MASK_RS = 0x01
MASK_RW = 0x02
MASK_E  = 0x04
MASK_BACKLIGHT = 0x08
SHIFT_DATA = 4  # D4-D7 na P4-P7

class I2cLcd:
    def __init__(self, i2c, addr, rows, cols):
        self.i2c = i2c
        self.addr = addr
        self.rows = rows
        self.cols = cols
        self.backlight = MASK_BACKLIGHT
        time.sleep_ms(20)
        self._write_init_nibble(0x03)
        time.sleep_ms(5)
        self._write_init_nibble(0x03)
        time.sleep_us(150)
        self._write_init_nibble(0x03)
        self._write_init_nibble(0x02)  # przełącz w tryb 4-bit

        self._command(0x28)  # 4-bit, 2 linie, 5x8 dots
        self._command(0x08)  # display off
        self._command(0x01)  # clear
        time.sleep_ms(2)
        self._command(0x06)  # entry mode
        self._command(0x0C)  # display on, cursor off

    def _write_byte(self, data):
        self.i2c.writeto(self.addr, bytes([data | self.backlight]))

    def _pulse_enable(self, data):
        self._write_byte(data | MASK_E)
        time.sleep_us(1)
        self._write_byte(data & ~MASK_E)
        time.sleep_us(50)

    def _write_init_nibble(self, nibble):
        data = (nibble << SHIFT_DATA)
        self._write_byte(data)
        self._pulse_enable(data)

    def _write4bits(self, data, rs=0):
        high = (data & 0xF0) | (MASK_RS if rs else 0)
        low = ((data << 4) & 0xF0) | (MASK_RS if rs else 0)
        self._write_byte(high)
        self._pulse_enable(high)
        self._write_byte(low)
        self._pulse_enable(low)

    def _command(self, cmd):
        self._write4bits(cmd, rs=0)

    def _data(self, data):
        self._write4bits(data, rs=1)

    def clear(self):
        self._command(0x01)
        time.sleep_ms(2)

    def move_to(self, col, row):
        row_offsets = [0x00, 0x40, 0x14, 0x54]
        self._command(0x80 | (col + row_offsets[row]))

    def putstr(self, text):
        for char in text:
            if char == '\n':
                continue
            self._data(ord(char))