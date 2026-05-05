# -*- coding: utf-8 -*-
"""
Created on Thu Feb 19 10:53:11 2026

@author: sford
"""

from pathlib import Path

jpg_path = Path("test.jpg")
data = jpg_path.read_bytes()

with open("test_jpeg.c", "w") as f:
    f.write('#include <stdint.h>\n')
    f.write('const uint8_t test_jpeg[] = {\n')
    for i, b in enumerate(data):
        if i % 12 == 0:
            f.write('  ')
        f.write(f'0x{b:02X}, ')
        if i % 12 == 11:
            f.write('\n')
    f.write('\n};\n')
    f.write(f'const uint32_t test_jpeg_len = {len(data)};\n')

with open("test_jpeg.h", "w") as f:
    f.write('#pragma once\n')
    f.write('#include <stdint.h>\n\n')
    f.write('extern const uint8_t test_jpeg[];\n')
    f.write('extern const uint32_t test_jpeg_len;\n')

print(f"Generated test_jpeg.c/.h from {jpg_path} ({len(data)} bytes)")
