"""In-memory practice session storage for the MVP backend."""

from threading import Lock
from typing import Optional
from uuid import uuid4

from app.models.analysis_result import AnalysisState
from app.models.practice_session import PracticeAttempt, PracticeSession
from app.services.result_service import build_mock_review_result, choose_mock_state_for_quote


class SessionNotFoundError(Exception):
    """Raised when a session ID does not exist in in-memory storage."""


_SESSIONS: dict[str, PracticeSession] = {}
_SESSIONS_LOCK = Lock()


def create_practice_session(
    *,
    quote_id: str,
    quote_text: Optional[str] = None,
    mock_result: Optional[AnalysisState] = None,
) -> PracticeSession:
    """Creates a session with one initial mock attempt for local integration."""

    session_id = str(uuid4())
    attempt_id = str(uuid4())

    selected_state = mock_result or choose_mock_state_for_quote(quote_id)

    initial_attempt = PracticeAttempt(
        attempt_id=attempt_id,
        recording_reference=f"mock-recording-{attempt_id[:8]}",
        review_result=build_mock_review_result(state=selected_state, quote_text=quote_text),
    )

    session = PracticeSession(
        session_id=session_id,
        quote_id=quote_id,
        quote_text=quote_text,
        attempts=[initial_attempt],
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
