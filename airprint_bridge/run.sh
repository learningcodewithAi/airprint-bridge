#!/usr/bin/env bash
# AirPrint Bridge: makes a printer (network or USB) available as an AirPrint
# printer. CUPS + the printer's driver is the engine; ippeveprinter is the
# AirPrint front end that iPhones, iPads and Macs see.
set -uo pipefail

OPTIONS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }
log() { echo "[airprint-bridge] $*"; }
notify() { /notify.sh "$1" "$2"; }
wait_forever() { log "$*"; log "Fix the Configuration tab, then restart the add-on."; sleep infinity; }

QUEUE=bridge
PRINTER_NAME="$(opt printer_name)"
PRINTER_URI="$(opt printer_uri)"
PRINTER_LOC="$(opt printer_location)"
DRIVER_MATCH="$(opt driver_match)"
PAPER_SIZES="$(opt paper_sizes)";         PAPER_SIZES="${PAPER_SIZES:-Letter,Legal}"; PAPER_SIZES="${PAPER_SIZES// /}"
COLOR="$(opt color)";                     COLOR="${COLOR:-false}"
DUPLEX="$(opt duplex)";                   DUPLEX="${DUPLEX:-false}"
AIRPRINT_PORT="$(opt airprint_port)";     AIRPRINT_PORT="${AIRPRINT_PORT:-8631}"
DEBUG="$(opt debug_logging)";             DEBUG="${DEBUG:-false}"
MODE="$(opt mode)";                       MODE="${MODE:-auto}"

log "Starting AirPrint Bridge on $(dpkg --print-architecture)."

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
restart_cups() {
  pkill -x cupsd; for _ in $(seq 1 20); do pgrep -x cupsd >/dev/null || break; sleep 0.5; done
  /usr/sbin/cupsd; sleep 3
}
MODEL_NAME=""   # the printer's own make and model, when we can find it
AUTO_FOUND=0

case "$PRINTER_URI" in
  "")
    log "No printer address set; looking for printers on your network and USB…"
    mapfile -t FOUND < <(/discover.sh)
    case "${#FOUND[@]}" in
      0)
        notify "AirPrint Bridge: no printer found" \
          "Make sure the printer is on and connected, then restart the add-on. Or type its address in the add-on's Configuration tab."
        wait_forever "No printers found. Make sure it's on, or set the printer address." ;;
      1)
        PRINTER_URI="$(cut -f1 <<<"${FOUND[0]}")"
        MODEL_NAME="$(cut -f2 <<<"${FOUND[0]}")"
        AUTO_FOUND=1
        log "Found one printer: $MODEL_NAME at $PRINTER_URI" ;;
      *)
        log "Found ${#FOUND[@]} printers. Copy one address into the Printer address setting:"
        LIST=""
        for f in "${FOUND[@]}"; do
          log "  $(cut -f2 <<<"$f"): $(cut -f1 <<<"$f")"
          LIST="${LIST}- $(cut -f2 <<<"$f"): \`$(cut -f1 <<<"$f")\`"$'\n'
        done
        notify "AirPrint Bridge: pick your printer" \
          "Found more than one printer. Copy the address of the one you want into the add-on's **Printer address** setting, then restart it:"$'\n\n'"$LIST"
        wait_forever "Set the printer address to one of the printers above." ;;
    esac ;;
  usb|USB|auto)
    FOUND_USB="$(/discover.sh | awk -F'\t' '$1 ~ /^usb:\/\// {print; exit}')"
    [ -n "$FOUND_USB" ] || wait_forever "No USB printer found. Is it plugged in and turned on?"
    PRINTER_URI="$(cut -f1 <<<"$FOUND_USB")"; MODEL_NAME="$(cut -f2 <<<"$FOUND_USB")"
    log "Found USB printer: $MODEL_NAME" ;;
  *://*) ;;
  *)
    # A bare address means a network printer on the standard raw port.
    PRINTER_URI="socket://${PRINTER_URI}:9100" ;;
esac

# Network printer given by address: ask it for its model (standard SNMP).
HOST="$(echo "$PRINTER_URI" | sed -nE 's#^(socket|ipp|ipps|lpd|http|https)://([^/:@]+@)?([^/:?]+).*#\3#p')"
if [ -z "$MODEL_NAME" ] && [ -n "$HOST" ]; then
  MODEL_NAME="$(snmpget -v1 -c public -t 2 -r 1 -Oqv "$HOST" 1.3.6.1.2.1.25.3.2.1.3.1 2>/dev/null | tr -d '"')"
fi
[ -n "$MODEL_NAME" ] && log "Printer model: $MODEL_NAME"
if [ -z "$PRINTER_NAME" ]; then
  PRINTER_NAME="${MODEL_NAME:-My Printer}"
  PRINTER_NAME="${PRINTER_NAME%%/*}"   # "Canon LBP6030w/6018w" -> "Canon LBP6030w"
fi

# ---------- 3b. Does the printer already do AirPrint? ----------
# AirPrint printers announce Apple's print format (URF) over Bonjour. Only
# that counts: many printers answer IPP without supporting AirPrint. Those printers don't need the bridge, and a
# second copy would show up as a duplicate on phones.
has_airprint() {
  local host="$1" t
  [ -n "$host" ] || return 1
  sleep 2   # give Avahi a moment to hear announcements
  if timeout 8 avahi-browse -rtp _ipp._tcp 2>/dev/null | awk -F';' -v h="$host" \
       '$1=="=" && $8==h && $10 ~ /URF=/ {f=1} END {exit !f}'; then
    return 0
  fi
  return 1
}

if [ "$MODE" != "bridge" ] && has_airprint "$HOST"; then
  if [ "$MODE" = "auto" ] || [ "$MODE" = "sensors" ]; then
    log "Good news: ${MODEL_NAME:-this printer} already supports AirPrint, so phones can print to it directly."
    log "Running sensors only. To run the bridge anyway, set Mode to \"Bridge + sensors\"."
    if [ ! -f "/data/airprint-native-$HOST" ]; then
      notify "Good news! Your printer already supports AirPrint" \
        "**${MODEL_NAME:-Your printer}** can print from iPhones, iPads and Macs on its own, so AirPrint Bridge is running **sensors only**: status, paper and ink alerts, and page count."$'\n\n'"Want the bridge anyway? Set **Mode** to \"Bridge + sensors\" in the add-on's Configuration tab."
      touch "/data/airprint-native-$HOST"
    fi
    SENSORS_ONLY=1
  fi
elif [ "$MODE" = "sensors" ]; then
  log "Mode is \"Sensors only\": not sharing the printer, sensors only."
  SENSORS_ONLY=1
fi

if [ "${SENSORS_ONLY:-0}" = "1" ]; then
  [ -n "$HOST" ] || wait_forever "Sensors need a network printer, but this one is $PRINTER_URI."
  [ "$(opt status_sensors)" != "false" ] || wait_forever "Status sensors are turned off, so there's nothing to do."
  SLUG="$(echo "$PRINTER_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g')"
  log "Status sensors: sensor.${SLUG}_status, _alert, _toner, _pages"
  exec /status.sh "$HOST" "$PRINTER_NAME" "$SLUG" 60
fi

# ---------- 4. Driver for this printer ----------
# Finds an installed driver for a model name by trying its model numbers,
# e.g. "Canon LBP6030w/6018w" -> LBP6030w, LBP6030, 6018w, 6018.
find_ppd() {
  local tok cand ppd
  for tok in $(echo "$1" | tr '/,()_' '     '); do
    [[ "$tok" =~ [0-9] ]] || continue
    for cand in "$tok" "$(echo "$tok" | sed -E 's/[A-Za-z]+$//')"; do
      [ "${#cand}" -ge 3 ] || continue
      ppd="$(lpinfo -m 2>/dev/null | grep -v -E '^(drv:///sample|everywhere)' | grep -iF -- "$cand" | head -n1 | cut -d' ' -f1)"
      [ -n "$ppd" ] && { echo "$ppd"; return 0; }
    done
  done
  return 1
}
# Free Debian driver for a brand, or nothing.
brand_package() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    *brother*)                 echo printer-driver-brlaser ;;
    *hewlett*|*" hp "*|hp\ *)  echo printer-driver-hpcups ;;
    *epson*)                   echo printer-driver-escpr ;;
    *samsung*|*xerox*)         echo printer-driver-splix ;;
  esac
}

PPD=""
if [ "$DRIVER_MATCH" = "everywhere" ] || [ "$DRIVER_MATCH" = "driverless" ]; then
  MODEL_ARG=(-m everywhere)
  log "Using driverless printing (the printer must support IPP Everywhere)."
else
  if [ -n "$DRIVER_MATCH" ]; then
    PPD="$(lpinfo -m 2>/dev/null | grep -iF -- "$DRIVER_MATCH" | grep -v '^drv:///sample' | head -n1 | cut -d' ' -f1)"
  elif [ -n "$MODEL_NAME" ]; then
    PPD="$(find_ppd "$MODEL_NAME")"
    # No driver yet: for brands with a free driver, install it and try again.
    if [ -z "$PPD" ]; then
      PKG="$(brand_package "$MODEL_NAME")"
      if [ -n "$PKG" ] && ! grep -qx "$PKG" /data/auto-packages 2>/dev/null; then
        log "Installing the free driver for this printer: $PKG"
        if /install_driver.sh --packages "$PKG"; then
          echo "$PKG" >> /data/auto-packages
          restart_cups
          PPD="$(find_ppd "$MODEL_NAME")"
        fi
      fi
    fi
  fi

  if [ -z "$PPD" ]; then
    WHAT="${DRIVER_MATCH:-${MODEL_NAME:-your printer}}"
    case "$(echo "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')" in
      *canon*)
        HELP="Canon printers need Canon's Linux driver. On Canon's support site, find your model's \"UFRII LT\" or \"UFR II\" Linux driver (or \"IJ Printer Driver\" for PIXMA), start the download, copy its link, and paste it into **Driver download link**." ;;
      *)
        HELP="Install a driver: set **Driver packages** (see the documentation's driver table) or **Driver download link**, or type the model as the driver lists it in **Printer model** (the add-on's log lists the installed models)." ;;
    esac
    log "No installed driver matches '$WHAT'. Installed models (first 80):"
    lpinfo -m 2>/dev/null | grep -v -E '^(drv:///sample|everywhere|lsb/usr/cupsfilters)' | head -n 80 \
      | sed 's/^/[airprint-bridge]   /'
    notify "AirPrint Bridge: driver needed" "Found ${MODEL_NAME:-your printer}, but no driver for it yet. $HELP Then restart the add-on."
    wait_forever "No driver for '$WHAT' yet. $HELP"
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

# If the printer (or anything else) already announces this name, phones would
# see two look-alikes. Use a clearly different name for the bridge.
AIR_NAME="$PRINTER_NAME"
if timeout 8 avahi-browse -atp 2>/dev/null | awk -F';' '{print $4}' \
     | sed 's/\\032/ /g; s/\\\././g' | grep -qxF "$PRINTER_NAME"; then
  AIR_NAME="$PRINTER_NAME AirPrint"
  log "Another device already uses the name '$PRINTER_NAME', so phones will see this one as '$AIR_NAME'."
fi

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
    "$AIR_NAME" 2>&1 \
    | grep --line-buffered -v -E 'Ignored Avahi state|IPv6 listener' \
    | sed -u 's/^/[airprint] /' &
}
start_airprint
sleep 3
if pgrep -x ippeveprinter >/dev/null; then
  log "Ready. '$AIR_NAME' is available to iPhones, iPads and Macs."
  if [ "$AUTO_FOUND" = "1" ] && [ ! -f /data/setup-notified ]; then
    MSG="Found **${MODEL_NAME}** and set it up as **${PRINTER_NAME}**. Print from your iPhone, iPad or Mac: Share → Print."
    if [ -n "$HOST" ]; then
      MSG="$MSG"$'\n\n'"The printer is at **${HOST}**. Reserve this address in your router (\"DHCP reservation\") so it doesn't change, or printing will stop working."
    fi
    notify "AirPrint Bridge is ready" "$MSG"
    touch /data/setup-notified
  fi
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
