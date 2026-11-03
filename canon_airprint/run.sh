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

# Diagnostics: what does Canon's package want, and what's missing?
for d in "${DEBS[@]}"; do
  log "Package $(dpkg-deb -f "$d" Package) depends on: $(dpkg-deb -f "$d" Depends)"
done
for f in /usr/lib/cups/filter/rastertosfp /usr/lib/cups/filter/*ufr2* /usr/bin/cnpk* /usr/lib*/libcanon* /usr/lib/x86_64-linux-gnu/libcanon*; do
  [ -e "$f" ] || continue
  MISSING="$(ldd "$f" 2>/dev/null | grep 'not found' | awk '{print $1}' | tr '\n' ' ')"
  if [ -n "$MISSING" ]; then
    log "MISSING libraries for $f: $MISSING"
  else
    log "OK: $f"
  fi
done
apt-get check 2>&1 | sed 's/^/[canon-airprint] apt: /' | head -n 20

# Keep CUPS's TLS certificate across restarts/updates, so iPhones don't
# show a "different printer" security warning each time.
mkdir -p /data/cups-ssl
rm -rf /etc/cups/ssl && ln -s /data/cups-ssl /etc/cups/ssl

# Optional detailed logging of print jobs.
if [ "$(opt debug_logging)" = "true" ]; then
  sed -i 's/^LogLevel .*/LogLevel debug/' /etc/cups/cupsd.conf
  log "Detailed CUPS logging is ON."
fi

# Canon's installer starts its own CUPS; stop it so ours starts cleanly.
pkill -x cupsd 2>/dev/null || true
sleep 2

# ---------- 3. Start D-Bus, Avahi and CUPS ----------
mkdir -p /run/dbus /run/cups /var/spool/cups /var/cache/cups /var/log/cups
rm -f /run/dbus/pid /run/avahi-daemon/pid

# Announce only on the home network, not Home Assistant's internal
# Docker networks, or iPhones may try an address they can't reach.
LAN_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -n "$LAN_IF" ]; then
  sed -i '/^allow-interfaces=/d' /etc/avahi/avahi-daemon.conf
  sed -i "/^\[server\]/a allow-interfaces=${LAN_IF}" /etc/avahi/avahi-daemon.conf
  log "Announcing AirPrint on network interface: $LAN_IF ($(ip -4 -o addr show "$LAN_IF" | awk '{print $4}'))"
else
  log "Could not find the home network interface; announcing on all."
fi

dbus-daemon --system --fork
sleep 1
avahi-daemon --daemonize --no-chroot || log "Avahi failed to start; AirPrint discovery won't work."
sleep 1
: > /var/log/cups/error_log
/usr/sbin/cupsd
sleep 3
# Copy CUPS's own log into the add-on log.
tail -n0 -F /var/log/cups/error_log 2>/dev/null | sed -u 's/^/[cups] /' &

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
  -o media=na_letter_8.5x11in \
  -o PageSize=Letter \
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
