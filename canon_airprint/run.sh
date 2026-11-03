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
for f in /usr/lib/cups/filter/rastertosfp /usr/lib/cups/filter/*ufr2* /usr/bin/cnpk* /usr/lib*/libcanon* /usr/lib/x86_64-linux-gnu/libcanon*; do
  [ -e "$f" ] || continue
  MISSING="$(ldd "$f" 2>/dev/null | grep 'not found' | awk '{print $1}' | tr '\n' ' ')"
  [ -n "$MISSING" ] && log "MISSING libraries for $f: $MISSING"
done

# Keep CUPS's TLS certificate across restarts/updates, so iPhones don't
# show a "different printer" security warning each time.
mkdir -p /data/cups-ssl
rm -rf /etc/cups/ssl && ln -s /data/cups-ssl /etc/cups/ssl

# Optional detailed logging of print jobs.
if [ "$(opt debug_logging)" = "true" ]; then
  sed -i 's/^LogLevel .*/LogLevel debug/' /etc/cups/cupsd.conf
  log "Detailed CUPS logging is ON."
fi

# Don't let CUPS read tray contents from the printer over SNMP: the printer
# reports A4/A5 and iPhones then only offer those sizes.
printf 'Address @LOCAL\nCommunity disabled-by-canon-airprint\n' > /etc/cups/snmp.conf

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
DRIVER_MATCH="$(opt driver_match)"
DRIVER_MATCH="${DRIVER_MATCH:-LBP6030}"
log "Looking for printer model matching: $DRIVER_MATCH"
PPD="$(lpinfo -m 2>/dev/null | grep -iF "$DRIVER_MATCH" | head -n1 | cut -d' ' -f1)"
if [ -z "$PPD" ]; then
  PPD="$(lpinfo -m 2>/dev/null | grep -i 'UFRII LT' | head -n1 | cut -d' ' -f1)"
fi
if [ -z "$PPD" ]; then
  log "Driver installed but no model matching '$DRIVER_MATCH'. Models in this driver:"
  lpinfo -m 2>/dev/null | grep -v -i -E '^(drv:|everywhere|lsb/)' | head -n 60 | sed 's/^/[canon-airprint]   /'
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
# Offer only the paper sizes actually in the tray, so iPhones don't pick
# something like A5 for photos and leave the printer waiting for paper.
PAPER_SIZES="$(opt paper_sizes)"
PAPER_SIZES="${PAPER_SIZES:-Letter,Legal}"
PPD_FILE="/etc/cups/ppd/${PRINTER_NAME}.ppd"
if [ -f "$PPD_FILE" ]; then
  awk -v KEEP="$PAPER_SIZES" -f /trim_ppd.awk "$PPD_FILE" > /tmp/trimmed.ppd
  if grep -q "^\*PageSize ${PAPER_SIZES%%,*}[/:]" /tmp/trimmed.ppd; then
    lpadmin -p "$PRINTER_NAME" -P /tmp/trimmed.ppd
    log "Paper sizes offered: $PAPER_SIZES"
  else
    log "Paper size '${PAPER_SIZES%%,*}' not in the driver; keeping all sizes."
  fi
fi

# The CUPS queue is now only the "engine" (Canon driver -> printer). It is not
# shared on the network; the AirPrint front end below is what phones see.
lpadmin -p "$PRINTER_NAME" -o printer-is-shared=false
lpadmin -d "$PRINTER_NAME"
cupsenable "$PRINTER_NAME"
cupsaccept "$PRINTER_NAME"

# ---------- 5. AirPrint front end (what iPhones, iPads and Macs see) ----------
mkdir -p /run/canon-airprint /data/ippeve-spool
echo "$PRINTER_NAME" > /run/canon-airprint/queue
echo "${PAPER_SIZES%%,*}" > /run/canon-airprint/default_size
/make_attrs.sh "$PAPER_SIZES" > /run/canon-airprint/attrs.conf || {
  log "Could not build the paper list for '$PAPER_SIZES'."; sleep infinity; }

IPPEVE="$(command -v ippeveprinter || ls /usr/sbin/ippeveprinter /usr/bin/ippeveprinter 2>/dev/null | head -n1)"
if [ -z "$IPPEVE" ]; then
  log "ippeveprinter is missing from this image; AirPrint can't start."
  sleep infinity
fi

AIRPRINT_PORT="$(opt airprint_port)"; AIRPRINT_PORT="${AIRPRINT_PORT:-8631}"
MAKE="$(opt printer_make)"; MAKE="${MAKE:-Canon}"
MODEL="$(opt printer_model)"; MODEL="${MODEL:-$PRINTER_DESC}"

start_airprint() {
  "$IPPEVE" \
    -p "$AIRPRINT_PORT" \
    -n canon-airprint.local \
    -M "$MAKE" -m "$MODEL" \
    -l "$PRINTER_LOC" \
    -s 18,0 \
    -f application/pdf,image/jpeg,image/png,image/pwg-raster,image/urf \
    -a /run/canon-airprint/attrs.conf \
    -c /print_job.sh \
    -d /data/ippeve-spool \
    -r _print,_universal \
    "$PRINTER_DESC" 2>&1 | sed -u 's/^/[airprint] /' &
}
start_airprint
sleep 3
if pgrep -x ippeveprinter >/dev/null; then
  log "Ready. '$PRINTER_DESC' is shared as an AirPrint printer on port ${AIRPRINT_PORT}."
else
  log "The AirPrint front end did not start; see the [airprint] lines above."
fi
log "Status page: http://<home-assistant-ip>:${AIRPRINT_PORT}/   CUPS engine: http://<home-assistant-ip>:631"

# Show exactly what iPhones are told about paper, and who else shares the printer.
(
  sleep 5
  mkdir -p /share/canon
  ipptool -tv "ipp://localhost:${AIRPRINT_PORT}/ipp/print" get-printer-attributes.test \
    > /share/canon/ipp-attributes.txt 2>&1
  grep -E '^\s+(media-(ready|default|supported|source-supported)|urf-supported|printer-uuid) ' \
      /share/canon/ipp-attributes.txt \
    | sed 's/^ */[canon-airprint] advertised: /' | cut -c1-500
  grep -c 'media-col-ready' /share/canon/ipp-attributes.txt >/dev/null \
    && log "advertised: media-col-ready is present (iPhones read loaded paper from it)"
  avahi-browse -rtp _ipp._tcp 2>/dev/null | grep '^=' | grep -v 'canon-airprint.local' \
    | awk -F';' '{print $4 " (" $8 ")"}' | sed 's/\\032/ /g; s/\\064/@/g; s/\\\././g' | sort -u \
    | sed 's/^/[canon-airprint] Also shared on the network (may confuse phones): /'
) &

# ---------- 6. Printer status sensors for Home Assistant ----------
if [ "$(opt status_sensors)" != "false" ]; then
  SENSOR_SLUG="$(echo "$PRINTER_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_')"
  log "Publishing printer status to Home Assistant as sensor.${SENSOR_SLUG}_*"
  /status.sh "$PRINTER_IP" "$PRINTER_DESC" "$SENSOR_SLUG" 60 &
fi

# ---------- 7. Stay running; restart pieces that stop ----------
while pgrep -x cupsd >/dev/null; do
  if ! pgrep -x ippeveprinter >/dev/null; then
    log "AirPrint front end stopped; restarting it."
    start_airprint
  fi
  sleep 30
done
log "CUPS stopped; exiting so Home Assistant restarts the add-on."
exit 1
