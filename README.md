# AirPrint Bridge for Home Assistant

Print from your iPhone, iPad or Mac to a printer that doesn't support
AirPrint, with no app, no PDF tricks, and no computer left on.

AirPrint Bridge is a Home Assistant add-on. It runs your printer's Linux
driver and presents the printer to your Apple devices as a native AirPrint
printer. Network printers stay on Wi-Fi or Ethernet; USB printers plug into
the Home Assistant machine.

It also gives Home Assistant sensors for the printer: **status**, **alerts**
(no paper, paper jam, door open, toner low), **toner level** and **page
count**, so you can get a phone notification when the printer needs
attention.

## Install

[![Add this repository to your Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FlearningcodewithAi%2Fha-airprint)

1. Click the button above, or in Home Assistant go to **Settings → Apps →
   App Store** (Add-on Store in older versions), menu (⋮) → **Repositories**,
   and add `https://github.com/learningcodewithAi/ha-airprint`.
2. Install **AirPrint Bridge**. It's built on your machine, so the first
   install takes a few minutes.
3. In its **Configuration** tab, set at least `printer_name`, `printer_uri`, a
   driver (`driver_url` or `driver_packages`) and `driver_match`. The
   **Documentation** tab explains each one and has a driver table by brand.
4. Start it and wait for `Ready` in the **Log** tab.
5. On your iPhone: Share → Print → pick your printer. Tap **Continue** if a
   one-time security warning appears.

Requires Home Assistant OS or a Supervised install (apps aren't available on
Container or Core installs). Works on Intel/AMD machines and on ARM
(Raspberry Pi, Home Assistant Green). Phones must be on the same network.

### Example configurations

Canon laser with Canon's Linux driver:

```yaml
printer_name: Office Canon
printer_uri: 192.168.1.50
driver_url: https://gdlp01.c-wss.com/gds/0/0100005950/11/linux-UFRIILT-drv-v510-m17n.tar.gz
driver_match: LBP6030
paper_sizes: Letter,Legal
```

Brother laser with a free Debian driver:

```yaml
printer_name: Brother Laser
printer_uri: 192.168.1.60
driver_packages:
  - printer-driver-brlaser
driver_match: HL-L2350
paper_sizes: A4
```

USB printer plugged into the Home Assistant machine:

```yaml
printer_name: Kitchen Printer
printer_uri: usb
driver_packages:
  - hplip
driver_match: DeskJet 2700
```

## Supported printers

Any printer the bridge can reach (on your network, or by USB) that has a Linux
driver: a manufacturer's Linux driver (Canon, Brother and others), one of
Debian's free drivers (HP, Epson, Brother, Samsung/Xerox, Gutenprint), or
driverless IPP Everywhere.

Printers that already support AirPrint don't need this.

### Tested printers

| Printer | Driver | Connection | Machine | Status | Confirmed by |
|---|---|---|---|---|---|
| Canon imageCLASS LBP6030w | Canon UFRII LT V5.10 (`driver_url`) | Wi-Fi (socket) | Intel Mac mini (amd64) | ✅ Works | @learningcodewithAi |

Tried it with another printer? Please
[open an issue](https://github.com/learningcodewithAi/ha-airprint/issues) with
the model, the options you used and whether it worked, and it'll be added
here.

## How it works

```
iPhone / iPad / Mac ──AirPrint──▶ AirPrint Bridge (Home Assistant)
                                   ├─ ippeveprinter: AirPrint front end
                                   └─ CUPS + printer driver ──▶ printer
```

## Notes

- Manufacturer drivers are downloaded by your own add-on from the link you
  provide. They are never included in this repository.
- AirPrint is a trademark of Apple Inc. This project is not affiliated with,
  endorsed by or sponsored by Apple, Canon or any printer manufacturer.

## License

MIT, see [LICENSE](LICENSE). Printer drivers keep their own licenses.
