#!/usr/bin/env bash
# Lists printers this machine can reach: network printers found with SNMP
# (most network printers answer it) and printers plugged in by USB.
# Output: one line per printer, "URI<TAB>make and model".
set -uo pipefail

BACKENDS=/usr/lib/cups/backend
parse() { awk -F'"' '{ split($1, a, " "); if (a[2] != "") print a[2] "\t" $2 }'; }

# SNMP discovery needs the standard "public" community; put the quiet
# setting back afterwards.
cp /etc/cups/snmp.conf /tmp/snmp.conf.saved 2>/dev/null
printf 'Address @LOCAL\nCommunity public\n' > /etc/cups/snmp.conf
{
  [ -x "$BACKENDS/snmp" ] && timeout 25 "$BACKENDS/snmp" 2>/dev/null | parse
  [ -x "$BACKENDS/usb" ]  && timeout 10 "$BACKENDS/usb"  2>/dev/null | parse
} | awk -F'\t' '!seen[$1]++'
[ -f /tmp/snmp.conf.saved ] && cp /tmp/snmp.conf.saved /etc/cups/snmp.conf
exit 0
