# Canon AirPrint

Makes a Canon UFRII LT printer (tested target: imageCLASS LBP6030w) show up
as an AirPrint printer on every iPhone, iPad and Mac in the house. It runs
CUPS with Canon's official Linux driver and announces the printer on your
network, the same job a Mac with Printer Sharing used to do.

## First-time setup

Canon's driver can't be included in this add-on (its license forbids
redistribution), so you give the add-on Canon's own download once:

1. Open Canon's page for **UFRII LT Printer Driver for Linux V5.10**
   (https://asia.canon/en/support/0100595001), accept the terms and copy the
   download link. Or download the `.tar.gz` and put it in `/share/canon/`.
2. In this add-on's **Configuration** tab, paste the link into `driver_url`
   and check `printer_ip`.
3. Start the add-on and watch the **Log** tab until it says `Ready`.

The driver is cached in the add-on's own storage, so later restarts don't
download it again.

## Options

| Option | What it is |
|---|---|
| `printer_ip` | The printer's address. Give it a fixed (reserved) IP in your router. |
| `printer_name` | Internal queue name. Letters, numbers, `_` and `-` only. |
| `printer_description` | The name phones show in the printer list. |
| `printer_location` | Optional location shown under the name. |
| `driver_url` | Canon's download link for the Linux driver (UFRII LT or UFR II). |
| `driver_match` | Text that identifies your model in the driver, e.g. `LBP6030`, `MF445`. If nothing matches, the log lists every model the driver contains. |
| `status_sensors` | Publish printer status, alert, toner % and page count to Home Assistant (default on). |
| `paper_sizes` | Paper sizes offered to phones, first one is the default (default `Letter,Legal`). Keeps iPhones from picking e.g. A5 for photos. |
| `debug_logging` | Detailed CUPS job logs in the Log tab, for troubleshooting. |

## Sensors

With `status_sensors` on, the add-on reads the printer's status over the
network every minute (standard Printer MIB via SNMP) and creates:

- `sensor.<printer_name>_status`: idle, printing, warming up, offline
- `sensor.<printer_name>_alert`: OK, or e.g. "No paper", "Paper jam", "Toner low"
- `sensor.<printer_name>_toner`: toner level in %
- `sensor.<printer_name>_pages`: total pages printed

Use them in automations, e.g. a phone alert when the alert sensor isn't OK.

## Other Canon models

Download Canon's Linux driver for your model (UFRII LT or UFR II), paste its
link into `driver_url`, set `driver_match` to your model number, and set
`printer_ip`. Other brands need their own Linux drivers and aren't
supported yet; many newer printers support AirPrint without this add-on.

## Troubleshooting

- CUPS web page: `http://<home-assistant-ip>:631` shows the queue and jobs.
- Printer missing on the iPhone: restart the add-on and check the log for an
  Avahi error.
- Jobs stuck: confirm the printer still answers at `printer_ip` on port 9100
  (the Mac's "HP Jetdirect – Socket" setting uses the same path).
