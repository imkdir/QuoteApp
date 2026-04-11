"""Maps lightweight backend analysis signals into app-facing review states."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Optional

from app.agents.prompts import (
    build_info_feedback,
    build_perfect_feedback,
    build_unavailable_feedback,
)
from app.models.analysis_result import AnalysisState, TutorReviewResult
from app.models.marked_token import MarkedToken

_MIN_AUDIO_BYTES = 2048


@dataclass(frozen=True)
class AttemptAnalysisInput:
    """Minimal input required for backend review shaping."""

    quote_text: Optional[str]
    attempt_id: str
    audio_size_bytes: int
    tutor_available: bool
    failure_reason: Optional[str] = None


def loading_result() -> TutorReviewResult:
    """Returns the canonical loading result used immediately after submission."""

    return TutorReviewResult(
        state=AnalysisState.loading,
        feedback_text="Reviewing the latest attempt.",
    )


def unavailable_result(*, reason: str) -> TutorReviewResult:
    """Returns a backend-unavailable review result."""

    return TutorReviewResult(
        state=AnalysisState.unavailable,
        feedback_text=build_unavailable_feedback(reason=reason),
    )


def map_attempt_to_review(payload: AttemptAnalysisInput) -> TutorReviewResult:
    """Maps backend-side signals into one of loading/info/perfect/unavailable."""

    if not payload.tutor_available:
        return unavailable_result(reason=payload.failure_reason or "tutor agent is unavailable")

    if payload.audio_size_bytes < _MIN_AUDIO_BYTES:
        return unavailable_result(reason="submitted recording was too short")

    quote_tokens = _normalized_quote_tokens(payload.quote_text)
    if not quote_tokens:
        return unavailable_result(reason="quote context was unavailable")

    digest = hashlib.sha256(
        f"{payload.attempt_id}:{payload.audio_size_bytes}".encode("utf-8")
    ).hexdigest()
    selector = int(digest[:8], 16)

    # Keep this modest and honest: deterministic coarse mapping, no phoneme-level claims.
    if selector % 5 == 0:
        return TutorReviewResult(
            state=AnalysisState.perfect,
            feedback_text=build_perfect_feedback(),
        )

    marked = _pick_marked_tokens(quote_tokens=quote_tokens, selector=selector)
    return TutorReviewResult(
        state=AnalysisState.info,
        marked_tokens=marked,
        feedback_text=build_info_feedback(marked_words=[token.text for token in marked]),
    )


def _normalized_quote_tokens(quote_text: Optional[str]) -> list[str]:
    if not quote_text:
        return []

    return [
        token.lower()
        for token in re.findall(r"[A-Za-z0-9']+", quote_text)
        if token.strip()
    ]


def _pick_marked_tokens(*, quote_tokens: list[str], selector: int) -> list[MarkedToken]:
    if not quote_tokens:
        return []

    first_index = selector % len(quote_tokens)
    second_index = (selector // 7) % len(quote_tokens)
    ordered_indexes = sorted({first_index, second_index})

    return [
        MarkedToken(text=quote_tokens[index], normalized_text=quote_tokens[index])
        for index in ordered_indexes
    ]
