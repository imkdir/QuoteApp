"""Practice session request/response and in-memory session models for MVP."""

from datetime import datetime, timezone
from typing import Optional

from app.models.analysis_result import AnalysisState, TutorReviewResult
from pydantic import BaseModel, Field


class PracticeAttempt(BaseModel):
    """A learner attempt with recording reference and optional review."""

    attempt_id: str
    recording_reference: str
    review_result: Optional[TutorReviewResult] = None
    is_superseded: bool = False
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PracticeSession(BaseModel):
    """In-memory practice session with attempt history for one quote."""

    session_id: str
    quote_id: str
    quote_text: Optional[str] = None
    livekit_room: str
    tutor_identity: str
    tutor_status: str = "pending"
    tutor_status_message: Optional[str] = None
    attempts: list[PracticeAttempt] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class StartPracticeSessionRequest(BaseModel):
    """Minimal payload required to open a new practice session."""

    quote_id: str = Field(min_length=1, max_length=128)
    quote_text: Optional[str] = Field(default=None, min_length=1, max_length=2000)
    mock_result: Optional[AnalysisState] = None


class StartPracticeSessionResponse(BaseModel):
    """Session start response used by iOS before full LiveKit wiring."""

    session_id: str
    quote_id: str
    livekit_room: Optional[str] = None
    tutor_identity: Optional[str] = None
    tutor_status: Optional[str] = None
    tutor_playback_identity: Optional[str] = None
    latest_attempt_id: Optional[str] = None
    latest_result_state: Optional[AnalysisState] = None


class SubmitPracticeAttemptResponse(BaseModel):
    """Submission response returned when learner audio becomes a new attempt."""

    session_id: str
    quote_id: str
    attempt_id: str
    recording_reference: str
    state: AnalysisState


class TutorPlaybackCommandResponse(BaseModel):
    """Playback command acknowledgement for tutor audio control."""

    session_id: str
    status: str
    message: Optional[str] = None
    tutor_playback_identity: Optional[str] = None
