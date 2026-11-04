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

1. In Home Assistant: **Settings → Apps → App Store** (called Add-on Store in
   older versions).
2. Menu (⋮) → **Repositories** → add
   `https://github.com/learningcodewithAi/ha-airprint`
3. Install **AirPrint Bridge** and follow its **Documentation** tab.

Works on Intel/AMD machines and on ARM (Raspberry Pi, Home Assistant Green).

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
