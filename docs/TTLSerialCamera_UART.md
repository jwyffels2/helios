# TTL Serial Camera UART

This branch uses the GNAT Academic USART layering pattern:

- `Usart_Types`, `Usart_Control`, `Usart_Data`, and `Usart_Interface` mirror the generic USART API shape from `usart_generic`.
- `Neorv32_UART1` is the concrete NEORV32 driver layer, analogous to the STM32G4 concrete USART driver.
- `Neorv32rb` is the board package, analogous to the Nucleo board package. It owns the TTL camera UART device.
- `Camera_Usart` binds the generic API to the NEORV32 UART1 implementation.
- `TTL_Serial_Camera` is the camera-facing wrapper used by `Helios`.

## Hardware Mapping

UART0 remains the Basys3 USB-UART console and bootloader path.

UART1 is reserved for the TTL serial camera:

| Signal | Basys3 | FPGA Pin | Connects To |
| --- | --- | --- | --- |
| `ttl_camera_rxd_i` | `JA1` | `J1` | camera `TX` |
| `ttl_camera_txd_o` | `JA2` | `L2` | camera `RX` |
| `GND` | any PMOD `GND` | n/a | camera `GND` |

Cross the UART data wires: camera `TX` goes to FPGA `RX`, and camera `RX` goes to FPGA `TX`.

Use only `3.3V` TTL logic on these PMOD pins.

## Current Default

`TTL_Serial_Camera.Default_Config` is `38400 8N1` with no flow control.
Change the baud rate there if the camera module is configured for a different
TTL UART speed.
