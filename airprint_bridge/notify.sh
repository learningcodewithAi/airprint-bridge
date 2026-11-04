#!/usr/bin/env bash
# Shows a notification in Home Assistant (bell icon in the sidebar).
#   notify.sh "Title" "Message"
set -uo pipefail

TOKEN="${SUPERVISOR_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -r /run/s6/container_environment/SUPERVISOR_TOKEN ]; then
  TOKEN="$(cat /run/s6/container_environment/SUPERVISOR_TOKEN)"
fi
[ -n "$TOKEN" ] || exit 0

jq -n --arg t "$1" --arg m "$2" '{title: $t, message: $m, notification_id: "airprint_bridge"}' \
  | curl -s -o /dev/null -X POST \
      -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
      --data @- http://supervisor/core/api/services/persistent_notification/create
exit 0
