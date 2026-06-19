#!/usr/bin/env bash
#
# udm-menu.sh — menú interactivo para la Dream Machine
# Usa udm-api.sh (mismo directorio) para la autenticación y las llamadas.
#
#   ./udm-menu.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$DIR/udm-api.sh"
LOCO_DIR="$DIR/UniFi_Loco_Patch"
LOCO="$LOCO_DIR/ufiber_patch.sh"
SITE="default"
B="/proxy/network/api/s/$SITE"   # base de la app Network

# ── colores ────────────────────────────────────────────────────────────
c_reset=$'\033[0m'; c_b=$'\033[1m'; c_dim=$'\033[2m'
c_grn=$'\033[0;32m'; c_cyn=$'\033[0;36m'; c_yel=$'\033[1;33m'; c_red=$'\033[0;31m'

command -v jq >/dev/null || { echo "${c_red}Falta 'jq' (brew install jq)${c_reset}"; exit 1; }
[ -x "$API" ] || { echo "${c_red}No encuentro udm-api.sh ejecutable en $DIR${c_reset}"; exit 1; }

api_get()  { "$API" get  "$@"; }
api_post() { "$API" post "$@"; }

pause() { echo; read -rsn1 -p "${c_dim}[Enter] para volver al menú…${c_reset}" _; echo; }

ensure_session() {
  if ! grep -q . "$DIR/.udm-session/cookies.txt" 2>/dev/null; then
    echo "${c_yel}No hay sesión activa, iniciando login…${c_reset}"; "$API" login || return 1
  fi
}

# ── acciones ───────────────────────────────────────────────────────────
do_login() { "$API" login; }

do_health() {
  echo "${c_b}Estado del gateway${c_reset}"
  api_get "$B/stat/device" | jq -r '
    .data[] | select(.type=="udm" or .model=="UDM") |
    "Modelo:   \(.model)",
    "Uptime:   \((.uptime//0)/3600|floor)h \((.uptime//0)%3600/60|floor)m",
    "Load:     \(.sys_stats.loadavg_1 // "?") / \(.sys_stats.loadavg_5 // "?") / \(.sys_stats.loadavg_15 // "?")",
    "CPU:      \(.["system-stats"].cpu // "?")%",
    "RAM:      \(.["system-stats"].mem // "?")%",
    "Temp:     \([.temperatures[]? | "\(.name) \(.value)°C"] | join("  ")  // "n/a")"'
}

do_wan() {
  echo "${c_b}WAN / Internet${c_reset}"
  api_get "$B/stat/health" | jq -r '
    .data[] | select(.subsystem=="wan") |
    "Estado:   \(.status)",
    "IP WAN:   \(.wan_ip // "—")",
    "Gateway:  \(.gw_name // .gateways[0]? // "—")",
    "Latencia: \(.latency // "—") ms   Down: \(((.["rx_bytes-r"]//0)/125000)|floor) kbps   Up: \(((.["tx_bytes-r"]//0)/125000)|floor) kbps"'
}

do_clients() {
  echo "${c_b}Clientes conectados${c_reset}"
  { printf "NOMBRE\tIP\tMAC\tTIPO\n"
    api_get "$B/stat/sta" | jq -r '
      .data | sort_by(.ip) | .[] |
      [ (.name // .hostname // "—"),
        (.ip // "—"),
        .mac,
        (if .is_wired then "cable" else "wifi" end) ] | @tsv'
  } | column -t -s$'\t'
}

do_devices() {
  echo "${c_b}Dispositivos UniFi${c_reset}"
  { printf "NOMBRE\tMODELO\tIP\tESTADO\n"
    api_get "$B/stat/device" | jq -r '
      .data[] |
      [ (.name // .model),
        .model,
        (.ip // "—"),
        (if .state==1 then "online" else "offline("+(.state|tostring)+")" end) ] | @tsv'
  } | column -t -s$'\t'
}

do_networks() {
  echo "${c_b}Redes configuradas${c_reset}"
  { printf "NOMBRE\tPROPOSITO\tSUBRED\tVLAN\n"
    api_get "$B/rest/networkconf" | jq -r '
      .data[] | [ .name, .purpose, (.ip_subnet // "—"), (.vlan // "—"|tostring) ] | @tsv'
  } | column -t -s$'\t'
}

do_ids() {
  echo "${c_b}IDS/IPS — categorías activas${c_reset}"
  api_get "$B/get/setting" | jq -r '.data[] | select(.key=="ips") |
    "Modo: \(.ips_mode)\nCategorías (\(.enabled_categories|length)):",
    (.enabled_categories[] | "  • \(.)")'
  echo; echo "${c_b}Últimas alertas IDS/IPS${c_reset}"
  api_get "$B/stat/ips/event" | jq -r '
    (.data // []) | if length==0 then "  (sin eventos recientes)" else
      sort_by(.timestamp) | reverse | .[0:8][] |
      "  \(.timestamp/1000|strftime("%d/%m %H:%M"))  \(.signature // .catname // "?")  src:\(.src_ip // "?")"
    end' 2>/dev/null || echo "  (endpoint sin datos)"
}

do_restart() {
  echo "${c_b}Reiniciar un dispositivo UniFi${c_reset}"
  api_get "$B/stat/device" | jq -r '.data[] | "  \(.mac)  \(.name // .model)  [\(.model)]"'
  echo; read -rp "MAC a reiniciar (vacío = cancelar): " mac
  [ -z "$mac" ] && { echo "Cancelado."; return; }
  [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || { echo "${c_red}MAC inválida${c_reset}"; return; }
  read -rp "${c_yel}¿Seguro que reiniciás $mac? (escribí SI): ${c_reset}" ok
  [ "$ok" = "SI" ] || { echo "Cancelado."; return; }
  body="$(jq -n --arg mac "$mac" '{cmd:"restart", mac:$mac}')"
  api_post "$B/cmd/devmgr" "$body" | jq -c '{rc:.meta.rc, msg:.meta.msg}'
}

# ── Fiber / UF-LOCO ──────────────────────────────────────────────────────
loco_run() { ( cd "$LOCO_DIR" && "./$(basename "$LOCO")" "$@" ); }

loco_warn_banner() {
  echo "${c_yel}${c_b}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║  ⚠️  UF-LOCO (192.168.1.1) — leé antes de operar               ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝${c_reset}"
  echo "  ${c_yel}Esto SOLO funciona con la PC conectada DIRECTO al LOCO."
  echo "  Si no, las operaciones van a fallar o colgarse.${c_reset}"
  echo
  echo "  ${c_b}Pasos antes de usar:${c_reset}"
  echo "   ${c_cyn}1.${c_reset} Conectá la PC por cable Ethernet directo al puerto del LOCO."
  echo "   ${c_cyn}2.${c_reset} Poné IP fija en esa interfaz, p.ej. ${c_b}192.168.1.10/24${c_reset}."
  echo "   ${c_cyn}3.${c_reset} Apuntá el gateway/DNS a ${c_b}192.168.1.1${c_reset} (el LOCO)."
  echo "   ${c_cyn}4.${c_reset} Verificá acceso: ${c_dim}ping 192.168.1.1${c_reset} y ${c_dim}http://192.168.1.1${c_reset} (ubnt/ubnt)."
  echo "   ${c_cyn}5.${c_reset} Hacé ${c_b}Backup (opción 1)${c_reset} antes de cualquier patch/restore."
  echo
}

do_loco() {
  [ -x "$LOCO" ] || { echo "${c_red}No encuentro $LOCO ejecutable${c_reset}"; return; }
  while true; do
    clear
    loco_warn_banner
    echo "${c_b}Fiber / UF-LOCO${c_reset}"
    echo "   ${c_cyn}1${c_reset})  💾  Backup de la config actual"
    echo "   ${c_cyn}2${c_reset})  ${c_red}⚠️  Patch (spoofing GPON — DESTRUCTIVO)${c_reset}"
    echo "   ${c_cyn}3${c_reset})  ${c_red}⚠️  Restore último backup (DESTRUCTIVO)${c_reset}"
    echo "   ${c_cyn}4${c_reset})  📜  Ver historial (log)"
    echo "   ${c_cyn}0${c_reset})  ↩️   Volver"
    echo
    read -rp "   Opción: " lo
    echo
    case "$lo" in
      1) loco_run backup ;;
      2) echo "${c_red}${c_b}⚠️  PATCH reescribe el firmware GPON con el serial/MAC clonados.${c_reset}"
        read -rp "${c_yel}Para confirmar escribí PATCH: ${c_reset}" ok
        [ "$ok" = "PATCH" ] && loco_run patch || echo "Cancelado." ;;
      3) echo "${c_red}${c_b}⚠️  RESTORE sobrescribe el firmware con el último backup.${c_reset}"
        read -rp "${c_yel}Para confirmar escribí RESTORE: ${c_reset}" ok
        [ "$ok" = "RESTORE" ] && loco_run restore || echo "Cancelado." ;;
      4) loco_run log ;;
      0) return ;;
      *) echo "${c_red}Opción inválida${c_reset}" ;;
    esac
    pause
  done
}

do_raw() {
  echo "${c_dim}Ej: $B/stat/sta   o   $B/get/setting${c_reset}"
  read -rp "GET path: " p
  [ -z "$p" ] && return
  api_get "$p" | jq '.' 2>/dev/null | ${PAGER:-less} -R
}

# ── menú ───────────────────────────────────────────────────────────────
menu() {
  clear
  echo "${c_grn}${c_b}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║           Dream Machine · Panel          ║"
  echo "  ╚══════════════════════════════════════════╝${c_reset}"
  echo "   ${c_cyn}1${c_reset})  📊  Estado del gateway (temp/CPU/RAM)"
  echo "   ${c_cyn}2${c_reset})  🌐  WAN / Internet"
  echo "   ${c_cyn}3${c_reset})  👥  Clientes conectados"
  echo "   ${c_cyn}4${c_reset})  📡  Dispositivos UniFi"
  echo "   ${c_cyn}5${c_reset})  🔀  Redes configuradas"
  echo "   ${c_cyn}6${c_reset})  🛡️   IDS/IPS (categorías + alertas)"
  echo "   ${c_cyn}7${c_reset})  🔄  Reiniciar un dispositivo"
  echo "   ${c_cyn}8${c_reset})  🔎  Query API libre (GET)"
  echo "   ${c_cyn}9${c_reset})  🔐  Re-login (refrescar sesión)"
  echo "   ${c_cyn}F${c_reset})  🔌  Fiber / UF-LOCO (backup·patch·restore)"
  echo "   ${c_cyn}0${c_reset})  ❌  Salir"
  echo
  read -rp "   Opción: " opt
  echo
  case "$opt" in
    1) do_health ;;   2) do_wan ;;     3) do_clients ;;
    4) do_devices ;;  5) do_networks ;; 6) do_ids ;;
    7) do_restart ;;  8) do_raw ;;     9) do_login ;;
    F|f) do_loco ;;
    0) echo "Chau 👋"; exit 0 ;;
    *) echo "${c_red}Opción inválida${c_reset}" ;;
  esac
  pause
}

ensure_session || { echo "${c_red}No pude iniciar sesión. Revisá .env${c_reset}"; exit 1; }
while true; do menu; done
