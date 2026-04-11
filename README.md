<!-- Purpose: Project overview placeholder for QuoteApp MVP. -->

## iOS Backend URL (Local Dev)

- Runtime URL resolution order in `AppEnvironment`:
  1. `QUOTEAPP_BACKEND_BASE_URL` from process environment / Xcode scheme env vars
  2. `QUOTEAPP_BACKEND_BASE_URL` from `Info.plist`
  3. fallback: `http://127.0.0.1:8000`
- For local-network HTTP development, `NSAppTransportSecurity.NSAllowsLocalNetworking` is enabled for the app target.

### Simulator

1. Start backend in simulator mode:
   - `./scripts/run_backend.sh`
2. Run iOS app in Simulator (no URL override needed; fallback works).

### Real Device

1. Start backend in device/LAN mode:
   - `BACKEND_MODE=device ./scripts/run_backend.sh`
2. Copy the printed `Device test URL` (example: `http://192.168.1.23:8000`).
3. In Xcode scheme for `QuoteApp`, set env var:
   - `QUOTEAPP_BACKEND_BASE_URL=http://192.168.1.23:8000`
4. Run on physical device (same Wi-Fi/LAN as your Mac).

## LiveKit Notes (MVP Plumbing)

- iOS now requests LiveKit tokens from `POST /livekit/token` via `LiveKitTokenProvider`.
- `LiveKitSessionManager` exposes connection lifecycle states:
  - `disconnected`
  - `requestingToken`
  - `connecting`
  - `connected`
  - `failed`
- In this workspace build, the LiveKit SDK package is optional. The app will still compile and will surface a clear failure state if the SDK is not linked.

## Backend Tutor Agent (Request 12 Draft Path)

- Practice session start now creates backend tutor context:
  - session id
  - LiveKit room name (`practice-<quote_id>-<session_id>` sanitized)
  - selected quote text
- The backend starts a tutor runtime worker per session that attempts to:
  - join the LiveKit room as `tutor-<session-prefix>`
  - synthesize and publish quote audio from backend TTS inference (`/audio/speech`) as the primary tutor voice path
  - publish quote script metadata (`quoteapp.tutor.quote_script`) only as companion data after audio starts
- Tutor playback speech content:
  - backend speaks only the selected quote text (no preamble/instructions)
  - punctuation and meaningful line breaks are preserved for natural phrasing
  - backend strips wrapper-only markdown artifacts before synthesis
  - backend picks TTS provider from available credentials (`OPENAI_API_KEY` or `GEMINI_API_KEY`) when `TUTOR_TTS_PROVIDER=auto`
  - voice/model are configurable via `TUTOR_TTS_PROVIDER`, `TUTOR_TTS_MODEL`, `TUTOR_TTS_VOICE`
  - duplicate Play requests while a tutor playback job is already running are ignored
  - playback startup latency stages are logged (request, audio ready, room connect/publish, first audio frame, started event)
  - startup path avoids blocking on script metadata publish and uses reduced preroll buffering
- Learner audio submission:
  - `POST /practice/session/{session_id}/attempt/submit` with raw bytes (`application/octet-stream`)
  - backend stores audio under temp directory `quoteapp-submissions/<session_id>/`
  - backend creates a new loading attempt, then resolves it asynchronously into:
    - `info`
    - `perfect`
    - `unavailable`
- If tutor runtime or review pipeline fails, attempt result maps to `unavailable`.

### Optional standalone tutor process entrypoint

You can run one tutor session worker directly:

```bash
PYTHONPATH=apps/backend python -m app.agents.speaking_tutor_agent \
  --session-id <session_id> \
  --room-name <room_name> \
  --quote-text "Your selected quote"
```
