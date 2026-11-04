# AirPrint Bridge

> **Beta.** If you try it with a new printer, please send a
> [printer report](https://github.com/learningcodewithAi/airprint-bridge/issues/new?template=printer-report.yml).

AirPrint Bridge makes a printer that doesn't support AirPrint show up on
every iPhone, iPad and Mac on your network, like a native AirPrint printer.
It runs on your Home Assistant machine, so it's always on. The printer stays
where it is: on your network, or plugged into the Home Assistant machine by
USB.

It also adds sensors for the printer's status, alerts (no paper, jam, toner
low), toner level and page count.

## How it works

1. **CUPS** and your printer's **Linux driver** do the actual printing.
2. A small **AirPrint front end** (`ippeveprinter`, from CUPS) announces the
   printer to your devices and tells them exactly which paper is loaded.
3. Each job from a phone goes to CUPS, through the driver, to the printer.

## Setup

For most printers, setup is: **install, start, print.**

1. Turn the printer on. For a USB printer, plug it into the Home Assistant
   machine.
2. Start the add-on and open the **Log** tab. With the **Printer address**
   left empty, the add-on looks for printers on your network and USB:
   - **One printer found:** it's set up by itself. For Brother, HP, Epson,
     Samsung and Xerox, the right free driver is installed automatically.
     A notification (bell icon) tells you when it's ready.
   - **More than one found:** a notification lists them. Copy the address of
     yours into **Printer address** and restart the add-on.
   - **Canon:** Canon's driver can't be downloaded automatically. The
     notification explains how to paste Canon's download link into **Driver
     download link**.
3. On your phone: Share → Print → Printer, and pick your printer. Tap
     **Continue** if a one-time security warning appears.

If your printer isn't found (some printers don't answer the search), type its
address into **Printer address**.

**Network printers only** (USB printers don't need these):

- **Required: give the printer a fixed IP address.** Reserve its address in
  your router ("DHCP reservation" or "reserved IP"). If the address changes,
  printing and the sensors stop working.
- **Recommended: turn off the printer's sleep (or auto power-off).** A
  sleeping printer can show as offline and trigger false alerts. Printing
  still works with sleep on.

## Options

| Option | What it does |
|---|---|
| `printer_name` | The name phones show, e.g. `Office Laser`. Empty: the printer's model name. |
| `printer_uri` | Where the printer is. Empty: found automatically. Or an address like `192.168.1.50` (raw port 9100), a full URI (`socket://…:9100`, `lpd://…/queue`, `ipp://…/ipp/print`), or `usb` for the first USB printer. |
| `printer_location` | Optional text shown under the name, e.g. `Office`. |
| `driver_url` | Link to the manufacturer's Linux driver (`.deb`, or `.tar.gz`/`.zip` containing `.deb` files). |
| `driver_packages` | Debian driver packages to install, e.g. `printer-driver-brlaser`. Empty: chosen automatically for Brother, HP, Epson, Samsung and Xerox. |
| `driver_match` | Empty: detected from the printer. Or part of the model name as the driver lists it, e.g. `LBP6030`. Use `everywhere` for driverless printing. |
| `paper_sizes` | Paper in your tray. The first one is the default: `Letter`, `Legal`, `A4`, `A5` (e.g. `Letter,Legal` or `A4`). |
| `color` | Turn on for color printers. |
| `duplex` | Turn on if the printer prints on both sides automatically. |
| `status_sensors` | Publish printer status to Home Assistant (network printers). |
| `airprint_port` | Port for the AirPrint printer (default `8631`). |
| `debug_logging` | Detailed logs for troubleshooting. |

If `driver_match` doesn't match anything, the log lists every model the
installed drivers support, so you can copy the right text.

## Choosing a driver

| Your printer | `driver_packages` | `driver_url` | `driver_match` example |
|---|---|---|---|
| Canon laser (imageCLASS / i-SENSYS, "UFRII LT" or "UFR II") | | Canon's "UFRII LT (or UFR II) Printer Driver for Linux" link | `LBP6030` |
| Canon PIXMA inkjet | | Canon's "IJ Printer Driver" for Linux link | `G3010` |
| Brother laser | `printer-driver-brlaser` | | `HL-L2350` |
| HP (most models) | `hplip` | | `LaserJet Pro M15` |
| Epson inkjet | `printer-driver-escpr` | | `ET-2720` |
| Samsung / Xerox (older lasers) | `printer-driver-splix` | | `ML-2160` |
| Many others | `printer-driver-gutenprint` | | your model |
| Printer already speaks IPP Everywhere | | | `everywhere` (with an `ipp://` printer_uri) |

To get a link for `driver_url`: open the manufacturer's download page, accept
the terms, start the download, and copy the download's address. Or download
the file and put it in `/share/airprint_bridge/` (a file there is used
instead of the link). Manufacturer drivers are downloaded by your own add-on
and are never included in this project.

**Raspberry Pi / Home Assistant Green (ARM):** Debian driver packages work.
Manufacturer drivers work only if the download includes an ARM (`arm64`)
package; the log says so if it doesn't.

## Sensors

For network printers, the add-on reads the printer's status every minute
(standard Printer MIB over SNMP) and creates:

- `sensor.<name>_status`: idle, printing, warming up, offline
- `sensor.<name>_alert`: `OK`, or e.g. `No paper`, `Paper jam`, `Toner low`
- `sensor.<name>_toner`: toner/ink level in % (first cartridge)
- `sensor.<name>_pages`: total pages printed

`<name>` is `printer_name` in lowercase with underscores, e.g.
`office_laser`. An automation can send a phone notification when the alert
sensor isn't `OK`.

## Troubleshooting

- **Printer doesn't appear on the phone:** make sure the phone is on the same
  network (not a guest network). Restart the add-on and check the log for an
  Avahi error.
- **A duplicate printer appears:** another computer is sharing the same
  printer. The log names it; turn off Printer Sharing there.
- **"Security warning" on the phone:** expected once after first install.
  Tap Continue.
- **Job waits forever or the printer blinks "no paper":** check `paper_sizes`
  matches the paper in the tray.
- **Pages come out blank or garbled:** the driver doesn't fit this model. Try
  another `driver_match` from the list in the log.
- **Status pages:** `http://<home-assistant-ip>:8631/` (AirPrint printer) and
  `http://<home-assistant-ip>:631/` (CUPS engine).
