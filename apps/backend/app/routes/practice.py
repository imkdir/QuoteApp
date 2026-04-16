"""Practice session APIs for end-to-end quote playback and review loop."""

import base64
import json
import logging
from fastapi import APIRouter, Body, Header, HTTPException, Response, status
from typing import Optional

from app.agents.speaking_tutor_agent import SpeakingTutorAgentRuntime
from app.models.analysis_result import AnalysisState
from app.models.practice_session import (
    StartPracticeSessionRequest,
    StartPracticeSessionResponse,
    SubmitPracticeAttemptResponse,
    TutorPlaybackCommandResponse,
    UpdatePracticeSessionQuoteRequest,
)
from app.config import get_settings
from app.services.practice_service import (
    SessionNotFoundError,
    create_practice_session,
    get_practice_session,
    update_practice_session_quote,
    update_tutor_status,
    submit_practice_attempt,
)
from app.services.quote_service import list_quotes
from app.services.result_service import LatestAttemptResultResponse, build_latest_result_response

router = APIRouter(prefix="/practice", tags=["practice"])
_TUTOR_RUNTIME = SpeakingTutorAgentRuntime()
logger = logging.getLogger(__name__)


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


def _resolve_quote_text_for_session(session) -> str:
    quote_text = (session.quote_text or "").strip()
    if quote_text:
        return quote_text

    for quote in list_quotes():
        if quote.id == session.quote_id and quote.text.strip():
            return quote.text
    return ""


def _resync_tutor_runtime_session(session_id: str, settings) -> Optional[str]:
    try:
        session = get_practice_session(session_id)
    except SessionNotFoundError:
        return None

    resolved_quote_text = _resolve_quote_text_for_session(session)
    try:
        _TUTOR_RUNTIME.ensure_session_tutor(
            session_id=session.session_id,
            quote_id=session.quote_id,
            room_name=session.livekit_room,
            quote_text=resolved_quote_text,
            settings=settings,
        )
        _TUTOR_RUNTIME.update_session_quote_context(
            session_id=session.session_id,
            quote_id=session.quote_id,
            quote_text=resolved_quote_text,
        )
        _sync_tutor_status(session_id)
    except RuntimeError as exc:
        return str(exc)

    return None


@router.post("/session/start", response_model=StartPracticeSessionResponse)
def start_practice_session(
    payload: StartPracticeSessionRequest,
) -> StartPracticeSessionResponse:
    """Creates an in-memory practice session before learner attempts are submitted."""

    settings = get_settings()
    session = create_practice_session(
        quote_id=payload.quote_id,
        quote_text=payload.quote_text,
    )
    resolved_quote_text = _resolve_quote_text_for_session(session)
    tutor_context = _TUTOR_RUNTIME.ensure_session_tutor(
        session_id=session.session_id,
        quote_id=session.quote_id,
        room_name=session.livekit_room,
        quote_text=resolved_quote_text,
        settings=settings,
    )
    tutor_playback_identity: Optional[str] = None
    try:
        tutor_playback_identity = _TUTOR_RUNTIME.playback_identity_for_session(
            session_id=session.session_id,
            settings=settings,
        )
    except RuntimeError:
        tutor_playback_identity = None
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
        tutor_playback_identity=tutor_playback_identity,
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

    response = build_latest_result_response(session=session)
    _TUTOR_RUNTIME.note_latest_attempt(
        session_id=session_id,
        attempt_id=response.attempt_id,
        review_state=response.state.value,
    )
    return response


@router.post(
    "/session/{session_id}/quote",
    response_model=StartPracticeSessionResponse,
)
def update_session_quote(
    session_id: str,
    payload: UpdatePracticeSessionQuoteRequest,
) -> StartPracticeSessionResponse:
    """Updates quote context for an existing session without replacing the LiveKit room."""

    settings = get_settings()
    try:
        _TUTOR_RUNTIME.stop_quote_playback(session_id=session_id)
        session = update_practice_session_quote(
            session_id=session_id,
            quote_id=payload.quote_id,
            quote_text=payload.quote_text,
        )
        resolved_quote_text = _resolve_quote_text_for_session(session)
        _TUTOR_RUNTIME.update_session_quote_context(
            session_id=session.session_id,
            quote_id=session.quote_id,
            quote_text=resolved_quote_text,
        )
        _sync_tutor_status(session_id)
    except SessionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": str(exc),
            },
        ) from exc
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": str(exc),
            },
        ) from exc

    tutor_playback_identity: Optional[str] = None
    try:
        tutor_playback_identity = _TUTOR_RUNTIME.playback_identity_for_session(
            session_id=session.session_id,
            settings=settings,
        )
    except RuntimeError:
        tutor_playback_identity = None

    return StartPracticeSessionResponse(
        session_id=session.session_id,
        quote_id=session.quote_id,
        livekit_room=session.livekit_room,
        tutor_identity=session.tutor_identity,
        tutor_status=session.tutor_status,
        tutor_playback_identity=tutor_playback_identity,
        latest_attempt_id=None,
        latest_result_state=None,
    )


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
    if _TUTOR_RUNTIME.context_for_session(session_id) is None:
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

    tutor_playback_identity: Optional[str] = None
    try:
        tutor_playback_identity = _TUTOR_RUNTIME.playback_identity_for_session(
            session_id=session_id,
            settings=settings,
        )
    except RuntimeError:
        tutor_playback_identity = None

    return TutorPlaybackCommandResponse(
        session_id=session_id,
        status="playing",
        message="Tutor playback requested.",
        tutor_playback_identity=tutor_playback_identity,
    )


@router.get(
    "/session/{session_id}/tutor/audio",
)
def get_tutor_quote_audio_artifact(session_id: str) -> Response:
    """Returns backend-generated tutor quote audio artifact for device cache reuse."""

    settings = get_settings()
    context = _TUTOR_RUNTIME.context_for_session(session_id)
    if context is None:
        recovery_error = _resync_tutor_runtime_session(session_id, settings)
        if recovery_error:
            logger.warning(
                "Tutor runtime session recovery failed before audio fetch for %s: %s",
                session_id,
                recovery_error,
            )
        context = _TUTOR_RUNTIME.context_for_session(session_id)
    if context is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "session_not_found",
                "message": f"Session not found: {session_id}",
            },
        )

    artifact = None
    first_runtime_error: Optional[RuntimeError] = None
    try:
        artifact = _TUTOR_RUNTIME.build_tutor_audio_artifact(
            session_id=session_id,
            settings=settings,
        )
    except RuntimeError as exc:
        first_runtime_error = exc
        logger.warning(
            "Tutor audio artifact build failed for %s (first attempt): %s",
            session_id,
            exc,
        )
        recovery_error = _resync_tutor_runtime_session(session_id, settings)
        if recovery_error:
            logger.warning(
                "Tutor runtime session recovery failed after audio build error for %s: %s",
                session_id,
                recovery_error,
            )
        try:
            artifact = _TUTOR_RUNTIME.build_tutor_audio_artifact(
                session_id=session_id,
                settings=settings,
            )
        except RuntimeError as retry_exc:
            message = f"{first_runtime_error}; recovery retry failed: {retry_exc}"
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "tutor_audio_unavailable",
                    "message": message,
                },
            ) from retry_exc
    except Exception as exc:  # noqa: BLE001 - runtime boundary
        logger.exception("Unexpected tutor audio artifact failure for session %s", session_id)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "tutor_audio_unavailable",
                "message": f"backend tutor audio unavailable: {exc}",
            },
        ) from exc

    if artifact is None:
        message = (
            "backend tutor audio unavailable: artifact generation returned no result"
            if first_runtime_error is None
            else str(first_runtime_error)
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "tutor_audio_unavailable",
                "message": message,
            },
        )

    headers = {
        "X-QuoteApp-Playback-Identity": artifact.playback_identity,
        "X-QuoteApp-Backend-Cache": "hit" if artifact.cache_hit else "miss",
        "X-QuoteApp-Word-Count": str(max(0, artifact.word_count)),
        "X-QuoteApp-Estimated-Duration-Sec": f"{max(0.0, artifact.estimated_duration_sec):.4f}",
        "X-QuoteApp-Rhythm-B64": base64.urlsafe_b64encode(
            json.dumps(
                artifact.rhythm_word_end_times,
                ensure_ascii=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).decode("ascii"),
        "Cache-Control": "private, max-age=86400",
    }
    return Response(
        content=artifact.wav_bytes,
        media_type="audio/wav",
        headers=headers,
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
