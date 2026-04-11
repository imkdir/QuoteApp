#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_backend.sh [--simulator|--device] [--host <host>] [--port <port>] [--no-reload]

Modes:
  --simulator (default)  Bind to localhost for iOS Simulator use
  --device               Bind to 0.0.0.0 and print LAN URL for real-device testing

Environment overrides:
  BACKEND_MODE=simulator|device
  BACKEND_HOST=<host>
  BACKEND_PORT=<port>
EOF
}

detect_lan_ip() {
  local default_iface=""
  local iface=""
  local ip=""

  default_iface="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [ -n "$default_iface" ]; then
    ip="$(ipconfig getifaddr "$default_iface" 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
  fi

  for iface in $(ifconfig -l 2>/dev/null); do
    case "$iface" in
      lo*) continue ;;
    esac
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
  done

  return 1
}

MODE="${BACKEND_MODE:-simulator}"
RELOAD=1
HOST_OVERRIDE=""
PORT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --device|device|lan)
      MODE="device"
      ;;
    --simulator|simulator|local)
      MODE="simulator"
      ;;
    --host)
      HOST_OVERRIDE="${2:-}"
      shift
      ;;
    --port)
      PORT_OVERRIDE="${2:-}"
      shift
      ;;
    --no-reload)
      RELOAD=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo ""
      usage
      exit 1
      ;;
  esac
  shift
done

case "$MODE" in
  simulator)
    DEFAULT_HOST="127.0.0.1"
    ;;
  device)
    DEFAULT_HOST="0.0.0.0"
    ;;
  *)
    echo "Invalid BACKEND_MODE: '$MODE' (expected simulator|device)"
    exit 1
    ;;
esac

cd "$BACKEND_DIR"

if [ ! -d ".venv" ]; then
  echo "Missing virtual environment. Run ./scripts/setup_backend.sh first."
  exit 1
fi

# shellcheck disable=SC1091
source .venv/bin/activate

if ! python -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo "Backend virtual environment is using Python < 3.11."
  echo "Continuing in compatibility mode; Python 3.11+ is recommended."
fi

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

HOST="${BACKEND_HOST:-$DEFAULT_HOST}"
PORT="${BACKEND_PORT:-8000}"

if [ -n "$HOST_OVERRIDE" ]; then
  HOST="$HOST_OVERRIDE"
fi
if [ -n "$PORT_OVERRIDE" ]; then
  PORT="$PORT_OVERRIDE"
fi

if [ "$MODE" = "device" ]; then
  case "$HOST" in
    127.0.0.1|localhost)
      echo "BACKEND_HOST=$HOST is not reachable from a real device; using 0.0.0.0."
      HOST="0.0.0.0"
      ;;
  esac
fi

echo "QuoteApp backend mode: $MODE"
echo "Backend directory: $BACKEND_DIR"
echo "Uvicorn bind URL: http://$HOST:$PORT"

if ! "$ROOT_DIR/scripts/check_env.sh" >/dev/null 2>&1; then
  echo "Environment check: incomplete (run ./scripts/check_env.sh for details)."
else
  echo "Environment check: ready for full end-to-end runs."
fi

if [ "$MODE" = "device" ]; then
  if LAN_IP="$(detect_lan_ip)"; then
    echo "Device test URL: http://$LAN_IP:$PORT"
    echo "Use in Xcode scheme: QUOTEAPP_BACKEND_BASE_URL=http://$LAN_IP:$PORT"
  else
    echo "Device test URL: unable to auto-detect LAN IP"
    echo "Use your Mac LAN IP manually: QUOTEAPP_BACKEND_BASE_URL=http://<LAN_IP>:$PORT"
  fi
else
  echo "Simulator URL: http://127.0.0.1:$PORT"
fi

uvicorn_cmd=(python -m uvicorn app.main:app --host "$HOST" --port "$PORT")
if [ "$RELOAD" -eq 1 ]; then
  uvicorn_cmd+=(--reload)
fi

exec "${uvicorn_cmd[@]}"
