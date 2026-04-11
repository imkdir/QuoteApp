#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"
ENV_FILE="$BACKEND_DIR/.env"

cd "$BACKEND_DIR"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  ENV_SOURCE="$ENV_FILE"
else
  ENV_SOURCE="(none)"
fi

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"

echo "QuoteApp backend environment check"
echo "Working directory: $BACKEND_DIR"
echo "Loaded env file: $ENV_SOURCE"
echo "BACKEND_HOST=$HOST"
echo "BACKEND_PORT=$PORT"
echo ""

missing_livekit=()
for key in LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET; do
  if [ -z "${!key:-}" ]; then
    missing_livekit+=("$key")
  fi
done

missing_tts=()
if [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  missing_tts+=("OPENAI_API_KEY or GEMINI_API_KEY")
fi

if [ ${#missing_livekit[@]} -eq 0 ]; then
  echo "[ok] LiveKit token config is complete."
else
  echo "[missing] LiveKit token config is incomplete."
  echo "          Missing: ${missing_livekit[*]}"
fi

if [ ${#missing_tts[@]} -eq 0 ]; then
  provider="${TUTOR_TTS_PROVIDER:-auto}"
  echo "[ok] Tutor TTS credentials are present (provider=$provider)."
else
  echo "[missing] Tutor TTS credentials are incomplete."
  echo "          Set at least one of: ${missing_tts[*]}"
fi

if [ ${#missing_livekit[@]} -eq 0 ] && [ ${#missing_tts[@]} -eq 0 ]; then
  echo ""
  echo "Environment is ready for full end-to-end practice runs."
  exit 0
fi

echo ""
echo "Environment is not ready for full end-to-end runs yet."
echo "Copy and update apps/backend/.env.example as apps/backend/.env, then rerun this script."
exit 1
