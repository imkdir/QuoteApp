"""Mock result helpers for mapping practice attempts into app-facing payloads."""

from datetime import datetime, timedelta, timezone
import re
from typing import Optional

from pydantic import BaseModel, Field

from app.models.analysis_result import AnalysisState, TutorReviewResult
from app.models.marked_token import MarkedToken
from app.models.practice_session import PracticeSession


class LatestAttemptResultResponse(BaseModel):
    """Latest attempt result shape consumed by the iOS practice flow."""

    session_id: str
    quote_id: str
    attempt_id: str
    recording_reference: str
    state: AnalysisState
    marked_tokens: list[MarkedToken] = Field(default_factory=list)
    feedback_text: Optional[str] = None


_MOCK_STATE_ORDER: list[AnalysisState] = [
    AnalysisState.loading,
    AnalysisState.info,
    AnalysisState.perfect,
    AnalysisState.unavailable,
]
_SUBMITTED_ATTEMPT_STATE_ORDER: list[AnalysisState] = [
    AnalysisState.info,
    AnalysisState.perfect,
    AnalysisState.unavailable,
]
_LOADING_RESOLVE_SECONDS = 2
_LOADING_TIMEOUT_SECONDS = 12


def choose_mock_state_for_quote(quote_id: str) -> AnalysisState:
    """Deterministically maps quote IDs into one of the four analysis states."""

    state_index = sum(ord(char) for char in quote_id) % len(_MOCK_STATE_ORDER)
    return _MOCK_STATE_ORDER[state_index]


def build_mock_review_result(
    *,
    state: AnalysisState,
    quote_text: Optional[str] = None,
) -> TutorReviewResult:
    """Builds a predictable mock review payload for the requested state."""

    if state == AnalysisState.loading:
        return TutorReviewResult(
            state=AnalysisState.loading,
            feedback_text="Reviewing the latest attempt.",
        )

    if state == AnalysisState.info:
        marked_tokens = _extract_marked_tokens(quote_text)
        return TutorReviewResult(
            state=AnalysisState.info,
            marked_tokens=marked_tokens,
            feedback_text="Good attempt. Try the marked words again with clearer stress.",
        )

    if state == AnalysisState.perfect:
        return TutorReviewResult(
            state=AnalysisState.perfect,
            feedback_text="Great pacing and pronunciation. No marked words this time.",
        )

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text="Review could not be completed for this attempt.",
    )


def build_latest_result_response(
    *,
    session: PracticeSession,
    override_state: Optional[AnalysisState] = None,
) -> LatestAttemptResultResponse:
    """Maps the latest attempt into the response shape used by the client."""

    latest_attempt = session.attempts[-1]

    review_result = latest_attempt.review_result or build_mock_review_result(
        state=AnalysisState.loading,
        quote_text=session.quote_text,
    )

    if latest_attempt.is_superseded and review_result.state == AnalysisState.loading:
        review_result = _make_superseded_unavailable_result()
        latest_attempt.review_result = review_result

    if _is_loading_timed_out(
        created_at=latest_attempt.created_at,
        review_result=review_result,
    ):
        review_result = _make_timeout_unavailable_result()
        latest_attempt.review_result = review_result

    if _is_ready_for_mock_completion(
        created_at=latest_attempt.created_at,
        review_result=review_result,
    ):
        completed_state = choose_mock_state_for_attempt(
            quote_id=session.quote_id,
            attempt_id=latest_attempt.attempt_id,
        )
        review_result = build_mock_review_result(
            state=completed_state,
            quote_text=session.quote_text,
        )
        latest_attempt.review_result = review_result

    if override_state is not None:
        review_result = build_mock_review_result(
            state=override_state,
            quote_text=session.quote_text,
        )

    return LatestAttemptResultResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        attempt_id=latest_attempt.attempt_id,
        recording_reference=latest_attempt.recording_reference,
        state=review_result.state,
        marked_tokens=review_result.marked_tokens,
        feedback_text=review_result.feedback_text,
    )


def _is_loading_timed_out(*, created_at: datetime, review_result: TutorReviewResult) -> bool:
    """Returns true when loading has exceeded the mock timeout window."""

    if review_result.state != AnalysisState.loading:
        return False

    deadline = created_at + timedelta(seconds=_LOADING_TIMEOUT_SECONDS)
    return datetime.now(timezone.utc) >= deadline


def _is_ready_for_mock_completion(*, created_at: datetime, review_result: TutorReviewResult) -> bool:
    """Returns true when a submitted loading attempt should resolve to a mock terminal state."""

    if review_result.state != AnalysisState.loading:
        return False

    ready_at = created_at + timedelta(seconds=_LOADING_RESOLVE_SECONDS)
    return datetime.now(timezone.utc) >= ready_at


def choose_mock_state_for_attempt(*, quote_id: str, attempt_id: str) -> AnalysisState:
    """Deterministically maps a submitted attempt into a terminal mock state."""

    state_index = sum(ord(char) for char in f"{quote_id}:{attempt_id}") % len(
        _SUBMITTED_ATTEMPT_STATE_ORDER
    )
    return _SUBMITTED_ATTEMPT_STATE_ORDER[state_index]


def _make_timeout_unavailable_result() -> TutorReviewResult:
    """Maps stale loading states into unavailable for client consumption."""

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text="Review timed out before completion.",
    )


def _make_superseded_unavailable_result() -> TutorReviewResult:
    """Maps superseded loading attempts into unavailable for consistency."""

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text="Review was superseded by a newer local recording draft.",
    )


def _extract_marked_tokens(quote_text: Optional[str]) -> list[MarkedToken]:
    """Returns a small deterministic list of marked tokens for info results."""

    words = _normalized_words(quote_text)

    if not words:
        return [
            MarkedToken(text="word", normalized_text="word"),
            MarkedToken(text="stress", normalized_text="stress"),
        ]

    indexes = [1, min(4, len(words) - 1)] if len(words) > 1 else [0]
    unique_indexes = sorted(set(indexes))

    return [
        MarkedToken(
            text=words[index],
            normalized_text=words[index],
        )
        for index in unique_indexes
    ]


def _normalized_words(quote_text: Optional[str]) -> list[str]:
    """Splits and normalizes quote text into simple alphanumeric tokens."""

    if not quote_text:
        return []

    return [
        token.lower()
        for token in re.findall(r"[A-Za-z0-9']+", quote_text)
        if token.strip()
    ]
