import serial
import struct


class CoordinateSender:
    def __init__(self, port="COM4", baudrate=19200, timeout=0.1):
        self.ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            timeout=timeout
        )

    def send_coordinates(self, lat, lon):
        START = 0xAA
        CMD = 0x01

        payload = struct.pack("<ff", lat, lon)

        packet = bytearray([START, CMD, len(payload)])
        packet += payload
        packet.append(sum(packet) & 0xFF)

        self.ser.write(packet)

    def read_log(self):
        data = self.ser.read(64)
        if data:
            print(data.decode(errors="ignore"), end="")

    def close(self):
        self.ser.close()


cs = CoordinateSender(port="COM4", baudrate=19200)

# TEST COORDINATES
cs.send_coordinates(42.2626, -71.8023)

while True:
    cs.read_log()

