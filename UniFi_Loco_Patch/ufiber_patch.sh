#!/usr/bin/env bash
#
# ufiber_patch.sh — wrapper de UFiber.Configurator para el UF-LOCO (ONU GPON).
#
# Automatiza: backup del firmware, spoofing del vendor/serial/MAC del ONT original,
# restore del último backup y registro de acciones.
#
# UFiber.Configurator es software de terceros (ver README.md / checksums.txt).
# Recursos:
#   - Proyecto:        https://github.com/Unifi-Tools/UFiber.Configurator
#   - Manual UF-LOCO:  https://dl.ubnt.com/qsg/UF-LOCO/UF-LOCO_ES.html
#   - Firmware:        https://ui.com/download/ufiber
#
# Los datos del ONT (vendor/serial/MAC) son secretos: NO se hardcodean, vienen
# de las variables LOCO_* en el .env del proyecto (un nivel arriba). Ver .env.example.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIGURATOR="$SCRIPT_DIR/UFiber.Configurator"
BACKUP_DIR="$SCRIPT_DIR/dumps"
HISTORY_FILE="$SCRIPT_DIR/history.log"
LOCK_DIR="$SCRIPT_DIR/.ufiber_patch.lock"

# Config desde el .env del proyecto (no hay valores por defecto).
[ -f "$SCRIPT_DIR/../.env" ] && set -a && . "$SCRIPT_DIR/../.env" && set +a
VENDOR_ID="${LOCO_VENDOR_ID:-}"
SERIAL="${LOCO_SERIAL:-}"
MAC_WAN="${LOCO_MAC_WAN:-}"

DRY_RUN=false

die() { echo "[✗] $*" >&2; exit 1; }
log_action() { echo "[$(date '+%F %T')] $1" >> "$HISTORY_FILE"; }  # nunca loguear secretos

run() {
  if [[ "$DRY_RUN" == "true" ]]; then echo "[DRY-RUN] $*"; else "$@"; fi
}

acquire_lock() {
  mkdir "$LOCK_DIR" 2>/dev/null || die "ya hay una operación UFiber en curso (lock: $LOCK_DIR)"
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}

latest_backup() {
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'fw-*.bin' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -n1
}

validate_loco_vars() {
  [[ -n "$VENDOR_ID" && -n "$SERIAL" && -n "$MAC_WAN" ]] \
    || die "faltan LOCO_VENDOR_ID/LOCO_SERIAL/LOCO_MAC_WAN en ../.env (ver .env.example)"
  [[ "$VENDOR_ID" =~ ^[A-Za-z0-9]{4}$ ]] \
    || die "LOCO_VENDOR_ID inválido (4 alfanuméricos, ej. HWTC)"
  [[ "$SERIAL" =~ ^([0-9A-Fa-f]{2}-){7}[0-9A-Fa-f]{2}$ ]] \
    || die "LOCO_SERIAL inválido (8 octetos hex separados por '-')"
  [[ "$MAC_WAN" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] \
    || die "LOCO_MAC_WAN inválido (MAC con ':')"
}

show_help() {
  cat <<EOF
UFiber LOCO Patch — wrapper de UFiber.Configurator

  Uso: ./ufiber_patch.sh <comando> [--dry-run]

  Comandos:
    check      Valida entorno (binario, .env, variables, backups) sin tocar nada.
    backup     Hace un dump del firmware actual y lo deja en dumps/.
    patch      Aplica el spoofing GPON con LOCO_* del .env (exige backup previo).
    restore    Restaura el último backup disponible.
    log        Muestra el historial de acciones.
    help       Esta ayuda.

  Flags:
    --dry-run  Muestra qué haría (sin ejecutar sudo). Vale para patch/restore.

  Archivos:
    Binario:  $CONFIGURATOR
    Backups:  $BACKUP_DIR/
    Config:   ../.env  (LOCO_VENDOR_ID, LOCO_SERIAL, LOCO_MAC_WAN)

  ⚠️  patch/restore reescriben el firmware GPON. Conectate DIRECTO al LOCO y
      hacé 'backup' antes. No toques el spoofing salvo que se caiga la fibra.
EOF
}

do_check() {
  local ok=0
  pass() { echo "  [✓] $1"; }
  fail() { echo "  [✗] $1"; ok=1; }
  echo "Chequeo de entorno UFiber:"
  [[ -f "$CONFIGURATOR" ]] && pass "binario presente"            || fail "falta el binario UFiber.Configurator"
  [[ -x "$CONFIGURATOR" ]] && pass "binario ejecutable"          || fail "binario no ejecutable (chmod +x)"
  [[ -f "$SCRIPT_DIR/../.env" ]] && pass ".env presente"         || fail "falta ../.env (cp .env.example .env)"
  [[ -n "$VENDOR_ID" ]] && pass "LOCO_VENDOR_ID seteada"         || fail "LOCO_VENDOR_ID vacía"
  [[ -n "$SERIAL"    ]] && pass "LOCO_SERIAL seteada"            || fail "LOCO_SERIAL vacía"
  [[ -n "$MAC_WAN"   ]] && pass "LOCO_MAC_WAN seteada"           || fail "LOCO_MAC_WAN vacía"
  [[ -d "$BACKUP_DIR" ]] && pass "directorio dumps/ existe"      || fail "no existe dumps/"
  [[ -n "$(latest_backup)" ]] && pass "hay backup previo"       || fail "no hay backup previo (corré: backup)"
  if file "$CONFIGURATOR" 2>/dev/null | grep -q 'x86_64'; then
    [[ "$(uname -m)" == "arm64" ]] && echo "  [i] binario x86_64 en Apple Silicon: requiere Rosetta 2"
  fi
  return $ok
}

do_backup() {
  echo "[+] Backup: dump del firmware actual..."
  mkdir -p "$BACKUP_DIR"
  run sudo "$CONFIGURATOR" --dump
  [[ "$DRY_RUN" == "true" ]] && return 0
  local latest; latest="$(latest_backup)"
  [[ -n "$latest" && -f "$latest" ]] || die "no se generó ningún dump (fw-*.bin) en $BACKUP_DIR"
  chmod 600 "$latest" 2>/dev/null || true
  echo "[✓] Backup disponible: $latest"
  log_action "Backup creado"
}

apply_patch() {
  validate_loco_vars
  [[ -n "$(latest_backup)" ]] || die "no hay backup previo. Corré primero: $0 backup"
  acquire_lock
  echo "[+] Aplicando spoofing GPON (vendor=$VENDOR_ID, serial=oculto, mac=oculto)..."
  run sudo "$CONFIGURATOR" --vendor "$VENDOR_ID" --serial "$SERIAL" --mac "$MAC_WAN"
  [[ "$DRY_RUN" == "true" ]] && return 0
  echo "[✓] Configuración aplicada."
  log_action "Spoofing aplicado"
}

restore_backup() {
  local latest; latest="$(latest_backup)"
  [[ -n "$latest" && -f "$latest" ]] || die "no hay backups (fw-*.bin) en $BACKUP_DIR"
  acquire_lock
  echo "[!] Restaurando desde: $latest"
  run sudo "$CONFIGURATOR" --restore "$latest"
  [[ "$DRY_RUN" == "true" ]] && return 0
  echo "[✓] Restauración completa."
  log_action "Restaurado desde backup"
}

show_log() {
  [[ -f "$HISTORY_FILE" ]] || { echo "[i] Todavía no hay historial."; return; }
  echo "Historial de acciones:"; echo
  cat "$HISTORY_FILE"
}

# ── parseo de args ────────────────────────────────────────────────────────
cmd="${1:-help}"; shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) die "flag desconocido: $arg" ;;
  esac
done

case "$cmd" in
  check)            do_check ;;
  backup)          do_backup ;;
  patch)         apply_patch ;;
  restore)    restore_backup ;;
  log)             show_log ;;
  help|--help|-h)  show_help ;;
  *) die "comando inválido: '$cmd'. Usá 'help'." ;;
esac
