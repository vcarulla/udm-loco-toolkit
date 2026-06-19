#!/usr/bin/env bash
#
# download-ufiber-configurator.sh — trae el binario UFiber.Configurator desde una URL
# (release upstream) y verifica su integridad contra UniFi_Loco_Patch/checksums.txt.
#
# Sirve para NO versionar el binario de terceros: lo descargás cuando hace falta.
#
# Uso:
#   scripts/download-ufiber-configurator.sh <URL_DEL_BINARIO> [URL_TARBALL_DYLIBS]
#
# La URL salís a buscarla a los releases del proyecto:
#   https://github.com/Unifi-Tools/UFiber.Configurator/releases
#
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_DIR/UniFi_Loco_Patch"
CHECKSUMS="$DEST/checksums.txt"

die() { echo "[✗] $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "falta la URL del binario. Ver: https://github.com/Unifi-Tools/UFiber.Configurator/releases"
command -v curl >/dev/null || die "falta curl"
command -v shasum >/dev/null || die "falta shasum"
[[ -f "$CHECKSUMS" ]] || die "no encuentro $CHECKSUMS para verificar"

url="$1"
echo "[+] Descargando UFiber.Configurator desde: $url"
curl -fL --output "$DEST/UFiber.Configurator" "$url"
chmod +x "$DEST/UFiber.Configurator"

echo "[+] Verificando checksum..."
( cd "$DEST" && shasum -a 256 -c checksums.txt --ignore-missing ) \
  || die "el checksum NO coincide — descarga corrupta o versión distinta. No uses este binario."

echo "[✓] Binario descargado y verificado."
echo "    Nota: si bajaste una versión nueva, regenerá checksums.txt a propósito:"
echo "    (cd '$DEST' && shasum -a 256 UFiber.Configurator *.dylib > checksums.txt)"
