# QuoteApp Finalization Plan

## Goal

Ship a believable end-to-end take-home submission where a reviewer can run the backend and iOS app, complete a full quote speaking loop, and understand design/implementation tradeoffs.

## Final Scope

- Keep one coherent product path:
  - load quote list from backend
  - select quote
  - start session / establish LiveKit context
  - play backend-generated tutor quote audio
  - darken quote text by tutor playback progress
  - stop tutor playback when recording starts
  - record learner attempt locally
  - submit learner attempt to backend
  - poll latest attempt review result
  - render marked words for `info` or clean quote for `perfect`
  - show unavailable feedback when review cannot be completed
- Keep state ownership explicit:
  - playback state
  - local recording draft state
  - latest visible attempt review state
- Remove runtime scaffolding and keep developer-only preview support separate.

## Implemented Finalization Work

1. End-to-end state-flow cleanup
- Removed runtime mock review fallbacks from `MainViewModel`.
- Kept recording/send-ready toolbar exclusivity while preserving playback availability outside draft mode.
- Updated review control visibility to rely on latest visible review ownership (prevents stale/superseded loading review controls).
- Ensured paused playback renders as Repeat semantics.
- Reduced persistent debug-style LiveKit status display; now only actionable connection states are shown.

2. Tutor playback correctness and caching
- Preserved backend-generated tutor audio artifact as primary playback path.
- Preserved transcript/data-channel usage as metadata only.
- Added backend tutor audio artifact cache keyed by playback identity (quote + backend voice config + versioning).
- Exposed backend cache hit/miss header on tutor artifact endpoint for observability.
- Preserved device-side tutor audio cache reuse keyed by playback identity.

3. Backend API cleanup
- Removed mock-only request/query knobs from practice start/result APIs.
- Simplified latest-result mapping helpers to production-facing loading/timeout/superseded behavior.
- Updated backend docs/comments to remove placeholder/mock terminology.

4. Reviewer setup cleanup
- Reworked `scripts/setup_backend.sh`, `scripts/run_backend.sh`, `scripts/check_env.sh` for explicit simulator/device flows and clear diagnostics.
- Ensured run script prints direct simulator URL and real-device LAN URL guidance.
- Kept root `pyrightconfig.json` unchanged as backend analysis source of truth.

## Validation Checklist

- [x] Quote list is backend-loaded.
- [x] Practice session starts and keeps backend session identity.
- [x] Tutor playback is backend-generated audio first, metadata second.
- [x] Quote darkening is playback-progress driven.
- [x] Recording start forces playback stop and finished-at-end state.
- [x] Local recording draft can be stopped, sent, or dismissed.
- [x] Submission creates latest loading attempt and enters polling.
- [x] Latest attempt review state owns visible review controls.
- [x] Superseded loading attempts do not remain active visible loading state.
- [x] Timeout/failure paths map to unavailable state.
- [x] Device-side cache reuse works via playback identity.
- [x] Backend artifact cache reuse works via playback identity.

## Intentional Non-Goals (This Submission)

- Full pronunciation scoring or phoneme-level feedback claims.
- Authentication, user accounts, or persistent history storage.
- Large quote ingestion pipeline.
- Multi-screen product expansion outside the quote loop.
