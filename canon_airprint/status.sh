#!/usr/bin/env bash
# Reads the printer's status over SNMP (standard Printer MIB) every minute
# and publishes it to Home Assistant as sensors through the Supervisor API.
set -uo pipefail

IP="$1"
NAME="${2:-Canon LBP6030w}"
SLUG="${3:-canon_printer}"
INTERVAL="${4:-60}"
API="http://supervisor/core/api/states"

# The Supervisor token is in the environment, or in s6's saved copy of it.
TOKEN="${SUPERVISOR_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -r /run/s6/container_environment/SUPERVISOR_TOKEN ]; then
  TOKEN="$(cat /run/s6/container_environment/SUPERVISOR_TOKEN)"
fi
if [ -z "$TOKEN" ]; then
  echo "[canon-airprint] No Home Assistant API token available; status sensors disabled."
  exit 0
fi

snmp() { snmpget -v1 -c public -t 2 -r 1 -Oqv "$IP" "$1" 2>/dev/null | tr -d '"'; }
snmphex() { snmpget -v1 -c public -t 2 -r 1 -Oqvx "$IP" "$1" 2>/dev/null | tr -d '"' | tr -s ' '; }

post() { # entity_id, state, attributes-json
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"state\": \"$2\", \"attributes\": $3}" \
    "${API}/$1")"
  case "$code" in 200|201) ;; *) echo "[canon-airprint] Could not update $1 (HTTP $code)" ;; esac
}

LAST=""
while true; do
  STATUS_CODE="$(snmp 1.3.6.1.2.1.25.3.5.1.1.1)"           # hrPrinterStatus
  if [ -z "$STATUS_CODE" ]; then
    STATUS="offline"; ALERT="Offline"; TONER=""; PAGES=""
  else
    case "$STATUS_CODE" in
      3) STATUS="idle" ;; 4) STATUS="printing" ;; 5) STATUS="warming up" ;;
      *) STATUS="unknown" ;;
    esac

    # hrPrinterDetectedErrorState: 2 bytes of flags.
    HEX="$(snmphex 1.3.6.1.2.1.25.3.5.1.2.1)"
    B0=$(( 16#$(echo "$HEX" | awk '{print ($1==""?"0":$1)}') ))
    B1=$(( 16#$(echo "$HEX" | awk '{print ($2==""?"0":$2)}') ))
    ALERTS=()
    (( B0 & 0x40 )) && ALERTS+=("No paper")
    (( B0 & 0x80 )) && ALERTS+=("Low paper")
    (( B0 & 0x04 )) && ALERTS+=("Paper jam")
    (( B0 & 0x08 )) && ALERTS+=("Door open")
    (( B0 & 0x10 )) && ALERTS+=("No toner")
    (( B0 & 0x20 )) && ALERTS+=("Toner low")
    (( B0 & 0x01 )) && ALERTS+=("Service requested")
    (( B1 & 0x04 )) && ALERTS+=("Paper tray empty")
    (( B1 & 0x20 )) && ALERTS+=("Toner cartridge missing")
    if [ "${#ALERTS[@]}" -eq 0 ]; then
      ALERT="OK"
    else
      ALERT="$(printf '%s, ' "${ALERTS[@]}")"; ALERT="${ALERT%, }"
    fi

    # Toner level as a percentage (negative values mean "unknown").
    LEVEL="$(snmp 1.3.6.1.2.1.43.11.1.1.9.1.1)"
    MAX="$(snmp 1.3.6.1.2.1.43.11.1.1.8.1.1)"
    TONER=""
    if [[ "$LEVEL" =~ ^[0-9]+$ && "$MAX" =~ ^[0-9]+$ && "$MAX" -gt 0 ]]; then
      TONER=$(( LEVEL * 100 / MAX ))
    fi
    PAGES="$(snmp 1.3.6.1.2.1.43.10.2.1.4.1.1)"
    [[ "$PAGES" =~ ^[0-9]+$ ]] || PAGES=""
  fi

  post "sensor.${SLUG}_status" "$STATUS" \
    "{\"friendly_name\": \"${NAME} Status\", \"icon\": \"mdi:printer\"}"
  post "sensor.${SLUG}_alert" "$ALERT" \
    "{\"friendly_name\": \"${NAME} Alert\", \"icon\": \"mdi:printer-alert\"}"
  post "sensor.${SLUG}_toner" "${TONER:-unknown}" \
    "{\"friendly_name\": \"${NAME} Toner\", \"unit_of_measurement\": \"%\", \"state_class\": \"measurement\", \"icon\": \"mdi:printer-toner\"}"
  post "sensor.${SLUG}_pages" "${PAGES:-unknown}" \
    "{\"friendly_name\": \"${NAME} Pages Printed\", \"state_class\": \"total_increasing\", \"icon\": \"mdi:counter\"}"

  NOW="${STATUS}|${ALERT}|${TONER}"
  if [ "$NOW" != "$LAST" ]; then
    echo "[canon-airprint] printer status: ${STATUS}, alert: ${ALERT}, toner: ${TONER:-?}%, pages: ${PAGES:-?}"
    LAST="$NOW"
  fi
  sleep "$INTERVAL"
done
