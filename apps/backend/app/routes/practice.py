"""Practice session APIs for mock-backed session and latest-result integration."""

from fastapi import APIRouter, HTTPException, Query, status
from typing import Optional

from app.models.analysis_result import AnalysisState
from app.models.practice_session import (
    StartPracticeSessionRequest,
    StartPracticeSessionResponse,
)
from app.services.practice_service import (
    SessionNotFoundError,
    create_practice_session,
    get_practice_session,
)
from app.services.result_service import LatestAttemptResultResponse, build_latest_result_response

router = APIRouter(prefix="/practice", tags=["practice"])


@router.post("/session/start", response_model=StartPracticeSessionResponse)
def start_practice_session(
    payload: StartPracticeSessionRequest,
) -> StartPracticeSessionResponse:
    """Creates a mock in-memory practice session and initial latest attempt."""

    session = create_practice_session(
        quote_id=payload.quote_id,
        quote_text=payload.quote_text,
        mock_result=payload.mock_result,
    )

    latest_attempt = session.attempts[-1]

    return StartPracticeSessionResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        latest_attempt_id=latest_attempt.attempt_id,
        latest_result_state=(
            latest_attempt.review_result.state if latest_attempt.review_result else None
        ),
    )


@router.get(
    "/session/{session_id}/result",
    response_model=LatestAttemptResultResponse,
)
def get_latest_attempt_result(
    session_id: str,
    mock_result: Optional[AnalysisState] = Query(default=None),
) -> LatestAttemptResultResponse:
    """Returns the latest attempt review state for the requested session."""

    try:
        session = get_practice_session(session_id)
    except SessionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": str(exc),
            },
        ) from exc

    return build_latest_result_response(session=session, override_state=mock_result)
