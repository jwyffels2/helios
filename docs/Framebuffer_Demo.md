# Framebuffer Demo

This document is the reproducible path for the framebuffer / VGA demo on Basys3.

## Hardware

- Use a direct `VGA -> VGA` cable.
- Do not use a passive `VGA -> HDMI` adapter.
- Connect the monitor to the Basys3 VGA port and select the VGA input.

## One-time repo setup

From the repo root:

```powershell
git submodule update --init --recursive
podman machine start
podman build -t helios-build -f ./build.dockerfile .
```

The submodule step is required because the shared Ada build depends on:

- `third_party/helios-neorv32-setups`
- `third_party/min`

## Bitstream

Build and program the framebuffer bitstream:

```powershell
vivado -mode batch -source rtl/build.tcl
vivado -mode batch -source rtl/program.tcl
```

## Build the framebuffer demo application

The framebuffer demo application is the `tests` project. It keeps UART at `19200`
so the bootloader and the demo use the same terminal setting.

From the repo root:

```powershell
podman run --rm -v "${PWD}:/workspace" -w /workspace helios-build ./build_neorv32_project.sh ./tests/bin/tests
```

This generates:

- `tests/bin/tests.exe`

`build_neorv32_project.sh` now skips `alr clean` by default because `alr clean`
is not reliable on this workstation's cached toolchain. If a clean rebuild is
actually needed, use:

```powershell
podman run --rm -v "${PWD}:/workspace" -w /workspace helios-build ./build_neorv32_project.sh --clean ./tests/bin/tests
```

## Upload and run

Open Tera Term at:

- `19200`
- `8N1`
- no flow control

At the NEORV32 bootloader prompt:

1. Press any key to stop autoboot
2. Type `u`
3. Send `tests\bin\tests.exe`
4. Wait for `OK`
5. Type `e`

## Expected UART output

```text
Framebuffer test start
Pattern 1: solid black
Pattern 2: RGBW bars
Pattern 3: checkerboard
Pattern 4: XBUS lane and boundary writes
Framebuffer test complete
```

## Expected monitor output

In order:

1. black screen
2. RGBW color bars
3. checkerboard
4. XBUS lane / boundary write pattern

## If it does not work

- If UART text is correct but video is missing:
  - verify the monitor is on VGA input
  - verify you are using direct VGA, not passive VGA-to-HDMI
- If the build fails with missing MIN or NEORV32 files:
  - rerun `git submodule update --init --recursive`
- If the app build fails during `alr clean`:
  - use the default script path shown above, which does not clean
