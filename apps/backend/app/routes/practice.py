"""Practice session APIs for mock-backed session and latest-result integration."""

from fastapi import APIRouter, Body, Header, HTTPException, Query, status
from typing import Optional

from app.agents.speaking_tutor_agent import SpeakingTutorAgentRuntime
from app.models.analysis_result import AnalysisState
from app.models.practice_session import (
    StartPracticeSessionRequest,
    StartPracticeSessionResponse,
    SubmitPracticeAttemptResponse,
    TutorPlaybackCommandResponse,
)
from app.config import get_settings
from app.services.practice_service import (
    SessionNotFoundError,
    create_practice_session,
    get_practice_session,
    update_tutor_status,
    submit_practice_attempt,
)
from app.services.result_service import LatestAttemptResultResponse, build_latest_result_response

router = APIRouter(prefix="/practice", tags=["practice"])
_TUTOR_RUNTIME = SpeakingTutorAgentRuntime()


def _sync_tutor_status(session_id: str) -> None:
    context = _TUTOR_RUNTIME.context_for_session(session_id)
    if context is None:
        return

    try:
        update_tutor_status(
            session_id=session_id,
            status=context.status,
            message=context.status_message,
        )
    except SessionNotFoundError:
        return


@router.post("/session/start", response_model=StartPracticeSessionResponse)
def start_practice_session(
    payload: StartPracticeSessionRequest,
) -> StartPracticeSessionResponse:
    """Creates an in-memory practice session before learner attempts are submitted."""

    settings = get_settings()
    session = create_practice_session(
        quote_id=payload.quote_id,
        quote_text=payload.quote_text,
        mock_result=payload.mock_result,
    )
    tutor_context = _TUTOR_RUNTIME.ensure_session_tutor(
        session_id=session.session_id,
        room_name=session.livekit_room,
        quote_text=session.quote_text or "",
        settings=settings,
    )
    update_tutor_status(
        session_id=session.session_id,
        status=tutor_context.status,
        message=tutor_context.status_message,
    )

    latest_attempt = session.attempts[-1] if session.attempts else None

    return StartPracticeSessionResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        livekit_room=session.livekit_room,
        tutor_identity=session.tutor_identity,
        tutor_status=tutor_context.status,
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

    _sync_tutor_status(session_id)

    if not session.attempts:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "attempt_not_found",
                "message": f"No submitted attempts for session {session_id}.",
            },
        )

    response = build_latest_result_response(session=session, override_state=mock_result)
    _TUTOR_RUNTIME.note_latest_attempt(
        session_id=session_id,
        attempt_id=response.attempt_id,
        review_state=response.state.value,
    )
    return response


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
        _sync_tutor_status(session_id)
        attempt = submit_practice_attempt(
            session_id=session_id,
            audio_bytes=audio_bytes,
            original_filename=filename,
        )
        _TUTOR_RUNTIME.note_latest_attempt(
            session_id=session_id,
            attempt_id=attempt.attempt_id,
            review_state=AnalysisState.loading.value,
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


@router.post(
    "/session/{session_id}/tutor/play",
    response_model=TutorPlaybackCommandResponse,
)
def play_tutor_quote(session_id: str) -> TutorPlaybackCommandResponse:
    """Triggers backend tutor playback as room audio for the selected session quote."""

    settings = get_settings()
    context = _TUTOR_RUNTIME.context_for_session(session_id)
    if context is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": f"Session not found: {session_id}",
            },
        )

    try:
        _TUTOR_RUNTIME.request_quote_playback(session_id=session_id, settings=settings)
        _sync_tutor_status(session_id)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "tutor_unavailable",
                "message": str(exc),
            },
        ) from exc
    except Exception as exc:  # noqa: BLE001 - runtime boundary
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "tutor_playback_failed",
                "message": str(exc),
            },
        ) from exc

    return TutorPlaybackCommandResponse(
        session_id=session_id,
        status="playing",
        message="Tutor playback requested.",
    )


@router.post(
    "/session/{session_id}/tutor/stop",
    response_model=TutorPlaybackCommandResponse,
)
def stop_tutor_quote(session_id: str) -> TutorPlaybackCommandResponse:
    """Stops active backend tutor playback for the session, if any."""

    context = _TUTOR_RUNTIME.context_for_session(session_id)
    if context is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": f"Session not found: {session_id}",
            },
        )

    _TUTOR_RUNTIME.stop_quote_playback(session_id=session_id)
    _sync_tutor_status(session_id)

    return TutorPlaybackCommandResponse(
        session_id=session_id,
        status="stopped",
        message="Tutor playback stop requested.",
    )
