"""Latest-attempt result mapping helpers for practice polling responses."""

from datetime import datetime, timedelta, timezone
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


_LOADING_TIMEOUT_SECONDS = 12


def build_latest_result_response(*, session: PracticeSession) -> LatestAttemptResultResponse:
    """Maps the latest persisted attempt into the client polling response shape."""

    latest_attempt = session.attempts[-1]

    review_result = latest_attempt.review_result or TutorReviewResult(
        state=AnalysisState.loading,
        feedback_text="Reviewing the latest attempt.",
    )

    if latest_attempt.is_superseded and review_result.state == AnalysisState.loading:
        review_result = make_superseded_unavailable_result()
        latest_attempt.review_result = review_result

    if _is_loading_timed_out(
        created_at=latest_attempt.created_at,
        review_result=review_result,
    ):
        review_result = _make_timeout_unavailable_result()
        latest_attempt.review_result = review_result

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
    """Returns true when loading has exceeded the client polling timeout window."""

    if review_result.state != AnalysisState.loading:
        return False

    deadline = created_at + timedelta(seconds=_LOADING_TIMEOUT_SECONDS)
    return datetime.now(timezone.utc) >= deadline


def _make_timeout_unavailable_result() -> TutorReviewResult:
    """Maps stale loading states into unavailable for client consumption."""

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text="Review timed out before completion.",
    )


def make_superseded_unavailable_result() -> TutorReviewResult:
    """Maps superseded loading attempts into unavailable for consistency."""

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text="Review was superseded by a newer local recording draft.",
    )
