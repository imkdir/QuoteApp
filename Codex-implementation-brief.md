# QuoteApp — Codex Implementation Brief

## Goal

Build a native iOS speaking-practice app backed by LiveKit.

The product is a quote-based speaking tutor:

* the learner picks a quote,
* hears the tutor read it aloud,
* repeats it,
* gets a review result,
* sees missed or unclear words marked directly on the quote,
* sees a simple explanation if review is unavailable.

This is not a general literary chat app.
This is not an acting or mood coach.
This is a focused speaking-practice product with a closed loop.

The visual direction should follow the approved mock:

* a simple start state with **Let’s speak**
* a bottom-sheet quote picker
* a minimal practice screen with the quote as the main reading surface
* a calm bottom action area centered on **Record**, **Repeat**, and **Review**
* a flat, system-forward visual style using native controls and SF Symbols where they fit naturally
* avoid decorative borders, heavy shadows, and custom card chrome

---

## Core product loop

1. Pick a quote
2. Hear the tutor read it
3. Repeat it by voice
4. Wait for analysis
5. Get one of four internal analysis states:

   * `info` — some words are marked on the quote
   * `perfect` — no words are marked
   * `loading` — result not ready yet
   * `unavailable` — review could not be completed
6. Hear again, continue, or choose another quote

---

## Product behavior

### Tutor playback rule

When the tutor reads the selected quote aloud, it must speak only the exact quote text.
Do not add any preamble, instruction, commentary, encouragement, or extra words before or after the quote.
Feedback belongs to the review phase, not the playback phase.

### Quote rendering model

The quote is always rendered as a full text surface.

Each token/word has visual states:

* `dimmed` — not yet spoken by the tutor
* `spoken` — already spoken by the tutor, rendered darker
* `marked` — analysis says this word needs attention

Rules:

* During tutor playback, the quote starts dimmed and spoken words progressively darken.
* During review, the full quote is fully readable.
* If result is `info`, marked words are underlined.
* If result is `perfect`, no marks are shown.
* On a later attempt, words that were previously marked and are now corrected may get a brief positive animation, then return to normal text.
* When tutor playback reaches the end of the quote, playback state should become **finished-at-end**.
* When playback is finished at end, the playback control should reset to `Play/Repeat`, and pressing it should restart playback from the beginning.
* When the learner starts recording, any active tutor playback should stop immediately and playback UI should transition to finished-at-end behavior.

Implementation note:

* Use a single quote text component.
* Do not split quote rendering into multiple overlapping quote layers.
* Do not add metadata or extra quote-surface controls in the MVP.

### Attempt history model

A practice session may contain a history of learner attempts.

For MVP, each attempt can be modeled as a pair of:

* a learner recording
* an optional tutor review result

A tutor review result may be simplified to:

* optional marked words
* optional short feedback text
* one of the internal analysis states:

  * `loading`
  * `info`
  * `perfect`
  * `unavailable`

The UI should display the latest attempt’s review state.

When the learner sends a new recording:

* create a new current attempt
* show `Reviewing` while that attempt is being processed
* once review finishes, replace the visible review with the latest attempt’s result

### Superseded and timed-out loading

A `loading` review state is only meaningful while the client is actively waiting for that attempt’s result.

If the learner starts a new local recording before a pending review completes:

* cancel client-side polling for the previous pending attempt
* treat that pending attempt as superseded for UI purposes
* do not continue showing its loading state as the active review

If a local draft is later deleted:

* restore the latest meaningful review state, if one exists
* otherwise do not show a review control

For UI purposes, a meaningful review is:

* `info`
* `perfect`
* `unavailable`
* `loading` only if it is the currently active review request

A review request that remains `loading` beyond a reasonable timeout should transition to `unavailable`.

### Feedback details

* The main review surface is the quote itself.
* Secondary feedback appears in the review control state or a bottom sheet if needed.
* The tutor should be concise and corrective, not chatty.

---

## Screen model

Use one main screen with multiple phases, plus a quotes sheet.

### Top-level phases

* `start`
* `practice`

### Overlay / sheet

* `quotePickerSheet`

### Practice session phases

* `listening`
* `readyToRecord`
* `recording`
* `recorded`
* `analyzing`
* `reviewed`

### Analysis states

* `none`
* `loading`
* `info`
* `perfect`
* `unavailable`

---

## UI structure

### 1. Start state

A minimal welcome-like state based on the approved mock:

* title: **Let’s speak**
* optional small brand mark or decorative waveform
* entry point to open the quotes sheet

### 2. Quote picker sheet

A rounded bottom sheet with:

* close button
* title: **Quotes**
* simple list of quote previews

This should feel lightweight and native, not like a full separate page.

### 3. Practice screen

The quote is the main visual object.
It should feel like a piece of paper the learner reads from while listening or speaking.

Contains:

* quote text only
* flat, native presentation with minimal custom container styling

### 4. Action stack

This is the main control surface at the bottom.

It has three logical control groups:

* playback action
* recording action
* analysis action

---

## Action stack rules

The bottom action area should stay simple and close to the mock.
Use SF Symbols when they naturally fit the action and status language.
Keep the styling flat and system-like.

### Action visibility rule

The action stack is state-driven, but it should feel natural rather than rigid.

Important distinction:

* the **current tutor playback state** controls playback controls
* the **current local recording draft** controls recording/send-ready controls
* the **latest attempt review state** controls review controls

These are separate concerns and should not be flattened into one mutually exclusive enum.

Natural toolbar behavior:

* when the learner is **recording** or has a **stopped-but-unsent local draft**, show only recording-related controls in the toolbar
* when the learner is **not recording** and has no unsent local draft, playback controls should be available based on tutor playback state
* when nothing blocks review controls, show review controls whenever:

  * analysis for the latest attempt is loading, or
  * there is at least one attempt in session history

In other words:

* **recording/send-ready** has toolbar exclusivity
* **playback** should be available whenever the learner is not in recording/send-ready mode
* **review** should be available whenever there is an in-progress or completed latest attempt and recording/send-ready mode is not active

The screen may still display the latest completed review in the quote area or review sheet, because review belongs to session history, not only to the current local draft.

A stale or superseded `loading` attempt should not count as the latest visible review for toolbar purposes.

### Playback action

* show `Pause` while tutor audio is actively playing
* show `Repeat` when tutor audio is paused or finished
* use `pause.circle.fill` and `play.circle.fill`
* playback controls should be available whenever the learner is not in recording/send-ready mode
* if playback is finished at end, pressing `Repeat` restarts playback from the beginning
* when recording starts, any active playback should stop and the playback UI should move into finished-at-end behavior

### Recording action

Default state:

* show a `Record` action in the right toolbar using `waveform.circle.fill`

When record is pressed:

* the record button disappears from the right toolbar
* a standalone `RecordingInputToolbar` component appears on the left side
* `RecordingInputToolbar` owns its own visual states and interaction states
* the recording input uses a glass-style toolbar background
* the recording input contains a live waveform view
* the recording input shows a stop action at the right edge using `stop.circle.fill`

When stop is pressed:

* `RecordingInputToolbar` stays visible
* it switches to a stopped-recording state internally
* it shows a close action at the right edge using `xmark.circle.fill`
* pressing close resets the recording input back to its default hidden/inactive state
* the right toolbar shows `Send` using `arrow.up.circle.fill`
* the `Send` action should be visually tinted blue and feel like the primary next action

While the recording toolbar is visible:

* hide playback controls in the toolbar
* hide review controls in the toolbar

### Analysis action

Show a compact `Review` action or status control with one of:

* `Reviewing` using `arrow.down.message.fill`
* `Reviewed` using:

  * `checkmark.message.fill` when the result is effectively perfect
  * `ellipsis.message.fill` when the result contains marks / info
* `Unavailable` using `exclamationmark.message.fill`

Behavior:

* `Reviewing` is not tappable
* `Reviewed` is tappable and opens review details if needed
* `Unavailable` is tappable and explains that review could not be completed via a simple bottom sheet
* `Reviewed` visually covers both internal `info` and `perfect`, while the app state still distinguishes them
* show review controls whenever recording/send-ready mode is not active and the latest attempt is either loading or already exists in session history

---

## Animation requirements

### Required

1. Quote word darkening during tutor playback
2. Record action disappearing into a separate recording input + stop control
3. Stop control transitioning into Send after recording ends
4. Mark underline reveal when a reviewed-with-marks result arrives
5. Bottom sheet presentation for feedback if used

### Nice to have

1. Current-word subtle highlight during tutor playback
2. Brief positive animation when a previously marked word is corrected on a later attempt
3. Soft status transitions between reviewing / reviewed / unavailable

Keep animations restrained and purposeful.

---

## Mobile architecture

Use:

* **SwiftUI** for UI
* **MVVM** for screen/state orchestration
* **Combine** where it genuinely helps for observable state
* async/await is acceptable for networking and backend calls

Recommended approach:

* SwiftUI views stay dumb and declarative
* `MainViewModel` owns screen behavior and state transitions
* LiveKit and audio concerns are isolated behind managers/services
* backend-facing repositories/services stay separate from UI state logic
* toolbar rendering should be derived from separate playback state, local recording draft state, and latest-attempt review state instead of flattened into one enum
* current local recording draft state should be kept separate from attempt-history review state
* playback state should remain separate from both draft state and latest-attempt review state

### Suggested frontend architecture

* `Features/Main` for the one-screen app flow and phases
* `Components` for reusable visual pieces
* `Domain` for models and repositories
* `Audio` for playback/recording logic
* `LiveKit` for realtime session management
* `Theme` for design tokens

---

## Frontend task split

### Frontend task 1 — Project skeleton

* Create SwiftUI app structure
* Create theme tokens if needed
* Set up preview support and mock data

### Frontend task 2 — Core domain models

Implement models for:

* `Quote`
* `QuoteToken`
* `PracticeAnalysis`
* `MarkedToken`
* `PracticeSessionPhase`
* `PlaybackState`
* `RecordingState`
* `AnalysisState`
* a lightweight attempt-history model
* a lightweight local draft model if needed

### Frontend task 3 — Main screen and state model

Implement:

* `MainScreen`
* `MainViewModel`
* start state + practice state + quotes sheet
* explicit toolbar/action-state transitions
* mock state switching before real backend integration

### Frontend task 4 — Quote text UI

Implement:

* quote reading surface
* dimmed-to-spoken token darkening model
* underline rendering for marked words
* flat system-like presentation without decorative card chrome

### Frontend task 5 — Action stack

Implement:

* playback action behavior with SF Symbols
* recording action behavior with standalone `RecordingInputToolbar`
* review status button behavior with SF Symbols
* toolbar transitions

### Frontend task 6 — Recording waveform UI

Implement:

* standalone `RecordingInputToolbar` component
* glass-style recording input background
* live waveform field driven by microphone metering
* internal state handling for recording / stopped / reset
* stop action at the right edge while recording
* close action at the right edge after stopping
* send state coordination with the main action toolbar

### Frontend task 7 — Review details

Implement:

* review status UI for internal `info` / `perfect` / `unavailable`
* optional bottom sheet for secondary feedback if needed
* latest-attempt review display based on attempt history

### Frontend task 8 — Audio + playback sync

Implement:

* tutor playback manager
* quote token darkening based on playback progress
* pause / repeat logic
* finished-at-end playback behavior
* recording start forcing playback into finished-at-end behavior

### Frontend task 9 — LiveKit client integration

Implement:

* token fetch
* room join/leave
* subscribe to tutor audio
* publish learner audio / bridge recording flow
* connection state handling

### Frontend task 10 — Backend integration

Wire screen to:

* quotes endpoint
* session start endpoint
* analysis result polling
* result mapping to UI states
* learner recording submission flow

---

## Backend task split

### Backend task 1 — Tech stack and skeleton

Use:

* **Python 3.11+**
* **FastAPI** for HTTP endpoints
* **LiveKit Agents (Python)** for the tutor agent
* simple in-memory session storage for MVP if needed

Keep backend intentionally small.

### Backend task 2 — Config and environment

Implement config loading for:

* `LIVEKIT_URL`
* `LIVEKIT_API_KEY`
* `LIVEKIT_API_SECRET`
* optional model configuration env vars

### Backend task 3 — Quotes endpoint

Provide a minimal `GET /quotes` endpoint returning:

* quote id
* preview text
* full quote text
* book title
* author

Use mock/in-memory data if necessary for MVP.

### Backend task 4 — LiveKit token endpoint

Implement `POST /livekit/token`.
The mobile app must never mint tokens client-side.

### Backend task 5 — Practice session start

Implement `POST /practice/session/start`.
Input:

* selected quote id or quote text

Output:

* session id
* room name / token info if appropriate
* tutor/session context if needed

### Backend task 6 — Tutor agent

Implement LiveKit agent process.
Responsibilities:

* join room as tutor participant
* read selected quote aloud
* handle playback session context
* receive learner attempt
* prepare or request analysis result

### Backend task 7 — Analysis result shaping

Implement result mapping into app-facing states:

* `loading`
* `info`
* `perfect`
* `unavailable`

`info` response should include:

* marked words/tokens
* concise tutor feedback if needed

`perfect` response may include:

* short praise message
* no marks

`unavailable` response should include:

* a brief explanation that review could not be completed

### Backend task 8 — Result polling endpoint

Implement `GET /practice/session/{id}/result`.
This should return current analysis state.

### Backend task 9 — Unavailable review behavior

If analysis times out or fails, map to `unavailable`.
The client should show a simple explanation of the failure via a bottom sheet.

---

## Backend responsibilities

The backend exists for two reasons:

1. LiveKit token generation must happen server-side.
2. The tutor agent runs as a backend participant and owns practice/review logic.

Additionally, the backend is the natural place for:

* quote retrieval
* session context
* analysis result shaping
* future progress logic

---

## Suggested repo structure

```text
QuoteApp/
├── apps/
│   ├── ios/
│   │   ├── QuoteApp/
│   │   │   ├── App/
│   │   │   │   ├── QuoteApp.swift
│   │   │   │   ├── RootView.swift
│   │   │   │   └── AppEnvironment.swift
│   │   │   ├── Features/
│   │   │   │   └── Main/
│   │   │   │       ├── MainScreen.swift
│   │   │   │       ├── MainViewModel.swift
│   │   │   │       ├── MainSessionState.swift
│   │   │   │       └── ActionToolbarState.swift
│   │   │   ├── Components/
│   │   │   │   ├── Header/
│   │   │   │   ├── Quote/
│   │   │   │   ├── Actions/
│   │   │   │   ├── Sheets/
│   │   │   │   └── Shared/
│   │   │   ├── Domain/
│   │   │   │   ├── Models/
│   │   │   │   ├── Repositories/
│   │   │   │   └── Services/
│   │   │   ├── Audio/
│   │   │   ├── LiveKit/
│   │   │   ├── Theme/
│   │   │   └── PreviewSupport/
│   │   └── QuoteApp.xcodeproj
│   │
│   └── backend/
│       ├── app/
│       │   ├── main.py
│       │   ├── config.py
│       │   ├── routes/
│       │   │   ├── token.py
│       │   │   ├── quotes.py
│       │   │   └── practice.py
│       │   ├── agents/
│       │   │   ├── speaking_tutor_agent.py
│       │   │   ├── prompts.py
│       │   │   └── analysis_mapper.py
│       │   ├── services/
│       │   │   ├── livekit_service.py
│       │   │   ├── quote_service.py
│       │   │   ├── practice_service.py
│       │   │   └── result_service.py
│       │   └── models/
│       │       ├── quote.py
│       │       ├── practice_session.py
│       │       ├── analysis_result.py
│       │       └── marked_token.py
│       ├── requirements.txt
│       └── .env.example
│
├── README.md
├── plan.md
├── workflow.md
└── scripts/
    ├── setup_backend.sh
    ├── run_backend.sh
    └── check_env.sh
```

---

## Suggested iOS files

### Feature files

* `MainScreen.swift`
* `MainViewModel.swift`
* `MainSessionState.swift`
* `ActionToolbarState.swift`

### Key components

* `BrandHeader.swift`
* `StartView.swift`
* `QuotePickerSheet.swift`
* `QuoteListItemView.swift`
* `QuoteTextView.swift`
* `ActionStackView.swift`
* `PlaybackActionButton.swift`
* `RecordingInputToolbar.swift`
* `RecordingWaveformField.swift`
* `RecordingInputToolbarState.swift`
* `ReviewStatusButton.swift`
* `TutorFeedbackSheet.swift`

### Managers / services

* `AudioSessionManager.swift`
* `TutorPlaybackManager.swift`
* `UserRecordingManager.swift`
* `PlaybackTimingCoordinator.swift`
* `LiveKitSessionManager.swift`
* `LiveKitTokenProvider.swift`
* `AnalysisPollingService.swift`

---

## Suggested backend files

### HTTP layer

* `main.py`
* `config.py`
* `routes/token.py`
* `routes/quotes.py`
* `routes/practice.py`

### Agent layer

* `agents/speaking_tutor_agent.py`
* `agents/prompts.py`
* `agents/analysis_mapper.py`

### Service layer

* `services/livekit_service.py`
* `services/quote_service.py`
* `services/practice_service.py`
* `services/result_service.py`

### Models

* `models/quote.py`
* `models/practice_session.py`
* `models/analysis_result.py`
* `models/marked_token.py`

---

## Setup scripts

Add simple scripts for reviewer convenience.

### `scripts/setup_backend.sh`

Responsibilities:

* create Python virtualenv if missing
* install `requirements.txt`
* verify `.env` exists or print instructions

### `scripts/run_backend.sh`

Responsibilities:

* source virtualenv
* run FastAPI dev server and/or agent entrypoint
* support both simulator/local mode and device/LAN mode
* make it easy to bind to `0.0.0.0` for physical-device testing
* print the backend URL to use on a real device when running in LAN mode

### `scripts/check_env.sh`

Responsibilities:

* verify required env vars are set
* print missing values clearly

Keep scripts small and readable.

---

## README requirements

`README.md` should include:

### 1. What the project is

Short product description.

### 2. Architecture overview

A short paragraph describing:

* SwiftUI iOS client
* FastAPI backend
* LiveKit token endpoint
* LiveKit Agent tutor
* analysis result mapping

### 3. Setup requirements

* Xcode version
* iOS version target
* Python version
* LiveKit account requirement

### 4. Environment setup

Explain `.env.example` and required env vars.

### 5. How to run backend

* install dependencies
* fill `.env`
* run scripts
* explain simulator/local vs real-device/LAN backend startup

### 6. How to run iOS app

* open Xcode project
* set backend base URL if needed
* run on simulator/device
* explain simulator localhost vs device LAN URL setup

### 7. Key tradeoffs

Include:

* one-screen multi-phase UX
* quote-centered review instead of generic chat
* lightweight analysis states including review-unavailable
* modest pronunciation feedback claims

### 8. Known limitations

Examples:

* mock quotes / limited quote library
* heuristic playback-to-token timing
* no auth / no user history

---

## `.env.example`

At minimum include:

```env
LIVEKIT_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000
```

Optional model config:

```env
LIVEKIT_LLM_MODEL=
LIVEKIT_STT_MODEL=
LIVEKIT_TTS_MODEL=
```

---

## Development order

### Step 1

Build a static SwiftUI screen matching the approved mock:

* start state with Let’s speak
* bottom-sheet quotes picker
* practice state with large quote text
* flat system-styled action row / toolbar
* SF Symbols for record / repeat / review states

### Step 2

Implement quote token rendering model:

* dimmed
* spoken
* marked

### Step 3

Implement action stack behavior and standalone `RecordingInputToolbar`.

### Step 4

Add review states and optional feedback sheet, including review-unavailable.

### Step 5

Create backend skeleton, quotes endpoint, token endpoint.

### Step 6

Integrate LiveKit room connection and tutor playback.

### Step 7

Wire learner recording and result polling.

### Step 8

Polish transitions and cleanup README/setup.

---

## Notes for Codex

* Keep the app small and coherent.
* Do not add auth, settings, session history, or generic chat.
* Do not over-engineer pronunciation scoring.
* The most important thing is a believable end-to-end speaking-practice loop.
* Prefer clear state transitions over feature breadth.
