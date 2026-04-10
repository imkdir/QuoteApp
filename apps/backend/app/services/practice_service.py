"""In-memory practice session storage for the MVP backend."""

from pathlib import Path
from threading import Lock
from typing import Final
from typing import Optional
import tempfile
from uuid import uuid4

from app.models.analysis_result import AnalysisState
from app.models.practice_session import PracticeAttempt, PracticeSession
from app.services.result_service import build_mock_review_result


class SessionNotFoundError(Exception):
    """Raised when a session ID does not exist in in-memory storage."""


_SESSIONS: dict[str, PracticeSession] = {}
_SESSIONS_LOCK = Lock()
_SUBMISSIONS_ROOT: Final[Path] = Path(tempfile.gettempdir()) / "quoteapp-submissions"


def create_practice_session(
    *,
    quote_id: str,
    quote_text: Optional[str] = None,
    mock_result: Optional[AnalysisState] = None,
) -> PracticeSession:
    """Creates an empty in-memory practice session for one quote."""
    _ = mock_result

    session_id = str(uuid4())

    session = PracticeSession(
        session_id=session_id,
        quote_id=quote_id,
        quote_text=quote_text,
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
            review_result=build_mock_review_result(
                state=AnalysisState.loading,
                quote_text=session.quote_text,
            ),
        )
        session.attempts.append(attempt)
        return attempt


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
