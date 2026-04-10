#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"

cd "$BACKEND_DIR"

if [ ! -d ".venv" ]; then
  echo "Missing virtual environment. Run ./scripts/setup_backend.sh first."
  exit 1
fi

source .venv/bin/activate

if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

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
if [ "${1:-}" = "--device" ] || [ "${1:-}" = "device" ]; then
  MODE="device"
elif [ "${1:-}" = "--simulator" ] || [ "${1:-}" = "simulator" ] || [ "${1:-}" = "local" ]; then
  MODE="simulator"
fi

case "$MODE" in
  simulator|local)
    DEFAULT_HOST="127.0.0.1"
    ;;
  device|lan)
    DEFAULT_HOST="0.0.0.0"
    ;;
  *)
    echo "Invalid BACKEND_MODE: '$MODE' (expected simulator|device)"
    exit 1
    ;;
esac

HOST="${BACKEND_HOST:-$DEFAULT_HOST}"
PORT="${BACKEND_PORT:-8000}"

# In device mode, localhost bind is never reachable from a phone.
if [ "$MODE" = "device" ] || [ "$MODE" = "lan" ]; then
  case "$HOST" in
    127.0.0.1|localhost)
      echo "BACKEND_HOST=$HOST is not reachable from a real device; using 0.0.0.0 for LAN mode."
      HOST="0.0.0.0"
      ;;
  esac
fi

echo "QuoteApp backend mode: $MODE"
echo "Uvicorn bind address: http://$HOST:$PORT"

if [ "$MODE" = "device" ] || [ "$MODE" = "lan" ]; then
  if LAN_IP="$(detect_lan_ip)"; then
    echo "Device test URL: http://$LAN_IP:$PORT"
    echo "Set QUOTEAPP_BACKEND_BASE_URL=http://$LAN_IP:$PORT in your iOS runtime config."
  else
    echo "Device test URL: (LAN IP auto-detect failed)"
    echo "Tip: set BACKEND_HOST manually or inspect your Mac LAN IP and use http://<LAN_IP>:$PORT"
  fi
else
  echo "Simulator/local URL: http://127.0.0.1:$PORT"
fi

exec python -m uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
