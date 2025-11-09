#!/usr/bin/env bash

# Build the image_gen tool
gcc ./third_party/helios-neorv32-setups/neorv32/sw/image_gen/image_gen.c -o image_gen

# Install it (likely needs sudo)
mv image_gen /usr/local/bin/

alr index --update-all
alr update
alr clean
alr build

riscv64-elf-objcopy -O binary ./bin/helios ./bin/helios.bin
truncate -s %4 ./bin/helios.bin
image_gen -app_bin bin/helios.bin bin/helios.exe

[ -f "$PWD/bin/helios.exe" ] || { echo "Error: Could Not Find Compiled Binary at $PWD/bin/helios.exe " >&2; exit 1; }
echo $PWD/bin/helios.exe
