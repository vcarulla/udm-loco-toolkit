#!/usr/bin/env bash
#
# udm-api.sh — cliente mínimo para la API local de UniFi OS (Dream Machine)
#
# Uso:
#   1) Configurá las credenciales en un archivo .env junto a este script
#      (ver .env.example):
#        UDM_HOST=...        # IP/host del gateway
#        UDM_USER=...
#        UDM_PASS=...        # comillas simples si tiene símbolos
#
#   2) Login (guarda cookie + token CSRF en .udm-session/):
#        ./udm-api.sh login
#
#   3) Llamadas:
#        ./udm-api.sh get  /proxy/network/api/s/default/stat/sta      # clientes
#        ./udm-api.sh get  /proxy/network/api/s/default/stat/device   # dispositivos
#        ./udm-api.sh post /proxy/network/api/s/default/cmd/devmgr '{"cmd":"...","mac":"..."}'
#
#   Tip: encadená con jq para leer cómodo:
#        ./udm-api.sh get /proxy/network/api/s/default/stat/sta | jq '.data[].hostname'
#
# TLS: el cert de la UDM suele ser self-signed. Por defecto se acepta
# (UDM_INSECURE_TLS=true). Para verificar contra una CA propia, poné
# UDM_INSECURE_TLS=false y UDM_CACERT=/ruta/al/ca.pem en el .env.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

command -v curl >/dev/null || { echo "Falta 'curl'" >&2; exit 1; }
command -v jq   >/dev/null || { echo "Falta 'jq' (brew install jq)" >&2; exit 1; }

UDM_HOST="${UDM_HOST:?Definí UDM_HOST (.env) — la IP del gateway no se hardcodea}"
UDM_INSECURE_TLS="${UDM_INSECURE_TLS:-true}"
SESSION_DIR="$SCRIPT_DIR/.udm-session"
COOKIE_JAR="$SESSION_DIR/cookies.txt"
CSRF_FILE="$SESSION_DIR/csrf.txt"
mkdir -p "$SESSION_DIR"
chmod 700 "$SESSION_DIR"

die() { echo "Error: $*" >&2; exit 1; }

# Validación básica de host (evita armar URLs raras).
[[ "$UDM_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || die "UDM_HOST inválido: '$UDM_HOST'"
base="https://${UDM_HOST}"

# Argumentos TLS según configuración.
_tls_args() {
  if [[ "$UDM_INSECURE_TLS" == "true" ]]; then
    printf '%s\0' -k
  elif [[ -n "${UDM_CACERT:-}" ]]; then
    printf '%s\0' --cacert "$UDM_CACERT"
  fi
}

_require_session() { [[ -s "$COOKIE_JAR" ]] || die "no hay sesión. Corré: $0 login"; }
_require_csrf()    { [[ -s "$CSRF_FILE"  ]] || die "no hay CSRF token. Corré: $0 login"; }

cmd_login() {
  : "${UDM_USER:?Definí UDM_USER (.env)}"
  : "${UDM_PASS:?Definí UDM_PASS (.env)}"
  echo "Login en $base ..." >&2
  local tls=(); while IFS= read -r -d '' a; do tls+=("$a"); done < <(_tls_args)
  # JSON armado con jq para no romper con símbolos en usuario/password.
  local headers
  headers=$(jq -n --arg u "$UDM_USER" --arg p "$UDM_PASS" '{username:$u,password:$p}' \
    | curl -s "${tls[@]}" --max-time 10 -c "$COOKIE_JAR" -D - -o /dev/null \
        -X POST "$base/api/auth/login" \
        -H 'Content-Type: application/json' --data-binary @-)
  echo "$headers" | grep -ioE 'x-csrf-token: .*' | awk '{print $2}' | tr -d '\r' > "$CSRF_FILE"
  [ -s "$COOKIE_JAR" ] || die "no se recibió cookie de sesión (¿credenciales mal?)"
  chmod 600 "$COOKIE_JAR" "$CSRF_FILE" 2>/dev/null || true
  echo "OK — sesión guardada en $SESSION_DIR" >&2
}

# request <method> <path> [body-json]
request() {
  local method="$1" path="${2:?Falta el path, ej: /proxy/network/...}" body="${3:-}"
  _require_session
  [[ "$path" == /* ]] || die "el path debe empezar con '/': '$path'"
  local tls=(); while IFS= read -r -d '' a; do tls+=("$a"); done < <(_tls_args)
  local args=(-s "${tls[@]}" --max-time 15 -b "$COOKIE_JAR")
  if [[ "$method" != "GET" ]]; then
    _require_csrf
    args+=(-H "X-CSRF-Token: $(cat "$CSRF_FILE")" -H 'Content-Type: application/json' -X "$method")
    [[ -n "$body" ]] && args+=(--data-binary "$body")
  fi
  curl "${args[@]}" "$base$path"
}

case "${1:-}" in
  login)  cmd_login ;;
  get)    shift; request GET    "${1:-}" ;;
  post)   shift; request POST   "${1:-}" "${2:-{}}" ;;
  put)    shift; request PUT    "${1:-}" "${2:-{}}" ;;
  delete) shift; request DELETE "${1:-}" ;;
  *) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
