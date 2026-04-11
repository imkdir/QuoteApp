# Development Workflow

## AI Tools Used

- Codex (GPT-5 coding agent) inside the shared workspace
- Terminal-driven repo inspection (`rg`, `sed`, `git`, script execution)

No external code generation pipelines were used beyond direct Codex edits in this repository.

## How AI Was Used

1. Codebase audit and gap mapping
- Read the implementation brief and inspected iOS/backend/runtime/scripts side by side.
- Mapped existing implementation to required end-to-end behavior and identified late-stage gaps (state ownership edge cases, remaining scaffolding, reviewer setup clarity).

2. Direct generation tasks
- Rewrote setup/documentation files (`README.md`, `plan.md`, `workflow.md`, backend scripts).
- Implemented concrete code cleanup patches in Swift and Python.
- Added backend tutor audio artifact cache logic keyed by playback identity.

3. Iterative refinement tasks
- Iterated on state derivation in `MainViewModel` and `ActionToolbarState` to avoid stale/superseded review visibility.
- Iterated on playback semantics (paused => Repeat) and UI status messaging to reduce debug-prototype feel.
- Iterated on script UX wording and argument handling for simulator/device mode consistency.

## What Was Iterative vs Direct

Iterative:
- iOS toolbar/review ownership cleanup
- playback/status behavior cleanup
- backend cache integration into tutor runtime and route response metadata
- setup script UX and argument model

Direct (single-pass or near single-pass):
- placeholder doc replacement (`README.md`, `plan.md`, `workflow.md`)
- removing mock-only API surface (`mock_result` request/query paths)
- terminology cleanup in comments/docstrings

## Debugging and Setup Issues That Influenced Implementation

- The app had runtime-ready backend services but still retained fallback/mock branches for non-runtime contexts; these made the code read as transitional. Those branches were removed or converted to explicit unavailable states in runtime paths.
- Review controls were previously driven partly by raw attempt history count. This could surface misleading review affordances when only superseded loading attempts existed. The logic was corrected to use latest visible review ownership.
- Backend tutor artifact generation existed, but repeated artifact requests were not explicitly cached server-side. A backend cache layer was added to align with replay optimization expectations.
- Backend startup ergonomics were uneven across simulator/device usage. Scripts were rewritten to produce clearer, mode-specific guidance and explicit environment diagnostics.

## Architectural Corrections Made During Development

1. State ownership separation was preserved and tightened
- Playback state remains independent from local recording draft state and latest-attempt review state.
- Recording/send-ready mode remains toolbar-exclusive while a local draft exists.
- Latest visible attempt owns review UI state; stale/superseded loading attempts no longer dominate UI.

2. Tutor playback path stayed backend-audio-first
- Backend-generated tutor audio artifact remains the default playback path.
- LiveKit transcript/data-channel remains metadata-only.
- No regression to local iOS TTS or macOS shell TTS as primary tutor playback.

3. Cache model was made explicit and explainable
- Backend identity-based artifact cache reduces repeated synthesis.
- Device-side cache reuse remains keyed by backend playback identity.
- Cache invalidation is tied to quote content + backend voice/model config + versioned identity.

## Final Validation Approach

- Static code inspection of iOS state ownership and backend endpoint paths.
- Script sanity checks for setup/run/env workflows.
- Backend Python compile check to catch syntax/integration regressions.
- Final documentation pass to ensure run instructions match actual implementation.
