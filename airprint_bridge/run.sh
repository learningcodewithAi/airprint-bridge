#!/usr/bin/env bash
# AirPrint Bridge: makes a printer (network or USB) available as an AirPrint
# printer. CUPS + the printer's driver is the engine; ippeveprinter is the
# AirPrint front end that iPhones, iPads and Macs see.
set -uo pipefail

OPTIONS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }
log() { echo "[airprint-bridge] $*"; }
wait_forever() { log "$*"; log "Fix the Configuration tab, then restart the add-on."; sleep infinity; }

QUEUE=bridge
PRINTER_NAME="$(opt printer_name)";       PRINTER_NAME="${PRINTER_NAME:-My Printer}"
PRINTER_URI="$(opt printer_uri)"
PRINTER_LOC="$(opt printer_location)"
DRIVER_MATCH="$(opt driver_match)"
PAPER_SIZES="$(opt paper_sizes)";         PAPER_SIZES="${PAPER_SIZES:-Letter,Legal}"; PAPER_SIZES="${PAPER_SIZES// /}"
COLOR="$(opt color)";                     COLOR="${COLOR:-false}"
DUPLEX="$(opt duplex)";                   DUPLEX="${DUPLEX:-false}"
AIRPRINT_PORT="$(opt airprint_port)";     AIRPRINT_PORT="${AIRPRINT_PORT:-8631}"
DEBUG="$(opt debug_logging)";             DEBUG="${DEBUG:-false}"

log "Starting AirPrint Bridge for '$PRINTER_NAME' on $(dpkg --print-architecture)."

# ---------- 1. Drivers ----------
/install_driver.sh

# ---------- 2. Services: D-Bus, Avahi, CUPS ----------
mkdir -p /run/dbus /run/cups /var/spool/cups /var/cache/cups /var/log/cups /run/airprint-bridge
rm -f /run/dbus/pid /run/avahi-daemon/pid
# CUPS shouldn't poll the network for printers or tray contents.
printf 'Address @LOCAL\nCommunity disabled-by-airprint-bridge\n' > /etc/cups/snmp.conf
[ "$DEBUG" = "true" ] && sed -i 's/^LogLevel .*/LogLevel debug/' /etc/cups/cupsd.conf

# Announce only on the home network, not Home Assistant's internal networks.
LAN_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -n "$LAN_IF" ]; then
  sed -i '/^allow-interfaces=/d' /etc/avahi/avahi-daemon.conf
  sed -i "/^\[server\]/a allow-interfaces=${LAN_IF}" /etc/avahi/avahi-daemon.conf
  log "Network: $LAN_IF ($(ip -4 -o addr show "$LAN_IF" | awk '{print $4}'))"
fi

dbus-daemon --system --fork
sleep 1
avahi-daemon --daemonize --no-chroot || log "Avahi failed to start; phones won't find the printer."
: > /var/log/cups/error_log
/usr/sbin/cupsd
sleep 3
tail -n0 -F /var/log/cups/error_log 2>/dev/null | grep --line-buffered -v 'ColorManager\|deprecated' \
  | sed -u 's/^/[cups] /' &

# ---------- 3. Where is the printer? ----------
case "$PRINTER_URI" in
  "")
    wait_forever "Set printer_uri, e.g. socket://192.168.1.50:9100 for a network printer or 'usb' for USB." ;;
  usb|USB|auto)
    PRINTER_URI="$(lpinfo --timeout 15 -v 2>/dev/null | awk '$2 ~ /^usb:\/\// {print $2; exit}')"
    [ -n "$PRINTER_URI" ] || wait_forever "No USB printer found. Is it plugged in and turned on?"
    log "Found USB printer: $PRINTER_URI" ;;
  *://*) ;;
  *)
    # A bare address means a network printer on the standard raw port.
    PRINTER_URI="socket://${PRINTER_URI}:9100" ;;
esac

# ---------- 4. Driver model for this printer ----------
if [ "$DRIVER_MATCH" = "everywhere" ] || [ "$DRIVER_MATCH" = "driverless" ]; then
  MODEL_ARG=(-m everywhere)
  log "Using driverless printing (the printer must support IPP Everywhere)."
else
  [ -n "$DRIVER_MATCH" ] || wait_forever "Set driver_match to part of your printer's model name (e.g. LBP6030, HL-L2350)."
  PPD="$(lpinfo -m 2>/dev/null | grep -iF -- "$DRIVER_MATCH" | grep -v '^drv:///sample' | head -n1 | cut -d' ' -f1)"
  if [ -z "$PPD" ]; then
    log "No installed driver matches '$DRIVER_MATCH'. Installed models (first 80):"
    lpinfo -m 2>/dev/null | grep -v -E '^(drv:///sample|everywhere|lsb/usr/cupsfilters)' | head -n 80 \
      | sed 's/^/[airprint-bridge]   /'
    wait_forever "Pick a model from the list above for driver_match, or install a driver."
  fi
  MODEL_ARG=(-m "$PPD")
  log "Driver: $(lpinfo -m 2>/dev/null | grep -F -- "$PPD " | head -n1 | cut -d' ' -f2-)"
fi

lpadmin -x "$QUEUE" 2>/dev/null || true
if ! lpadmin -p "$QUEUE" -v "$PRINTER_URI" "${MODEL_ARG[@]}" -D "$PRINTER_NAME" -L "$PRINTER_LOC" \
       -o printer-is-shared=false -E 2>/tmp/lpadmin.log; then
  wait_forever "Could not create the printer: $(grep -v deprecated /tmp/lpadmin.log | head -n2)"
fi

# Offer only the paper sizes in the tray, so phones can't pick one that
# leaves the printer waiting for paper.
PPD_FILE="/etc/cups/ppd/${QUEUE}.ppd"
if [ -f "$PPD_FILE" ]; then
  awk -v KEEP="$PAPER_SIZES" -f /trim_ppd.awk "$PPD_FILE" > /tmp/trimmed.ppd
  if grep -q "^\*PageSize ${PAPER_SIZES%%,*}[/:]" /tmp/trimmed.ppd; then
    lpadmin -p "$QUEUE" -P /tmp/trimmed.ppd 2>/dev/null
  else
    log "Paper size '${PAPER_SIZES%%,*}' isn't in this driver; keeping the driver's sizes."
  fi
fi
lpadmin -d "$QUEUE"
cupsenable "$QUEUE"; cupsaccept "$QUEUE"
log "Printer: $PRINTER_URI, paper: $PAPER_SIZES, color: $COLOR, two-sided: $DUPLEX"

# ---------- 5. AirPrint front end ----------
echo "$QUEUE" > /run/airprint-bridge/queue
echo "${PAPER_SIZES%%,*}" > /run/airprint-bridge/default_size
echo "$COLOR" > /run/airprint-bridge/color
echo "$DUPLEX" > /run/airprint-bridge/duplex
/make_attrs.sh "$PAPER_SIZES" "$PRINTER_NAME" "$COLOR" "$DUPLEX" > /run/airprint-bridge/attrs.conf \
  || wait_forever "paper_sizes has no supported sizes (use Letter, Legal, A4, A5)."

IPPEVE="$(command -v ippeveprinter || ls /usr/sbin/ippeveprinter /usr/bin/ippeveprinter 2>/dev/null | head -n1)"
[ -n "$IPPEVE" ] || wait_forever "ippeveprinter is missing from this image."
mkdir -p /data/ssl /data/spool
[ "$DEBUG" = "true" ] && VERBOSE=(-vv) || VERBOSE=()

start_airprint() {
  # -K keeps the TLS keys in /data, so phones don't warn about a "different
  # printer" after restarts and updates.
  "$IPPEVE" "${VERBOSE[@]}" \
    -p "$AIRPRINT_PORT" \
    -K /data/ssl \
    -l "$PRINTER_LOC" \
    -a /run/airprint-bridge/attrs.conf \
    -c /print_job.sh \
    -d /data/spool \
    -r _print,_universal \
    "$PRINTER_NAME" 2>&1 \
    | grep --line-buffered -v -E 'Ignored Avahi state|IPv6 listener' \
    | sed -u 's/^/[airprint] /' &
}
start_airprint
sleep 3
if pgrep -x ippeveprinter >/dev/null; then
  log "Ready. '$PRINTER_NAME' is available to iPhones, iPads and Macs."
else
  log "The AirPrint front end did not start; see the [airprint] lines above."
fi

# Other computers sharing the same printer show up as duplicates on phones.
(
  sleep 8
  avahi-browse -rtp _ipp._tcp 2>/dev/null | grep '^=' | grep -v "airprint-bridge\.local" \
    | awk -F';' '{print $4 " (" $8 ")"}' | sed 's/\\032/ /g; s/\\064/@/g; s/\\\././g' | sort -u \
    | grep -v -F "$PRINTER_NAME (" \
    | sed 's/^/[airprint-bridge] Note: also shared on your network (can look like a duplicate on phones): /'
) &

# ---------- 6. Status sensors ----------
if [ "$(opt status_sensors)" != "false" ]; then
  HOST="$(echo "$PRINTER_URI" | sed -nE 's#^(socket|ipp|ipps|lpd|http|https)://([^/:@]+@)?([^/:]+).*#\3#p')"
  SLUG="$(echo "$PRINTER_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g')"
  if [ -n "$HOST" ]; then
    log "Status sensors: sensor.${SLUG}_status, _alert, _toner, _pages"
    /status.sh "$HOST" "$PRINTER_NAME" "$SLUG" 60 &
  else
    log "Status sensors need a network printer; skipped for $PRINTER_URI."
  fi
fi

# ---------- 7. Keep everything running ----------
while pgrep -x cupsd >/dev/null; do
  if ! pgrep -x ippeveprinter >/dev/null; then
    log "AirPrint front end stopped; restarting it."
    start_airprint
  fi
  if ! pgrep -x avahi-daemon >/dev/null; then
    log "Avahi stopped; restarting it."
    rm -f /run/avahi-daemon/pid
    avahi-daemon --daemonize --no-chroot
  fi
  sleep 30
done
log "CUPS stopped; exiting so Home Assistant restarts the add-on."
exit 1
