"""In-memory practice session storage for the MVP backend."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
from threading import Lock
from typing import Final
from typing import Optional
import tempfile
from time import sleep
from uuid import uuid4

from app.agents.analysis_mapper import (
    AttemptAnalysisInput,
    loading_result,
    map_attempt_to_review,
    unavailable_result,
)
from app.models.analysis_result import AnalysisState
from app.models.practice_session import PracticeAttempt, PracticeSession
from app.services.result_service import make_superseded_unavailable_result


class SessionNotFoundError(Exception):
    """Raised when a session ID does not exist in in-memory storage."""


_SESSIONS: dict[str, PracticeSession] = {}
_SESSIONS_LOCK = Lock()
_SUBMISSIONS_ROOT: Final[Path] = Path(tempfile.gettempdir()) / "quoteapp-submissions"
_REVIEW_EXECUTOR: Final[ThreadPoolExecutor] = ThreadPoolExecutor(
    max_workers=4, thread_name_prefix="quoteapp-review-worker"
)
_REVIEW_DELAY_SECONDS: Final[float] = 1.0


def create_practice_session(
    *,
    quote_id: str,
    quote_text: Optional[str] = None,
    mock_result: Optional[AnalysisState] = None,
) -> PracticeSession:
    """Creates an empty in-memory practice session for one quote."""
    _ = mock_result

    session_id = str(uuid4())
    room_name = make_livekit_room_name(quote_id=quote_id, session_id=session_id)
    tutor_identity = f"tutor-{session_id[:8]}"

    session = PracticeSession(
        session_id=session_id,
        quote_id=quote_id,
        quote_text=quote_text,
        livekit_room=room_name,
        tutor_identity=tutor_identity,
        tutor_status="pending",
        tutor_status_message="Tutor context created.",
        attempts=[],
    )

    with _SESSIONS_LOCK:
        _SESSIONS[session_id] = session

    return session


def get_practice_session(session_id: str) -> PracticeSession:
    """Returns the existing in-memory practice session for the given ID."""

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)

    if session is None:
        raise SessionNotFoundError(f"Session not found: {session_id}")

    return session


def mark_attempt_superseded(*, session_id: str, attempt_id: str) -> None:
    """Marks a loading attempt as superseded for client-facing selection rules."""

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)
        if session is None:
            raise SessionNotFoundError(f"Session not found: {session_id}")

        for attempt in session.attempts:
            if attempt.attempt_id != attempt_id:
                continue

            attempt.is_superseded = True
            if attempt.review_result and attempt.review_result.state == AnalysisState.loading:
                attempt.review_result = make_superseded_unavailable_result()
            return


def submit_practice_attempt(
    *,
    session_id: str,
    audio_bytes: bytes,
    original_filename: Optional[str] = None,
) -> PracticeAttempt:
    """Persists learner audio bytes and appends a new loading attempt."""

    if not audio_bytes:
        raise ValueError("audio payload is empty")

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)
        if session is None:
            raise SessionNotFoundError(f"Session not found: {session_id}")

        attempt_id = str(uuid4())
        extension = _file_extension(original_filename)
        recording_path = _persist_submission_audio(
            session_id=session_id,
            attempt_id=attempt_id,
            extension=extension,
            audio_bytes=audio_bytes,
        )

        attempt = PracticeAttempt(
            attempt_id=attempt_id,
            recording_reference=str(recording_path),
            review_result=loading_result(),
        )
        session.attempts.append(attempt)

        tutor_available = session.tutor_status != "failed"
        tutor_failure_reason = session.tutor_status_message if not tutor_available else None

    _REVIEW_EXECUTOR.submit(
        _resolve_review_for_attempt,
        session_id,
        attempt_id,
        audio_bytes,
        tutor_available,
        tutor_failure_reason,
    )
    return attempt


def update_tutor_status(
    *,
    session_id: str,
    status: str,
    message: str | None = None,
) -> None:
    """Updates inspectable tutor runtime status for a session."""

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)
        if session is None:
            raise SessionNotFoundError(f"Session not found: {session_id}")

        session.tutor_status = status
        session.tutor_status_message = message


def _persist_submission_audio(
    *,
    session_id: str,
    attempt_id: str,
    extension: str,
    audio_bytes: bytes,
) -> Path:
    session_dir = _SUBMISSIONS_ROOT / session_id
    session_dir.mkdir(parents=True, exist_ok=True)

    destination = session_dir / f"{attempt_id}{extension}"
    destination.write_bytes(audio_bytes)
    return destination


def _file_extension(original_filename: Optional[str]) -> str:
    if not original_filename:
        return ".m4a"

    suffix = Path(original_filename).suffix.lower()
    if not suffix or len(suffix) > 8:
        return ".m4a"

    return suffix


def make_livekit_room_name(*, quote_id: str, session_id: str) -> str:
    """Builds the deterministic room name expected by the iOS client."""

    raw = f"practice-{quote_id}-{session_id}"
    sanitized = re.sub(r"[^A-Za-z0-9\-_]", "", raw)
    return sanitized or "practice-default"


def _resolve_review_for_attempt(
    session_id: str,
    attempt_id: str,
    audio_bytes: bytes,
    tutor_available: bool,
    tutor_failure_reason: str | None,
) -> None:
    """Background review worker for one submitted learner attempt."""

    sleep(_REVIEW_DELAY_SECONDS)

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)
        if session is None:
            return

        attempt = next((item for item in session.attempts if item.attempt_id == attempt_id), None)
        if attempt is None:
            return

        if attempt.is_superseded:
            attempt.review_result = make_superseded_unavailable_result()
            return

        quote_text = session.quote_text

    try:
        review_result = map_attempt_to_review(
            AttemptAnalysisInput(
                quote_text=quote_text,
                attempt_id=attempt_id,
                audio_size_bytes=len(audio_bytes),
                tutor_available=tutor_available,
                failure_reason=tutor_failure_reason,
            )
        )
    except Exception:  # noqa: BLE001 - defensive mapper boundary
        review_result = unavailable_result(reason="backend review pipeline failed")

    with _SESSIONS_LOCK:
        session = _SESSIONS.get(session_id)
        if session is None:
            return

        attempt = next((item for item in session.attempts if item.attempt_id == attempt_id), None)
        if attempt is None:
            return

        if attempt.is_superseded:
            attempt.review_result = make_superseded_unavailable_result()
            return

        attempt.review_result = review_result
