# USB Logic Analyzer Guide

This guide walks through installing drivers and connecting a USB logic analyzer in PulseView on Windows.

## Prerequisites

1. Run `windows_dependencies.bat`.
2. Confirm these tools are installed:
   - `PulseView` at `C:\Program Files\sigrok\PulseView\pulseview.exe`
   - `sigrok-cli` at `C:\Program Files\sigrok\sigrok-cli\sigrok-cli.exe`
3. You will have to add these tools to your PATH manually.

## 1. Install the USB Driver with Zadig

1. Unplug your logic analyzer.
2. Open **Zadig**.
3. In Zadig, select **Options -> List All Devices**.

![Screenshot of selecting "Options" -> "List All Devices" inside Zadig](Logic_Analyzers_Guide_Resources/Zadig_List_All_Devices.png)

4. Note the current device list, then close Zadig.
5. Plug in the logic analyzer and reopen Zadig.
6. Compare the list and select the new device (for example, `Unknown Device #1`).

![A screenshot of the dropdown list of all available devices](Logic_Analyzers_Guide_Resources/Zadig_Device_List.png)

7. Verify you selected the correct device, then click **Install Driver**.

![Screenshot of the install button highlighted for the selected device](Logic_Analyzers_Guide_Resources/Install_Driver.png)

8. Wait for the install to complete. This can take longer than expected.

![A screenshot of the success dialog after driver installation](Logic_Analyzers_Guide_Resources/Install_Driver_Success.png)

## 2. Connect the Analyzer in PulseView

1. Open **PulseView**.
2. If you see **Demo device**, your analyzer was not auto-detected yet.

![Screenshot of PulseView with Demo Device selected](Logic_Analyzers_Guide_Resources/Demo_Device_Selected.png)

3. Open the device dropdown and click **Connect to Device**.

![Screenshot of PulseView selecting "Connect to Device"](Logic_Analyzers_Guide_Resources/Connect_to_Device_Dropdown.png)

4. Choose the correct driver for your hardware.
   - The [SparkFun USB Logic Analyzer (24 MHz, 8-channel)](https://www.sparkfun.com/usb-logic-analyzer-24mhz-8-channel.html) uses `fx2lafw`.

![Screenshot showing fx2lafw driver selected](Logic_Analyzers_Guide_Resources/Fx2lafw_Driver_Selected.png)

5. Click **Scan for devices using driver above**.

![Screenshot depicting "Scan for devices using driver above"](Logic_Analyzers_Guide_Resources/Scan_Using_Driver.png)

6. Select your analyzer from the scan results and click **OK**.

![Screenshot depicting a logic analyzer being detected and selecting OK](Logic_Analyzers_Guide_Resources/Select_Device_From_Scan.png)

Your analyzer is now ready to capture signals.

## 3. Configure I2C Decoding

1. Set sample configuration first.
   - Recommended starting point: `10 MHz` sample rate for standard I2C debugging.
   - Increase sample rate if you are analyzing faster buses.

![Screenshot of sample rate settings in PulseView](Logic_Analyzers_Guide_Resources/I2C_Sample_Rate_Config.png)

2. Click **Add Protocol Decoder**.

![Button for selecting protocol decoder](Logic_Analyzers_Guide_Resources/Add_Protocol_Decoder_Button.png)

3. Search for `I2C` and double-click it.

![Image showing searching I2C in the decoder menu](Logic_Analyzers_Guide_Resources/I2C_Decoder_Search.png)

4. Confirm the I2C decoder appears in the channel list.

![I2C channel appearing in the main UI window](Logic_Analyzers_Guide_Resources/I2C_Channel_Main_Window_Appearing.png)

5. Configure channel mapping:
   - `SDA` -> data line
   - `SCL` -> clock line
   - Optional: set colors for readability

![Channel configuration window for I2C](Logic_Analyzers_Guide_Resources/I2C_Configure_Channel.png)

## FAQ

### PulseView cannot find my analyzer after unplugging/replugging

1. Unplug and reconnect the analyzer.
2. Re-run the PulseView **Connect to Device** scan.
3. If still missing, reinstall the Zadig driver for that device.
4. Device names can change after reconnecting (for example, channel count display may differ).

## Sources
[Logic Analyzer Used In Guide](https://www.sparkfun.com/usb-logic-analyzer-24mhz-8-channel.html)
[Setting Up Logic Analyzer With Pulseview Guide](https://learn.sparkfun.com/tutorials/using-the-usb-logic-analyzer-with-sigrok-pulseview)
