# Connect_OmniTrak

Connect_OmniTrak is a MATLAB entry-point function for opening a serial connection to Vulintus OmniTrak-compatible devices and loading a controller structure for device communication.

It is intended for building custom MATLAB workflows around Vulintus behavioral hardware while using the open OmniTrak Serial Communication (OTSC) protocol.

_Disclaimer: Sections of this README file were AI-generated, but checked for accuracy by a human._

---

## What This Function Does

- Selects or accepts a serial COM port.
- Connects at a default baud rate, then attempts higher rates if needed.
- Verifies OTSC communication with the target device.
- Builds and returns a controller structure with loaded OTSC functions.
- Optionally reports progress to a message box, axes, or waitbar.

## Quick Start

### Basic connection

ctrl = Connect_OmniTrak;

This will prompt/select an available serial port (depending on helper behavior), connect, verify OTSC, and return a controller structure.

### Connect to a specific COM port

ctrl = Connect_OmniTrak('port','COM6');

### Capture connected device SKU list

[ctrl, devices] = Connect_OmniTrak;

## Function Signature

[ctrl, varargout] = Connect_OmniTrak(varargin)

Optional name/value parameters:

- port: COM port string (example: COM6)
- msgbox: UI handle for textual progress output (listbox or uitextarea)
- axes: axes or uiaxes handle for graphical progress text
- useserialport: true/false to force newer serialport API or legacy serial API
- device: device type string or cell array of device types

Notes:

- If both msgbox and axes are provided, axes is ignored.
- If no port is chosen, the function returns an empty controller.

## Outputs

- ctrl: Controller structure with stream, device metadata, and OTSC function handles.
- devices: (optional) list of connected device SKU(s) loaded during setup.

## Behavior Summary

- Default baud rate starts at 115200.
- If OTSC verification fails, fallback rates are tested (1000000 and 2000000).
- On successful connection, the function may increase baud rate to device maximum.
- Input/output buffers are flushed before returning.

## Troubleshooting

### Could not open serial connection

Cause:
- COM port is incorrect, unavailable, or in use by another process.

Fix:
- Confirm the device COM port in Device Manager.
- Close other software using that port.
- Retry with explicit port parameter.

### OTSC verification failed

Cause:
- Connected device is not speaking OTSC on the selected port/baud.

Fix:
- Verify hardware and firmware are OTSC-compatible.
- Check USB cable and power.
- Retry after reconnecting the device.

## Compatibility

- MATLAB release behavior is handled internally:
	- Newer releases default to serialport.
	- Older releases fall back to legacy serial.

## License and Copyright

See source header comments in Connect_OmniTrak.m for copyright and update history.
