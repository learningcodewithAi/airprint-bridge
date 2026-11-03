#!/usr/bin/env bash
# Canon AirPrint add-on: installs Canon's UFRII LT driver, sets up the printer
# in CUPS, and announces it on the network so iPhones see it as AirPrint.
set -uo pipefail

OPTIONS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }

PRINTER_IP="$(opt printer_ip)"
PRINTER_NAME="$(opt printer_name)"
PRINTER_DESC="$(opt printer_description)"
PRINTER_LOC="$(opt printer_location)"
DRIVER_URL="$(opt driver_url)"

DRIVER_CACHE=/data/driver
SHARE_DIR=/share/canon
mkdir -p "$DRIVER_CACHE"

log() { echo "[canon-airprint] $*"; }

# ---------- 1. Get Canon's driver (never bundled; license forbids it) ----------
TARBALL="$(ls "$DRIVER_CACHE"/*.tar.gz 2>/dev/null | head -n1 || true)"

if [ -z "$TARBALL" ] && ls "$SHARE_DIR"/*.tar.gz >/dev/null 2>&1; then
  log "Using driver found in /share/canon"
  cp "$(ls "$SHARE_DIR"/*.tar.gz | head -n1)" "$DRIVER_CACHE"/
  TARBALL="$(ls "$DRIVER_CACHE"/*.tar.gz | head -n1)"
fi

if [ -z "$TARBALL" ] && [ -n "$DRIVER_URL" ]; then
  log "Downloading Canon driver from the URL in the add-on options"
  if curl -fL --retry 3 -o "$DRIVER_CACHE/canon-driver.tar.gz" "$DRIVER_URL"; then
    TARBALL="$DRIVER_CACHE/canon-driver.tar.gz"
  else
    log "Download failed. Check driver_url in the Configuration tab."
    rm -f "$DRIVER_CACHE/canon-driver.tar.gz"
  fi
fi

if [ -z "$TARBALL" ]; then
  log "No Canon driver yet."
  log "Paste the download link for 'UFRII LT Printer Driver for Linux' into"
  log "driver_url (Configuration tab), or put the .tar.gz in /share/canon/,"
  log "then restart this add-on. Waiting..."
  sleep infinity
fi

# ---------- 2. Install the driver's 64-bit Debian package ----------
WORK=/tmp/canon-driver
rm -rf "$WORK" && mkdir -p "$WORK"
tar -xzf "$TARBALL" -C "$WORK" || { log "Could not unpack the driver archive."; sleep infinity; }

mapfile -t DEBS < <(find "$WORK" -type f -name '*amd64.deb' | sort)
if [ "${#DEBS[@]}" -eq 0 ]; then
  log "No 64-bit .deb packages found in the driver archive."
  sleep infinity
fi
log "Installing: ${DEBS[*]##*/}"
dpkg -i --force-depends "${DEBS[@]}" >/dev/null 2>&1 || log "dpkg reported warnings (usually fine)."

# ---------- 3. Start D-Bus, Avahi and CUPS ----------
mkdir -p /run/dbus /run/cups /var/spool/cups /var/cache/cups
rm -f /run/dbus/pid
dbus-daemon --system --fork
avahi-daemon --daemonize --no-chroot || log "Avahi failed to start; AirPrint discovery won't work."
/usr/sbin/cupsd
sleep 3

# ---------- 4. Create the printer queue ----------
PPD="$(lpinfo -m 2>/dev/null | grep -i 'LBP6030' | head -n1 | cut -d' ' -f1)"
if [ -z "$PPD" ]; then
  PPD="$(lpinfo -m 2>/dev/null | grep -i 'UFRII LT' | head -n1 | cut -d' ' -f1)"
fi
if [ -z "$PPD" ]; then
  log "Driver installed but no LBP6030 model found. Models offered:"
  lpinfo -m | grep -i canon | head -n 20
  sleep infinity
fi
log "Using driver model: $PPD"

lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
lpadmin -p "$PRINTER_NAME" \
  -v "socket://${PRINTER_IP}:9100" \
  -m "$PPD" \
  -D "$PRINTER_DESC" \
  -L "$PRINTER_LOC" \
  -o printer-is-shared=true \
  -E
lpadmin -d "$PRINTER_NAME"
cupsenable "$PRINTER_NAME"
cupsaccept "$PRINTER_NAME"

log "Ready. '$PRINTER_DESC' is shared as an AirPrint printer."
log "CUPS web page: http://<home-assistant-ip>:631"

# ---------- 5. Stay running; restart if CUPS dies ----------
while pgrep -x cupsd >/dev/null; do sleep 30; done
log "CUPS stopped; exiting so Home Assistant restarts the add-on."
exit 1
