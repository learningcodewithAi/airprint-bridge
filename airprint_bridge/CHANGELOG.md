# Changelog

## 1.2.1

- AirPrint detection now only trusts the printer's AirPrint announcement, so
  printers without AirPrint (like the Epson ET-2860) are never switched to
  sensors only by mistake.
- If another device already uses the printer's name on your network, the
  bridge shows up as "<name> AirPrint", so phones don't see two look-alikes.

## 1.2.0

- Printers that already support AirPrint are detected. Instead of adding a
  duplicate printer to your phone, the add-on runs **sensors only** (status,
  paper and ink alerts, page count) and tells you so.
- New **Mode** setting: auto (default), bridge (always share) or sensors
  (sensors only).

## 1.1.0

- Setup finds your printer: leave the address empty and the add-on searches
  your network (SNMP) and USB. With one printer it sets itself up; with
  several it lists them.
- Detects the printer's model and picks the matching driver; installs the
  free driver for Brother, HP, Epson, Samsung and Xerox printers.
- Home Assistant notifications when the printer is ready or needs something
  (pick a printer, Canon driver link, no printer found).
- Plain-English names and help text in the Configuration tab.
- The printer name defaults to the printer's model.

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
