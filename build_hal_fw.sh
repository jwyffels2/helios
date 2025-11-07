#!/usr/bin/env bash

# Remember where we started
originalPath="$PWD"

# Build the image_gen tool
gcc ./third_party/helios-neorv32-setups/neorv32/sw/image_gen/image_gen.c -o image_gen

# Install it (likely needs sudo)
mv image_gen /usr/local/bin/

# Go to neorv32-hal root
cd ./third_party/helios-neorv32-setups/neorv32-hal/

# Clean and build with alr
alr build

# Build demo app binaries
cd ./demos
sh ./build_app_bin.sh

# Return to original directory
cd "$originalPath"
executablePath="$originalPath/third_party/helios-neorv32-setups/neorv32-hal/demos/bin/bios.exe"
[ -f $executablePath ] || { echo "Error: Could Not Find Compiled Binary at $executablePath " >&2; exit 1; }
echo $executablePath
