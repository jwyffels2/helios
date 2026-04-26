#!/usr/bin/env bash
set -euo pipefail

# Always resolve paths relative to the script location (repo root)
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

  # Path to ELF relative to project_dir (we assume it's always bin/<name>)
  local elf_rel_path
  elf_rel_path="bin/$elf_name"

  # Build & install image_gen from repo root (SCRIPT_DIR)
  cd "$SCRIPT_DIR"
  gcc "$IMAGE_GEN_SRC" -o image_gen
  mv image_gen "$IMAGE_GEN_BIN"

  # Run Alire steps inside the project dir
  cd "$project_dir"
  alr index --update-all
  alr update
  alr clean
  alr build

  # Now do ELF -> .bin -> .exe in the project dir
  if [ ! -f "$elf_rel_path" ]; then
    echo "Error: ELF not found at $(pwd)/$elf_rel_path" >&2
    exit 1
  fi

  local dir_name bin_path exe_path
  dir_name="$(dirname "$elf_rel_path")"        # bin
  bin_path="${dir_name}/${elf_name}.bin"
  exe_path="${dir_name}/${elf_name}.exe"

  riscv64-elf-objcopy -O binary "$elf_rel_path" "$bin_path"
  truncate -s %4 "$bin_path"
  image_gen -i "$bin_path" -o "$exe_path" -t app_bin

  if [ ! -f "$exe_path" ]; then
    echo "Error: Could not find generated exe at $(pwd)/$exe_path" >&2
    exit 1
  fi

  echo "$(pwd)/$exe_path"
}

main "$@"
