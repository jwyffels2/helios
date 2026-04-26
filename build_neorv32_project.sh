#!/usr/bin/env bash
set -euo pipefail

# This script runs inside the helios-build container. It receives the expected
# ELF path (for example ./bin/helios or ./tests/bin/tests), builds the matching
# Alire project, converts the ELF to a raw binary, then wraps it with NEORV32's
# image_gen tool so the result can be loaded by the processor boot flow.
#
# The important detail is that bin/ may not exist yet when this script starts.
# Alire creates that directory during `alr build`, so path resolution must infer
# the project directory from the requested ELF path without `cd`ing into bin/.

# Always resolve paths relative to the script location (repo root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_GEN_SRC="$SCRIPT_DIR/third_party/helios-neorv32-setups/neorv32/sw/image_gen/image_gen.c"
IMAGE_GEN_BIN="/usr/local/bin/image_gen"

usage() {
  echo "Usage: ./build_neorv32_project.sh <elf_path>" >&2
  echo "  example: ./build_neorv32_project.sh ./bin/helios" >&2
  echo "  example: ./build_neorv32_project.sh ./tests/bin/tests" >&2
  exit 1
}

main() {
  if [ "$#" -ne 1 ]; then
    usage
  fi

  local elf_input="$1"
  elf_input="${elf_input%/}"

  # Infer project_dir without requiring bin/ to exist before alr build creates it.
  # Examples:
  #   ./bin/helios       -> project_dir=$SCRIPT_DIR,         elf_rel_path=bin/helios
  #   ./tests/bin/tests  -> project_dir=$SCRIPT_DIR/tests,   elf_rel_path=bin/tests
  local elf_dir elf_name project_dir
  elf_input="${elf_input#./}"
  elf_dir="$(dirname "$elf_input")"
  elf_name="$(basename "$elf_input")"

  if [ "$elf_dir" = "bin" ]; then
    project_dir="$SCRIPT_DIR"
  elif [ "${elf_dir%/bin}" != "$elf_dir" ]; then
    project_dir="$SCRIPT_DIR/${elf_dir%/bin}"
  else
    echo "Error: ELF path must point to a bin directory: $elf_input" >&2
    exit 1
  fi

  # Path to ELF relative to project_dir. Alire projects in this repo write their
  # executables under project-local bin/, so this path is stable after build.
  local elf_rel_path
  elf_rel_path="bin/$elf_name"

  # Build and install image_gen from the checked-out NEORV32 sources. image_gen
  # converts the raw RISC-V binary into the executable image format consumed by
  # the NEORV32 bootloader.
  cd "$SCRIPT_DIR"
  gcc "$IMAGE_GEN_SRC" -o image_gen
  mv image_gen "$IMAGE_GEN_BIN"

  # Run Alire steps inside the selected project directory. For normal builds
  # this is the repo root; for --test builds it is tests/.
  cd "$project_dir"
  alr index --update-all
  alr update
  alr clean
  alr build

  # Now do ELF -> .bin -> .exe in the project dir.
  # The explicit existence check catches failed builds before objcopy/image_gen
  # produce confusing follow-on errors.
  if [ ! -f "$elf_rel_path" ]; then
    echo "Error: ELF not found at $(pwd)/$elf_rel_path" >&2
    exit 1
  fi

  local dir_name bin_path exe_path
  dir_name="$(dirname "$elf_rel_path")"        # bin
  bin_path="${dir_name}/${elf_name}.bin"
  exe_path="${dir_name}/${elf_name}.exe"

  riscv64-elf-objcopy -O binary "$elf_rel_path" "$bin_path"
  # Pad the raw binary to a 4-byte boundary because the NEORV32 image generator
  # and boot flow expect word-aligned payloads.
  truncate -s %4 "$bin_path"
  image_gen -i "$bin_path" -o "$exe_path" -t app_bin

  if [ ! -f "$exe_path" ]; then
    echo "Error: Could not find generated exe at $(pwd)/$exe_path" >&2
    exit 1
  fi

  echo "$(pwd)/$exe_path"
}

main "$@"
