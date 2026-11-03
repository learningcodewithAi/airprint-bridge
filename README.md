# ha-airprint

A Home Assistant add-on repository with one add-on:

- **Canon AirPrint**: shares a Canon UFRII LT printer (like the LBP6030w) as
  an AirPrint printer for iPhones and Macs, using CUPS, Avahi and Canon's
  official Linux driver (downloaded by you on first start, never bundled).

## Install

1. Home Assistant → **Settings → Add-ons → Add-on Store**.
2. Menu (⋮) → **Repositories** → add `https://github.com/learningcodewithAi/ha-airprint`.
3. Install **Canon AirPrint** and follow its Documentation tab.

Requires an amd64 (Intel/AMD) Home Assistant machine, because Canon only
ships its driver for that chip family.
