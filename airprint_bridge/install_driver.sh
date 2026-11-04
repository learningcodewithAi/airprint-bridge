#!/usr/bin/env bash
# Installs printer drivers from the add-on options:
#   1. driver_packages: Debian packages (e.g. printer-driver-brlaser, hplip)
#   2. driver_url:      a vendor .deb, or a .tar.gz/.tgz/.zip containing .debs
#   3. /share/airprint_bridge/: a vendor .deb/.tar.gz/.zip dropped there
# Vendor drivers are downloaded by the user's own add-on and cached in /data;
# they are never part of this repository.
set -uo pipefail

log() { echo "[airprint-bridge] $*"; }
opt() { jq -r --arg k "$1" '.[$k] // empty' /data/options.json; }

ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
CACHE=/data/driver
DROP=/share/airprint_bridge
mkdir -p "$CACHE" "$DROP" /data/apt-archives

# ---------- 1. Debian driver packages ----------
mapfile -t PKGS < <(jq -r '.driver_packages[]? // empty' /data/options.json)
if [ "${#PKGS[@]}" -gt 0 ]; then
  log "Installing driver packages: ${PKGS[*]}"
  # Keep downloaded packages in /data so restarts don't download them again.
  rm -rf /var/cache/apt/archives && ln -s /data/apt-archives /var/cache/apt/archives
  mkdir -p /data/apt-archives/partial
  if apt-get update -qq >/dev/null 2>&1 \
     && apt-get install -y -qq --no-install-recommends "${PKGS[@]}" >/tmp/apt.log 2>&1; then
    log "Driver packages installed."
  else
    log "Could not install: ${PKGS[*]}. Check the names (see the documentation)."
    tail -n 5 /tmp/apt.log | sed 's/^/[airprint-bridge]   /'
  fi
fi

# ---------- 2. Vendor driver archive or package ----------
DRIVER_URL="$(opt driver_url)"
ARCHIVE=""

# A file dropped into /share/airprint_bridge wins over the URL.
DROPPED="$(ls -t "$DROP"/*.deb "$DROP"/*.tar.gz "$DROP"/*.tgz "$DROP"/*.zip 2>/dev/null | head -n1)"
if [ -n "$DROPPED" ]; then
  ARCHIVE="$DROPPED"
  log "Using driver file from /share/airprint_bridge: ${DROPPED##*/}"
elif [ -n "$DRIVER_URL" ]; then
  NAME="$(basename "${DRIVER_URL%%\?*}")"
  [ -n "$NAME" ] || NAME="driver.tar.gz"
  # Re-download only when the URL changes.
  if [ "$(cat "$CACHE/url" 2>/dev/null)" != "$DRIVER_URL" ] || [ ! -s "$CACHE/$NAME" ]; then
    rm -f "$CACHE"/*
    log "Downloading driver: $NAME"
    if curl -fsSL --retry 3 -o "$CACHE/$NAME" "$DRIVER_URL"; then
      echo "$DRIVER_URL" > "$CACHE/url"
    else
      log "Download failed. Check driver_url in the Configuration tab."
      rm -f "$CACHE/$NAME"
    fi
  fi
  [ -s "$CACHE/$NAME" ] && ARCHIVE="$CACHE/$NAME"
fi

[ -z "$ARCHIVE" ] && exit 0

WORK=/tmp/vendor-driver
rm -rf "$WORK" && mkdir -p "$WORK"
case "$ARCHIVE" in
  *.deb)          cp "$ARCHIVE" "$WORK"/ ;;
  *.zip)          unzip -q "$ARCHIVE" -d "$WORK" || { log "Could not unpack ${ARCHIVE##*/}."; exit 0; } ;;
  *)              tar -xzf "$ARCHIVE" -C "$WORK" 2>/dev/null || tar -xf "$ARCHIVE" -C "$WORK" \
                    || { log "Could not unpack ${ARCHIVE##*/}."; exit 0; } ;;
esac

# Pick the packages built for this machine's chip (plus arch-independent ones).
mapfile -t DEBS < <(find "$WORK" -type f \( -name "*_${ARCH}.deb" -o -name '*_all.deb' \) | sort)
if [ "${#DEBS[@]}" -eq 0 ]; then
  OTHER="$(find "$WORK" -type f -name '*.deb' -printf '%f ' | head -c 300)"
  if [ -n "$OTHER" ]; then
    log "This driver has no package for this machine ($ARCH). Found only: $OTHER"
    log "Look for a different download from the manufacturer, or a Debian driver package."
  else
    log "No .deb packages found in ${ARCHIVE##*/}."
  fi
  exit 0
fi

log "Installing vendor driver ($ARCH): ${DEBS[*]##*/}"
# Vendor packages often depend on desktop libraries only their GUI tools need,
# so install without pulling those in, then report anything printing needs.
dpkg -i --force-depends "${DEBS[@]}" >/tmp/dpkg.log 2>&1 || true

for d in "${DEBS[@]}"; do
  PKG="$(dpkg-deb -f "$d" Package)"
  dpkg -L "$PKG" 2>/dev/null | grep -E '^/usr/(lib|libexec)/cups/(filter|backend)/|\.so' | while read -r f; do
    [ -f "$f" ] || continue
    MISSING="$(ldd "$f" 2>/dev/null | awk '/not found/{print $1}' | tr '\n' ' ')"
    [ -n "$MISSING" ] && log "Driver file ${f##*/} is missing libraries: $MISSING"
  done
done

# Some vendor installers start their own CUPS; run.sh starts ours.
pkill -x cupsd 2>/dev/null || true
exit 0
