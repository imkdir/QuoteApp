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


@dataclass(frozen=True)
class _MismatchEvidence:
    marked_tokens: list[MarkedToken]
    mismatch_indexes: list[int]


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

    mismatch_evidence = _find_mismatch_evidence(
        quote_tokens=quote_tokens,
        transcript_tokens=transcript_tokens,
    )
    marked = mismatch_evidence.marked_tokens
    if not marked:
        return TutorReviewResult(
            state=AnalysisState.perfect,
            feedback_text=build_perfect_feedback(),
        )

    mismatch_pattern = _coarse_mismatch_pattern(
        mismatch_indexes=mismatch_evidence.mismatch_indexes,
        quote_token_count=len(quote_tokens),
    )
    confidence = _coarse_info_confidence(
        quote_token_count=len(quote_tokens),
        transcript_token_count=len(transcript_tokens),
        mismatch_indexes=mismatch_evidence.mismatch_indexes,
    )

    return TutorReviewResult(
        state=AnalysisState.info,
        marked_tokens=marked,
        feedback_text=build_info_feedback(
            quote_text=payload.quote_text,
            transcript_text=payload.transcript_text,
            marked_words=[token.text for token in marked],
            mismatch_pattern=mismatch_pattern,
            confidence=confidence,
        ),
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


def _find_mismatch_evidence(
    *,
    quote_tokens: list[_QuoteToken],
    transcript_tokens: list[str],
) -> _MismatchEvidence:
    if not quote_tokens or not transcript_tokens:
        return _MismatchEvidence(marked_tokens=[], mismatch_indexes=[])

    matcher = SequenceMatcher(
        a=[token.normalized for token in quote_tokens],
        b=transcript_tokens,
        autojunk=False,
    )

    mismatch_indexes: list[int] = []
    for tag, quote_start, quote_end, _, _ in matcher.get_opcodes():
        if tag in {"replace", "delete"}:
            mismatch_indexes.extend(range(quote_start, quote_end))

    mismatch_indexes = sorted(set(mismatch_indexes))
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

    return _MismatchEvidence(marked_tokens=marked_tokens, mismatch_indexes=mismatch_indexes)


def _coarse_mismatch_pattern(*, mismatch_indexes: list[int], quote_token_count: int) -> Optional[str]:
    if not mismatch_indexes or quote_token_count <= 0:
        return None

    mismatch_share = len(mismatch_indexes) / quote_token_count
    longest_run = _longest_contiguous_run(mismatch_indexes)

    if len(mismatch_indexes) == 1 and longest_run == 1:
        return "single-word slip"
    if len(mismatch_indexes) <= 3 and longest_run <= 2:
        return "short cluster mismatch"
    if mismatch_share >= 0.6:
        return "widespread mismatch"
    if longest_run >= 4 or mismatch_share >= 0.35:
        return "phrase-level drift"
    return "scattered slips"


def _coarse_info_confidence(
    *,
    quote_token_count: int,
    transcript_token_count: int,
    mismatch_indexes: list[int],
) -> float:
    if quote_token_count <= 0:
        return 0.3

    mismatch_share = len(mismatch_indexes) / quote_token_count
    length_delta = abs(quote_token_count - transcript_token_count) / max(quote_token_count, 1)

    confidence = 0.88 - (mismatch_share * 0.72) - (length_delta * 0.28)
    if quote_token_count < 5 or transcript_token_count < 5:
        confidence -= 0.08

    return max(0.3, min(0.9, confidence))


def _longest_contiguous_run(indexes: list[int]) -> int:
    if not indexes:
        return 0

    longest = 1
    current = 1
    for previous, current_index in zip(indexes, indexes[1:]):
        if current_index == previous + 1:
            current += 1
            longest = max(longest, current)
        else:
            current = 1

    return longest
