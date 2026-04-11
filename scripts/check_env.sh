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

tutor_tts_provider="$(printf '%s' "${TUTOR_TTS_PROVIDER:-auto}" | tr '[:upper:]' '[:lower:]')"
missing_tts=()
if [ "$tutor_tts_provider" = "openai" ]; then
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    missing_tts+=("OPENAI_API_KEY")
  fi
elif [ "$tutor_tts_provider" = "gemini" ]; then
  if [ -z "${GEMINI_API_KEY:-}" ]; then
    missing_tts+=("GEMINI_API_KEY")
  fi
elif [ "$tutor_tts_provider" = "auto" ]; then
  if [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
    missing_tts+=("OPENAI_API_KEY or GEMINI_API_KEY")
  fi
else
  missing_tts+=("TUTOR_TTS_PROVIDER must be one of: auto, openai, gemini")
fi

review_stt_provider="$(printf '%s' "${REVIEW_STT_PROVIDER:-auto}" | tr '[:upper:]' '[:lower:]')"
missing_review_stt=()
if [ "$review_stt_provider" = "openai" ]; then
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    missing_review_stt+=("OPENAI_API_KEY")
  fi
elif [ "$review_stt_provider" = "gemini" ]; then
  if [ -z "${GEMINI_API_KEY:-}" ]; then
    missing_review_stt+=("GEMINI_API_KEY")
  fi
elif [ "$review_stt_provider" = "auto" ]; then
  if [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
    missing_review_stt+=("OPENAI_API_KEY or GEMINI_API_KEY")
  fi
elif [ "$review_stt_provider" != "none" ] && [ "$review_stt_provider" != "disabled" ]; then
  missing_review_stt+=("REVIEW_STT_PROVIDER must be one of: auto, openai, gemini, none, disabled")
fi

if [ ${#missing_livekit[@]} -eq 0 ]; then
  echo "[ok] LiveKit token config is complete."
else
  echo "[missing] LiveKit token config is incomplete."
  echo "          Missing: ${missing_livekit[*]}"
fi

if [ ${#missing_tts[@]} -eq 0 ]; then
  echo "[ok] Tutor TTS credentials are present (provider=$tutor_tts_provider)."
else
  echo "[missing] Tutor TTS credentials are incomplete."
  echo "          Set: ${missing_tts[*]}"
fi

if [ ${#missing_review_stt[@]} -eq 0 ]; then
  echo "[ok] Learner review STT credentials are present (provider=$review_stt_provider)."
else
  echo "[missing] Learner review STT credentials are incomplete."
  echo "          Set: ${missing_review_stt[*]}"
fi

if [ ${#missing_livekit[@]} -eq 0 ] && [ ${#missing_tts[@]} -eq 0 ] && [ ${#missing_review_stt[@]} -eq 0 ]; then
  echo ""
  echo "Environment is ready for full end-to-end practice runs."
  exit 0
fi

echo ""
echo "Environment is not ready for full end-to-end runs yet."
echo "Copy and update apps/backend/.env.example as apps/backend/.env, then rerun this script."
exit 1
