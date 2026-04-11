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
_MIN_TRANSCRIPT_TOKENS = 2
_MIN_GROUNDED_MATCHED_TOKENS = 1
_MIN_AUDIO_BYTES_FOR_RELIABLE_REVIEW = 6_000
_MAX_TINY_AUDIO_BYTES_FOR_LONG_CLAIM = 10_000
_SOFT_MATCH_MIN_LENGTH = 4
_SOFT_MATCH_MAX_LENGTH_DELTA = 2
_SOFT_MATCH_SHORT_THRESHOLD = 0.9
_SOFT_MATCH_LONG_THRESHOLD = 0.8


@dataclass(frozen=True)
class TranscriptAnalysisInput:
    """Input required for quote-grounded transcript review."""

    quote_text: Optional[str]
    transcript_text: Optional[str]
    recording_num_bytes: Optional[int] = None


@dataclass(frozen=True)
class _QuoteToken:
    text: str
    normalized: str


@dataclass(frozen=True)
class _MismatchEvidence:
    marked_tokens: list[MarkedToken]
    mismatch_indexes: list[int]
    matched_quote_indexes: list[int]


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
    if len(transcript_tokens) < _MIN_TRANSCRIPT_TOKENS:
        return unavailable_result(reason="no usable speech detected")
    if _is_implausible_for_audio_size(
        recording_num_bytes=payload.recording_num_bytes,
        quote_token_count=len(quote_tokens),
        transcript_token_count=len(transcript_tokens),
    ):
        return unavailable_result(
            reason="the attempt did not match enough of the quote for a reliable review"
        )

    mismatch_evidence = _find_mismatch_evidence(
        quote_tokens=quote_tokens,
        transcript_tokens=transcript_tokens,
    )
    if not _has_grounded_alignment(
        quote_token_count=len(quote_tokens),
        transcript_token_count=len(transcript_tokens),
        matched_quote_indexes=mismatch_evidence.matched_quote_indexes,
    ):
        return unavailable_result(
            reason="the attempt did not match enough of the quote for a reliable review"
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
        return _MismatchEvidence(
            marked_tokens=[],
            mismatch_indexes=[],
            matched_quote_indexes=[],
        )

    matcher = SequenceMatcher(
        a=[token.normalized for token in quote_tokens],
        b=transcript_tokens,
        autojunk=False,
    )

    mismatch_indexes: list[int] = []
    matched_quote_indexes: list[int] = []
    for tag, quote_start, quote_end, transcript_start, transcript_end in matcher.get_opcodes():
        if tag == "replace":
            replace_mismatches, replace_matches = _resolve_replace_span(
                quote_tokens=quote_tokens,
                transcript_tokens=transcript_tokens,
                quote_start=quote_start,
                quote_end=quote_end,
                transcript_start=transcript_start,
                transcript_end=transcript_end,
            )
            mismatch_indexes.extend(replace_mismatches)
            matched_quote_indexes.extend(replace_matches)
        elif tag == "delete":
            mismatch_indexes.extend(range(quote_start, quote_end))
        elif tag == "equal":
            matched_quote_indexes.extend(range(quote_start, quote_end))

    mismatch_indexes = sorted(set(mismatch_indexes))
    matched_quote_indexes = sorted(set(matched_quote_indexes))
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

    return _MismatchEvidence(
        marked_tokens=marked_tokens,
        mismatch_indexes=mismatch_indexes,
        matched_quote_indexes=matched_quote_indexes,
    )


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


def _has_grounded_alignment(
    *,
    quote_token_count: int,
    transcript_token_count: int,
    matched_quote_indexes: list[int],
) -> bool:
    if quote_token_count <= 0 or transcript_token_count <= 0:
        return False

    matched_count = len(matched_quote_indexes)
    if matched_count < _MIN_GROUNDED_MATCHED_TOKENS:
        return False

    quote_match_share = matched_count / quote_token_count
    transcript_to_quote_ratio = transcript_token_count / quote_token_count

    if matched_count == 1 and quote_token_count >= 8 and transcript_token_count <= 2:
        return False
    if quote_match_share < 0.08 and quote_token_count >= 12:
        return False
    if transcript_to_quote_ratio < 0.2 and matched_count <= 1:
        return False
    if transcript_to_quote_ratio > 3.0 and matched_count <= 1:
        return False

    return True


def _is_implausible_for_audio_size(
    *,
    recording_num_bytes: Optional[int],
    quote_token_count: int,
    transcript_token_count: int,
) -> bool:
    if recording_num_bytes is None:
        return False
    if recording_num_bytes < _MIN_AUDIO_BYTES_FOR_RELIABLE_REVIEW:
        return True
    if recording_num_bytes >= _MAX_TINY_AUDIO_BYTES_FOR_LONG_CLAIM:
        return False
    if quote_token_count <= 0:
        return transcript_token_count >= 6

    long_claim_threshold = max(6, int(quote_token_count * 0.8))
    return transcript_token_count >= long_claim_threshold


def _resolve_replace_span(
    *,
    quote_tokens: list[_QuoteToken],
    transcript_tokens: list[str],
    quote_start: int,
    quote_end: int,
    transcript_start: int,
    transcript_end: int,
) -> tuple[list[int], list[int]]:
    quote_indexes = list(range(quote_start, quote_end))
    transcript_indexes = list(range(transcript_start, transcript_end))
    if not quote_indexes:
        return ([], [])
    if not transcript_indexes:
        return (quote_indexes, [])

    matched_quote_indexes: list[int] = []
    used_transcript_indexes: set[int] = set()

    for quote_index in quote_indexes:
        quote_token = quote_tokens[quote_index].normalized
        best_transcript_index: Optional[int] = None
        best_similarity = 0.0

        for transcript_index in transcript_indexes:
            if transcript_index in used_transcript_indexes:
                continue

            transcript_token = transcript_tokens[transcript_index]
            similarity = _soft_token_similarity(quote_token, transcript_token)
            if similarity <= 0.0:
                continue

            if similarity > best_similarity:
                best_similarity = similarity
                best_transcript_index = transcript_index

        if best_transcript_index is not None:
            matched_quote_indexes.append(quote_index)
            used_transcript_indexes.add(best_transcript_index)

    matched_set = set(matched_quote_indexes)
    mismatch_indexes = [index for index in quote_indexes if index not in matched_set]
    return (mismatch_indexes, matched_quote_indexes)


def _soft_token_similarity(quote_token: str, transcript_token: str) -> float:
    if not quote_token or not transcript_token:
        return 0.0
    if quote_token == transcript_token:
        return 1.0
    if quote_token[0] != transcript_token[0]:
        return 0.0
    if min(len(quote_token), len(transcript_token)) < _SOFT_MATCH_MIN_LENGTH:
        return 0.0
    if abs(len(quote_token) - len(transcript_token)) > _SOFT_MATCH_MAX_LENGTH_DELTA:
        return 0.0

    similarity = SequenceMatcher(
        a=quote_token,
        b=transcript_token,
        autojunk=False,
    ).ratio()
    threshold = (
        _SOFT_MATCH_LONG_THRESHOLD
        if max(len(quote_token), len(transcript_token)) >= 8
        else _SOFT_MATCH_SHORT_THRESHOLD
    )
    if similarity < threshold:
        return 0.0
    return similarity
