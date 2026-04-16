# Tutor Audio Incident Note: 503, Quote-2 Latch, and Hardening

## Goal

Show exactly why one `/tutor/audio` failure window could make playback look stuck on one quote, and show the code-level fixes.

## Plain-English Summary

1. The trigger window was a `/tutor/audio` failure (often `503`) or quote-context mismatch timing.
2. The sticky symptom was stale playback identity plus cache-first early return.
3. If stale identity pointed to quote #2 and quote #2 already had a real cache file, playback could keep returning quote #2 audio.

---

## Pre-Fix Summary + Evidence Pairs

### Pair 1
Summary: Quote switch reused the existing backend session id.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 255-280):
>
> ```text
> 255  func selectQuote(_ quote: Quote?) {
> 256      let previousSessionID = sessionState.practiceSession?.backendSessionID
> 257      let previousLiveKitRoomName = sessionState.practiceSession?.liveKitRoomName
> ...
> 275      sessionState = .practice(
> 276          PracticeSession(
> 277              quote: quote,
> 278              backendSessionID: previousSessionID,
> 279              liveKitRoomName: previousLiveKitRoomName
> 280          )
> ```

### Pair 2
Summary: Quote switch trusted and stored backend-returned `tutorPlaybackIdentity` directly.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 1544-1560):
>
> ```text
> 1544  do {
> 1545      let updatedSession = try await practiceRepository.updateSessionQuote(
> 1546          sessionID: sessionID,
> 1547          quoteID: quote.id,
> 1548          quoteText: quote.text
> 1549      )
> ...
> 1554      updatePracticeSession { session in
> 1555          session.backendSessionID = updatedSession.sessionID
> 1556          if let liveKitRoom = updatedSession.liveKitRoom, !liveKitRoom.isEmpty {
> 1557              session.liveKitRoomName = liveKitRoom
> 1558          }
> 1559          session.tutorPlaybackIdentity = updatedSession.tutorPlaybackIdentity
> 1560      }
> ```

### Pair 3
Summary: `/session/{id}/quote` returned a playback identity derived from backend runtime context.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/backend/app/routes/practice.py`, lines 139-199):
>
> ```text
> 139  @router.post("/session/{session_id}/quote", ...)
> ...
> 180      tutor_playback_identity: Optional[str] = None
> 181      try:
> 182          tutor_playback_identity = _TUTOR_RUNTIME.playback_identity_for_session(
> 183              session_id=session.session_id,
> 184              settings=settings,
> 185          )
> ...
> 189      return StartPracticeSessionResponse(
> ...
> 195          tutor_playback_identity=tutor_playback_identity,
> ```

### Pair 4
Summary: Runtime playback identity was built from in-memory context `quote_id` and `quote_text`.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/backend/app/agents/speaking_tutor_agent.py`, lines 233-245):
>
> ```text
> 233  def playback_identity_for_session(self, *, session_id: str, settings: Settings) -> str:
> ...
> 240      profile = self._ensure_tts_profile(session_id=session_id, settings=settings)
> 241      return _build_playback_identity(
> 242          quote_id=context.quote_id,
> 243          quote_text=context.quote_text,
> 244          tts_profile=profile,
> 245      )
> ```
>
> From pre-fix commit `4b34aa0` (`apps/backend/app/agents/speaking_tutor_agent.py`, lines 375-395):
>
> ```text
> 389      context.quote_id = quote_id
> 390      context.quote_text = quote_text
> ```

### Pair 5
Summary: iOS playback checked local cache first and returned early on hit.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 498-516):
>
> ```text
> 498  let playbackIdentity = self.sessionState.practiceSession?.tutorPlaybackIdentity
> 499  if let playbackIdentity,
> 500     let cachedArtifact = self.tutorAudioCache.cachedAudioArtifact(
> 501         for: playbackIdentity
> 502     ) {
> ...
> 514      self.completeTutorPlaybackRequest()
> 515      self.practiceStatusMessage = "Tutor playback started from device cache."
> 516      return
> ```

### Pair 6
Summary: `/tutor/audio` was only reached on cache miss, and then it rewrote identity.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 522-554):
>
> ```text
> 522  self.isTutorAudioDownloadInFlight = true
> ...
> 525      artifact = try await practiceRepository.fetchTutorPlaybackAudioArtifact(
> 526          sessionID: sessionID
> 527      )
> ...
> 552  self.updatePracticeSession { session in
> 553      session.tutorPlaybackIdentity = artifact.playbackIdentity
> 554  }
> ```

### Pair 7
Summary: On `/tutor/audio` error, iOS fell back to LiveKit playback, so failure could be masked.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 580-590):
>
> ```text
> 580  } catch {
> ...
> 585      let fallbackStarted = await self.startTutorPlaybackViaLiveKitFallback(
> 586          for: selectedQuote,
> 587          playbackStateBeforeCommand: playbackStateBeforeCommand
> 588      )
> ```

### Pair 8
Summary: Backend mapped artifact runtime failures to HTTP `503`.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/backend/app/routes/practice.py`, lines 312-341):
>
> ```text
> 329      try:
> 330          artifact = _TUTOR_RUNTIME.build_tutor_audio_artifact(
> ...
> 334      except RuntimeError as exc:
> 335          raise HTTPException(
> 336              status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
> 337              detail={"code": "tutor_audio_unavailable", "message": str(exc)},
> 338          ) from exc
> ```

---

## Why Quote #2 Could Dominate (Summary + Evidence Pairs)

### Pair 1
Summary: Playback chose cache by `tutorPlaybackIdentity` key, not directly by currently selected quote id.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 498-502):
>
> ```text
> 498  let playbackIdentity = self.sessionState.practiceSession?.tutorPlaybackIdentity
> 499  if let playbackIdentity,
> 500     let cachedArtifact = self.tutorAudioCache.cachedAudioArtifact(
> 501         for: playbackIdentity
> 502     ) {
> ```

### Pair 2
Summary: Once cache hit happened, function returned early and skipped backend refresh.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 514-516):
>
> ```text
> 514      self.completeTutorPlaybackRequest()
> 515      self.practiceStatusMessage = "Tutor playback started from device cache."
> 516      return
> ```

### Pair 3
Summary: Because fallback could still play audio, a transient `/tutor/audio` failure might not look like a hard error to users.

Evidence:

> From pre-fix commit `4b34aa0` (`apps/ios/QuoteApp/Features/Main/MainViewModel.swift`, lines 585-588):
>
> ```text
> 585      let fallbackStarted = await self.startTutorPlaybackViaLiveKitFallback(
> 586          for: selectedQuote,
> 587          playbackStateBeforeCommand: playbackStateBeforeCommand
> 588      )
> ```

---

## Why Reinstall/Kill Might Not Clear It (Summary + Evidence Pair)

Summary: iOS process reset does not reset backend in-memory runtime state while server keeps running.

Evidence:

> From current `apps/backend/app/agents/speaking_tutor_agent.py` (`SpeakingTutorAgentRuntime.__init__`, lines 131-135):
>
> ```text
> 131  self._contexts: dict[str, TutorSessionContext] = {}
> 132  self._playback_stop_events: dict[str, Event] = {}
> 133  self._playback_jobs: dict[str, Future[None]] = {}
> 134  self._tts_profiles: dict[str, TutorTTSProfile] = {}
> 135  self._audio_artifact_cache: OrderedDict[str, TutorPlaybackAudioArtifact] = OrderedDict()
> ```

---

## Corrected Logic Summary + Evidence Pairs

### Pair 1
Summary: iOS now tracks backend quote context explicitly (`backendQuoteID`).

Evidence:

> From current `apps/ios/QuoteApp/Features/Main/MainSessionState.swift`:
>
> ```text
> var backendQuoteID: String?
> ```

### Pair 2
Summary: Before cache lookup and `/tutor/audio`, iOS verifies backend quote context and repairs mismatch.

Evidence:

> From current `apps/ios/QuoteApp/Features/Main/MainViewModel.swift` (playback path):
>
> ```text
> sessionID = try await self.ensureBackendSessionQuoteContext(
>     for: selectedQuote,
>     sessionID: sessionID
> )
> ```
>
> From current `apps/ios/QuoteApp/Features/Main/MainViewModel.swift` (`ensureBackendSessionQuoteContext`):
>
> ```text
> if let practiceSession = sessionState.practiceSession,
>    practiceSession.backendSessionID == sessionID,
>    practiceSession.backendQuoteID == quote.id {
>     return sessionID
> }
> ...
> catch let PracticeFlowError.quoteContextMismatch(...) {
>     updatePracticeSession { session in
>         session.backendSessionID = nil
>         session.backendQuoteID = nil
>         session.liveKitRoomName = nil
>         session.tutorPlaybackIdentity = nil
>     }
>     return try await ensurePracticeSessionID(for: quote)
> }
> ```

### Pair 3
Summary: On quote switch, iOS no longer trusts precomputed switch identity.

Evidence:

> From current `apps/ios/QuoteApp/Features/Main/MainViewModel.swift` (`switchQuoteInExistingSession`):
>
> ```text
> // Do not trust precomputed playback identity on quote switch.
> // Use the identity returned with the actual /tutor/audio artifact instead.
> session.tutorPlaybackIdentity = nil
> ```

### Pair 4
Summary: Backend `/tutor/audio` now attempts runtime resync and retries artifact build once before returning `503`.

Evidence:

> From current `apps/backend/app/routes/practice.py`:
>
> ```text
> context = _TUTOR_RUNTIME.context_for_session(session_id)
> if context is None:
>     recovery_error = _resync_tutor_runtime_session(session_id, settings)
> ...
> try:
>     artifact = _TUTOR_RUNTIME.build_tutor_audio_artifact(...)
> except RuntimeError as exc:
>     first_runtime_error = exc
>     recovery_error = _resync_tutor_runtime_session(session_id, settings)
>     try:
>         artifact = _TUTOR_RUNTIME.build_tutor_audio_artifact(...)
>     except RuntimeError as retry_exc:
>         raise HTTPException(status_code=503, detail={...})
> ```

### Pair 5
Summary: Backend synthesis now retries once on retryable transient errors and refreshes TTS profile.

Evidence:

> From current `apps/backend/app/agents/speaking_tutor_agent.py` (`build_tutor_audio_artifact`):
>
> ```text
> for attempt in range(_AUDIO_ARTIFACT_SYNTHESIS_MAX_ATTEMPTS):
> ...
> except Exception as exc:
>     should_retry = (
>         attempt + 1 < _AUDIO_ARTIFACT_SYNTHESIS_MAX_ATTEMPTS
>         and _is_retryable_tutor_audio_error(exc)
>     )
>     if not should_retry:
>         break
>     self.invalidate_tts_profile(session_id=session_id)
>     sleep(_AUDIO_ARTIFACT_SYNTHESIS_RETRY_BACKOFF_SECONDS)
>     continue
> ```

---

## Corrected End-to-End ASCII Flow

```text
User taps Play
  |
  v
ensurePracticeSessionID(selectedQuote)
  |
  v
ensureBackendSessionQuoteContext(selectedQuote, sessionID)
  |
  +--> mismatch => clear stale linkage + recreate session
  |
  v
cache lookup by tutorPlaybackIdentity
  |
  +--> hit => play local file (fast path)
  |
  +--> miss => GET /session/{id}/tutor/audio
               |
               +--> backend tries runtime resync if needed
               +--> backend builds artifact (retry once on retryable failure)
               +--> return wav + playback identity
  |
  v
iOS stores artifact and identity, then plays local file
  |
  v
if /tutor/audio still fails => LiveKit fallback path
```
