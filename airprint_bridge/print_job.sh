#!/usr/bin/env bash
# Called by ippeveprinter for every document a phone or Mac sends.
#   $1             = the document file
#   CONTENT_TYPE   = its MIME type (application/pdf, image/urf, image/jpeg, ...)
#   IPP_*          = job options (IPP_MEDIA, IPP_MEDIA_COL, IPP_COPIES, IPP_SIDES,
#                    IPP_PRINT_COLOR_MODE, ...)
# Hands the document to the local CUPS queue, which runs the printer's driver.
# Page ranges and orientation are already applied by the phone, so they are
# not passed again.
set -uo pipefail

STATE=/run/airprint-bridge
FILE="${1:-}"
QUEUE="$(cat "$STATE/queue" 2>/dev/null)"
DEFAULT_SIZE="$(cat "$STATE/default_size" 2>/dev/null)"; DEFAULT_SIZE="${DEFAULT_SIZE:-Letter}"
COLOR="$(cat "$STATE/color" 2>/dev/null)"
DUPLEX="$(cat "$STATE/duplex" 2>/dev/null)"

if [ -z "$FILE" ] || [ ! -f "$FILE" ] || [ -z "$QUEUE" ]; then
  echo "ERROR: Print job setup is incomplete." >&2
  exit 1
fi

# Paper size from the job (media keyword or media-col size in hundredths of mm).
MEDIA="${IPP_MEDIA:-} ${IPP_MEDIA_COL:-}"
case "$MEDIA" in
  *legal*|*35560*)   SIZE="Legal" ;;
  *letter*|*27940*)  SIZE="Letter" ;;
  *iso_a4*|*29700*)  SIZE="A4" ;;
  *iso_a5*|*21000*)  SIZE="A5" ;;
  *)                 SIZE="$DEFAULT_SIZE" ;;
esac
# Never ask the printer for a size it doesn't offer.
grep -q "^\*PageSize ${SIZE}[/:]" "/etc/cups/ppd/${QUEUE}.ppd" 2>/dev/null || SIZE="$DEFAULT_SIZE"

COPIES="${IPP_COPIES:-1}"
[[ "$COPIES" =~ ^[0-9]+$ ]] || COPIES=1

OPTS=(-o "PageSize=${SIZE}" -o "media=${SIZE}" -o fit-to-page)
if [ "$COLOR" = "true" ]; then
  OPTS+=(-o "print-color-mode=${IPP_PRINT_COLOR_MODE:-color}")
else
  OPTS+=(-o print-color-mode=monochrome)
fi
if [ "$DUPLEX" = "true" ] && [ -n "${IPP_SIDES:-}" ]; then
  OPTS+=(-o "sides=${IPP_SIDES}")
fi

echo "INFO: Printing on ${SIZE}" >&2
echo "[airprint-bridge] Job: ${CONTENT_TYPE:-?}, ${SIZE}, ${COPIES} copies, sides ${IPP_SIDES:-one-sided}" \
  >> /proc/1/fd/1 2>/dev/null

if ! lp -d "$QUEUE" -n "$COPIES" "${OPTS[@]}" "$FILE" >/dev/null 2>/tmp/lp_error; then
  echo "ERROR: $(cat /tmp/lp_error)" >&2
  echo "[airprint-bridge] Job failed: $(cat /tmp/lp_error)" >> /proc/1/fd/1 2>/dev/null
  exit 1
fi
exit 0
