# Changelog

## 1.0.0

First public release as **AirPrint Bridge** (formerly the Canon-only
"Canon AirPrint" add-on).

- Real AirPrint front end (`ippeveprinter`) that declares the paper loaded in
  the tray, so iPhones show the right paper sizes.
- Any printer with a Linux driver: manufacturer drivers by link or file
  (`.deb`, `.tar.gz`, `.zip`), Debian driver packages, or driverless
  IPP Everywhere.
- Network printers (raw/socket, LPD, IPP) and USB printers.
- Color and two-sided printing options.
- Runs on Intel/AMD (amd64) and ARM (aarch64: Raspberry Pi, Home Assistant
  Green).
- Printer status sensors: status, alert, toner level, page count.
- Stable printer identity and TLS keys across restarts and updates.
