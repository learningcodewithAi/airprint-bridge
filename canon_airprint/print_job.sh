#!/usr/bin/env bash
# Called by ippeveprinter for every document an iPhone/Mac sends.
#   $1                = the document file
#   CONTENT_TYPE      = its MIME type (application/pdf, image/urf, image/jpeg, ...)
#   IPP_MEDIA / IPP_MEDIA_COL, IPP_COPIES, IPP_PAGE_RANGES ... = job options
# Hands the document to the local CUPS queue, which runs Canon's driver.
set -uo pipefail

FILE="${1:-}"
QUEUE="$(cat /run/canon-airprint/queue 2>/dev/null)"
DEFAULT_SIZE="$(cat /run/canon-airprint/default_size 2>/dev/null)"
DEFAULT_SIZE="${DEFAULT_SIZE:-Letter}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ] || [ -z "$QUEUE" ]; then
  echo "ERROR: Print job setup is incomplete." >&2
  exit 1
fi

# Pick the paper size from the job (media keyword or media-col size).
MEDIA="${IPP_MEDIA:-} ${IPP_MEDIA_COL:-}"
case "$MEDIA" in
  *legal*|*35560*)              SIZE="Legal" ;;
  *letter*|*27940*)             SIZE="Letter" ;;
  *iso_a4*|*29700*)             SIZE="A4" ;;
  *iso_a5*|*21000*)             SIZE="A5" ;;
  *)                            SIZE="$DEFAULT_SIZE" ;;
esac
# Never ask the printer for a size it doesn't offer; fall back to the default.
grep -q "^\*PageSize ${SIZE}[/:]" "/etc/cups/ppd/${QUEUE}.ppd" 2>/dev/null || SIZE="$DEFAULT_SIZE"

COPIES="${IPP_COPIES:-1}"
[[ "$COPIES" =~ ^[0-9]+$ ]] || COPIES=1

OPTS=(-o "PageSize=${SIZE}" -o "media=${SIZE}" -o fit-to-page)
[ -n "${IPP_PAGE_RANGES:-}" ] && OPTS+=(-o "page-ranges=${IPP_PAGE_RANGES}")
[ -n "${IPP_ORIENTATION_REQUESTED:-}" ] && [ "${IPP_ORIENTATION_REQUESTED}" = "landscape" ] && OPTS+=(-o landscape)

echo "INFO: Sending to ${QUEUE} on ${SIZE} (${CONTENT_TYPE:-unknown}, ${COPIES} copies)" >&2
echo "[canon-airprint] job: ${CONTENT_TYPE:-?} -> ${QUEUE}, paper ${SIZE}, copies ${COPIES}, requested '${IPP_MEDIA:-}'" >> /proc/1/fd/1 2>/dev/null

if ! lp -d "$QUEUE" -n "$COPIES" "${OPTS[@]}" "$FILE" >/dev/null 2>/tmp/lp_error; then
  echo "ERROR: $(cat /tmp/lp_error)" >&2
  exit 1
fi
exit 0
