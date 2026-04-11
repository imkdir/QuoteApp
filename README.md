# QuoteApp

QuoteApp is a native iOS speaking-practice app with a FastAPI backend and LiveKit integration.

The product loop is quote-centered:
1. pick a quote,
2. hear the tutor read that exact quote,
3. record your own attempt,
4. submit for review,
5. see the latest attempt result (`info`, `perfect`, or `unavailable`) directly on the quote surface.

This is intentionally not a generic chat app. It is a focused quote-reading practice loop.

## Architecture Overview

- `apps/ios/QuoteApp`:
  - SwiftUI single-screen, multi-phase experience (`start` -> `practice`)
  - `MainViewModel` owns state orchestration for playback, local recording draft, and latest-attempt review ownership
  - local recording with `AVAudioRecorder`
  - tutor playback driven from backend-generated audio artifacts, with device-side cache reuse
  - LiveKit connection plumbing for room/session lifecycle and tutor playback metadata
- `apps/backend`:
  - FastAPI API for quotes, practice session lifecycle, submission, and polling
  - backend LiveKit token minting (`/livekit/token`)
  - backend tutor runtime that generates tutor quote audio from backend TTS providers
  - backend result shaping into app-facing states (`loading`, `info`, `perfect`, `unavailable`)
  - backend-generated tutor audio artifact identity + cache for replay efficiency

### Playback Contract (Important)

- Backend-generated tutor audio is the primary playback path.
- Transcript/timing/data-channel output is secondary metadata only.
- Tutor playback speaks only the exact selected quote text.
- The app does not use local iOS TTS or macOS `say` as the primary tutor voice path.
- Device-side caching is an optimization on top of backend-generated audio, not a replacement for backend voice generation.

## Requirements

- macOS with Xcode 15+ (tested with iOS target 16.0)
- Python 3.11+
- LiveKit project credentials
- At least one backend TTS credential:
  - `OPENAI_API_KEY`, or
  - `GEMINI_API_KEY`

## Environment Setup

1. Prepare backend environment file:
   - `apps/backend/.env` (or run `./scripts/setup_backend.sh` to copy from `.env.example`)
2. Fill required values:
   - `LIVEKIT_URL`
   - `LIVEKIT_API_KEY`
   - `LIVEKIT_API_SECRET`
   - `OPENAI_API_KEY` or `GEMINI_API_KEY`
3. Optional tuning:
   - `TUTOR_TTS_PROVIDER`, `TUTOR_TTS_MODEL`, `TUTOR_TTS_VOICE`, `TUTOR_TTS_SPEED`

Run a readiness check anytime:

```bash
./scripts/check_env.sh
```

## Backend Setup and Run

Initial setup:

```bash
./scripts/setup_backend.sh
```

### Simulator / Local Backend Run

```bash
./scripts/run_backend.sh --simulator
```

- Binds to `127.0.0.1:8000` by default.
- iOS Simulator can use `http://127.0.0.1:8000` directly.

### Real Device / LAN Backend Run

```bash
./scripts/run_backend.sh --device
```

- Binds to `0.0.0.0`.
- Script prints `Device test URL: http://<LAN_IP>:8000`.
- Use that URL in Xcode scheme env var:
  - `QUOTEAPP_BACKEND_BASE_URL=http://<LAN_IP>:8000`

## iOS Run

1. From `apps/ios/QuoteApp`, ensure project is generated/updated:

```bash
xcodegen generate
```

2. Open `apps/ios/QuoteApp/QuoteApp.xcodeproj` in Xcode.
3. Select scheme `QuoteApp`.
4. Configure backend base URL when needed:
   - Simulator: default fallback is `http://127.0.0.1:8000`
   - Device: set `QUOTEAPP_BACKEND_BASE_URL` to printed LAN URL
5. Run on simulator or device.

## Final Runnable Path

1. Launch backend (`./scripts/run_backend.sh --simulator` or `--device`).
2. Launch iOS app.
3. Tap **Choose a quote**.
4. Select a quote (backend `/quotes`).
5. Tap **Play/Repeat** (backend tutor audio artifact playback; quote darkening is playback-driven).
6. Tap **Record** (active playback is stopped and moved to finished-at-end behavior).
7. Tap **Stop** then **Send** (local recording submitted via `/practice/session/{id}/attempt/submit`).
8. App polls `/practice/session/{id}/result` until `info`, `perfect`, or `unavailable`.
9. Review state reflects the latest visible attempt; marked words are shown inline for `info`.

## Key Tradeoffs

- One-screen multi-phase flow instead of multiple pages, to keep user loop tight.
- Review output is quote-surface-first, with minimal secondary sheet details.
- Review logic is intentionally modest and honest (coarse correctness states, no phoneme-level claims).
- Backend-generated audio path is prioritized over local synthesis.
- Playback cache strategy:
  - backend identity + backend artifact cache,
  - plus device-side cached artifact reuse.

## Known Limitations

- Quote catalog is in-memory and small.
- Practice/session data is in-memory; no persistence or auth.
- Review shaping is deterministic heuristic logic, not full pronunciation scoring.
- LiveKit SDK availability and network setup are required for full room behavior.
- Device/LAN testing depends on local network reachability and firewall settings.

## Project Notes

- `pyrightconfig.json` at repo root is the backend Python analysis source of truth.
- Xcode generation is kept deterministic via `apps/ios/QuoteApp/project.yml`.
