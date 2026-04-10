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
