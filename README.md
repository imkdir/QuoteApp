<!-- Purpose: Project overview placeholder for QuoteApp MVP. -->

## LiveKit Notes (MVP Plumbing)

- iOS now requests LiveKit tokens from `POST /livekit/token` via `LiveKitTokenProvider`.
- `LiveKitSessionManager` exposes connection lifecycle states:
  - `disconnected`
  - `requestingToken`
  - `connecting`
  - `connected`
  - `failed`
- In this workspace build, the LiveKit SDK package is optional. The app will still compile and will surface a clear failure state if the SDK is not linked.
