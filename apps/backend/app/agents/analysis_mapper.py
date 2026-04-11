"""Maps learner transcript evidence into app-facing review states."""

from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
import re
from typing import Optional

from app.agents.prompts import (
    build_info_feedback,
    build_perfect_feedback,
    build_unavailable_feedback,
)
from app.models.analysis_result import AnalysisState, TutorReviewResult
from app.models.marked_token import MarkedToken

_TOKEN_PATTERN = re.compile(r"[A-Za-z0-9]+(?:['’‘`][A-Za-z0-9]+)*")
_APOSTROPHE_PATTERN = re.compile(r"[’‘`]")
_MAX_MARKED_TOKENS = 8


@dataclass(frozen=True)
class TranscriptAnalysisInput:
    """Input required for quote-grounded transcript review."""

    quote_text: Optional[str]
    transcript_text: Optional[str]


@dataclass(frozen=True)
class _QuoteToken:
    text: str
    normalized: str


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


def map_transcript_to_review(payload: TranscriptAnalysisInput) -> TutorReviewResult:
    """Maps transcript-vs-quote evidence into one of info/perfect/unavailable."""

    quote_tokens = _normalized_quote_tokens(payload.quote_text)
    if not quote_tokens:
        return unavailable_result(reason="quote context was unavailable")

    transcript_tokens = _normalized_transcript_tokens(payload.transcript_text)
    if not transcript_tokens:
        return unavailable_result(reason="learner speech could not be transcribed")

    marked = _find_mismatched_quote_tokens(
        quote_tokens=quote_tokens,
        transcript_tokens=transcript_tokens,
    )
    if not marked:
        return TutorReviewResult(
            state=AnalysisState.perfect,
            feedback_text=build_perfect_feedback(),
        )

    return TutorReviewResult(
        state=AnalysisState.info,
        marked_tokens=marked,
        feedback_text=build_info_feedback(marked_words=[token.text for token in marked]),
    )


def _normalized_quote_tokens(quote_text: Optional[str]) -> list[_QuoteToken]:
    if not quote_text:
        return []

    return [
        _QuoteToken(text=token, normalized=_normalize_token(token))
        for token in _TOKEN_PATTERN.findall(quote_text)
        if token
    ]


def _normalized_transcript_tokens(transcript_text: Optional[str]) -> list[str]:
    if not transcript_text:
        return []

    return [
        _normalize_token(token)
        for token in _TOKEN_PATTERN.findall(transcript_text)
        if token
    ]


def _normalize_token(token: str) -> str:
    return _APOSTROPHE_PATTERN.sub("'", token).lower()


def _find_mismatched_quote_tokens(
    *,
    quote_tokens: list[_QuoteToken],
    transcript_tokens: list[str],
) -> list[MarkedToken]:
    if not quote_tokens or not transcript_tokens:
        return []

    matcher = SequenceMatcher(
        a=[token.normalized for token in quote_tokens],
        b=transcript_tokens,
        autojunk=False,
    )

    mismatch_indexes: list[int] = []
    for tag, quote_start, quote_end, _, _ in matcher.get_opcodes():
        if tag in {"replace", "delete"}:
            mismatch_indexes.extend(range(quote_start, quote_end))

    marked_tokens: list[MarkedToken] = []
    seen: set[str] = set()
    for index in mismatch_indexes:
        if index < 0 or index >= len(quote_tokens):
            continue

        quote_token = quote_tokens[index]
        if quote_token.normalized in seen:
            continue

        seen.add(quote_token.normalized)
        marked_tokens.append(
            MarkedToken(text=quote_token.text, normalized_text=quote_token.normalized)
        )
        if len(marked_tokens) >= _MAX_MARKED_TOKENS:
            break

    return marked_tokens
