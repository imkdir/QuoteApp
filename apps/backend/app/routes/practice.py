"""Practice session APIs for mock-backed session and latest-result integration."""

from fastapi import APIRouter, Body, Header, HTTPException, Query, status
from typing import Optional

from app.models.analysis_result import AnalysisState
from app.models.practice_session import (
    StartPracticeSessionRequest,
    StartPracticeSessionResponse,
    SubmitPracticeAttemptResponse,
)
from app.services.practice_service import (
    SessionNotFoundError,
    create_practice_session,
    get_practice_session,
    submit_practice_attempt,
)
from app.services.result_service import LatestAttemptResultResponse, build_latest_result_response

router = APIRouter(prefix="/practice", tags=["practice"])


@router.post("/session/start", response_model=StartPracticeSessionResponse)
def start_practice_session(
    payload: StartPracticeSessionRequest,
) -> StartPracticeSessionResponse:
    """Creates an in-memory practice session before learner attempts are submitted."""

    session = create_practice_session(
        quote_id=payload.quote_id,
        quote_text=payload.quote_text,
        mock_result=payload.mock_result,
    )

    latest_attempt = session.attempts[-1] if session.attempts else None

    return StartPracticeSessionResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        latest_attempt_id=latest_attempt.attempt_id if latest_attempt else None,
        latest_result_state=(
            latest_attempt.review_result.state
            if latest_attempt and latest_attempt.review_result
            else None
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

    if not session.attempts:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "attempt_not_found",
                "message": f"No submitted attempts for session {session_id}.",
            },
        )

    return build_latest_result_response(session=session, override_state=mock_result)


@router.post(
    "/session/{session_id}/attempt/submit",
    response_model=SubmitPracticeAttemptResponse,
    status_code=status.HTTP_201_CREATED,
)
def submit_learner_attempt(
    session_id: str,
    audio_bytes: bytes = Body(media_type="application/octet-stream"),
    filename: Optional[str] = Header(default=None, alias="X-QuoteApp-Filename"),
    recording_reference: Optional[str] = Header(
        default=None,
        alias="X-QuoteApp-Recording-Reference",
    ),
) -> SubmitPracticeAttemptResponse:
    """Submits learner-recorded audio and creates a new loading attempt."""

    _ = recording_reference  # Reserved for future traceability across local/backend references.

    try:
        session = get_practice_session(session_id)
        attempt = submit_practice_attempt(
            session_id=session_id,
            audio_bytes=audio_bytes,
            original_filename=filename,
        )
    except SessionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": str(exc),
            },
        ) from exc
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "invalid_submission",
                "message": str(exc),
            },
        ) from exc

    return SubmitPracticeAttemptResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        attempt_id=attempt.attempt_id,
        recording_reference=attempt.recording_reference,
        state=attempt.review_result.state if attempt.review_result else AnalysisState.loading,
    )
