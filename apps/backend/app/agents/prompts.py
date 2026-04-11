"""Prompt helpers for the QuoteApp speaking tutor agent."""

from __future__ import annotations

import re
from typing import Optional

_MARKDOWN_FENCE_PATTERN = re.compile(r"^\s*```")
_MARKDOWN_BLOCKQUOTE_PATTERN = re.compile(r"^\s*>\s?")
_ZERO_WIDTH_CHARS = str.maketrans("", "", "\ufeff\u200b\u200c\u200d")
_TOKEN_PATTERN = re.compile(r"[A-Za-z0-9]+(?:['’‘`][A-Za-z0-9]+)*")
_MAX_INFO_FEEDBACK_WORDS = 140


def build_tutor_quote_script(*, quote_text: str) -> str:
    """Returns quote-only playback text prepared for natural prose-style reading.

    Product rule: tutor playback must contain only the quote text itself.
    """

    return _prepare_quote_text_for_speech(quote_text)


def build_tutor_reading_instruction() -> str:
    """Returns backend-controlled guidance for restrained quote reading style."""

    return (
        "Speak only the exact quote text. Do not add preambles, instructions, or commentary. "
        "Keep pacing natural and restrained, guided by punctuation and line breaks."
    )


def _prepare_quote_text_for_speech(quote_text: str) -> str:
    """Normalizes transport artifacts while keeping quote wording faithful."""

    normalized_newlines = quote_text.replace("\r\n", "\n").replace("\r", "\n")
    stripped_zero_width = normalized_newlines.translate(_ZERO_WIDTH_CHARS)
    cleaned = _strip_wrapping_markdown_blocks(stripped_zero_width)
    lines = cleaned.split("\n")

    if _all_non_empty_lines_are_blockquotes(lines):
        lines = [
            _MARKDOWN_BLOCKQUOTE_PATTERN.sub("", line, count=1) if line.strip() else line
            for line in lines
        ]

    collapsed_lines = [" ".join(line.replace("\u00a0", " ").split()) for line in lines]

    while collapsed_lines and not collapsed_lines[0]:
        collapsed_lines.pop(0)
    while collapsed_lines and not collapsed_lines[-1]:
        collapsed_lines.pop()

    if not collapsed_lines:
        return ""

    normalized_lines: list[str] = []
    previous_blank = False
    for line in collapsed_lines:
        if not line:
            if previous_blank:
                continue
            previous_blank = True
            normalized_lines.append("")
            continue

        previous_blank = False
        normalized_lines.append(line)

    return "\n".join(normalized_lines)


def _strip_wrapping_markdown_blocks(text: str) -> str:
    """Removes obvious wrapper-only markdown fences around the quote payload."""

    lines = text.split("\n")
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()

    if (
        len(lines) >= 2
        and _MARKDOWN_FENCE_PATTERN.match(lines[0])
        and _MARKDOWN_FENCE_PATTERN.match(lines[-1])
    ):
        return "\n".join(lines[1:-1])

    return "\n".join(lines)


def _all_non_empty_lines_are_blockquotes(lines: list[str]) -> bool:
    """Returns true when every non-empty line is prefixed as a markdown blockquote."""

    non_empty = [line for line in lines if line.strip()]
    if not non_empty:
        return False
    return all(_MARKDOWN_BLOCKQUOTE_PATTERN.match(line) for line in non_empty)


def build_info_feedback(
    *,
    quote_text: Optional[str] = None,
    transcript_text: Optional[str] = None,
    marked_words: list[str],
    mismatch_pattern: Optional[str] = None,
    confidence: Optional[float] = None,
) -> str:
    """Returns grounded, concise tutor feedback for info results."""

    focus_words = _dedup_words(marked_words, limit=2)
    focus_phrase = _focus_phrase(focus_words)
    quote_token_count = _count_tokens(quote_text)
    transcript_token_count = _count_tokens(transcript_text)
    approx_feedback = confidence is not None and confidence < 0.45

    if approx_feedback:
        opening = "Some parts did not align cleanly with the quote, so this is an approximate pass."
    elif mismatch_pattern == "single-word slip" and focus_phrase:
        opening = f"Your attempt was mostly clear, with one likely slip around {focus_phrase}."
    elif mismatch_pattern == "short cluster mismatch" and focus_phrase:
        opening = f"Your attempt was mostly steady, but the section around {focus_phrase} did not match the quote clearly."
    elif mismatch_pattern == "phrase-level drift":
        opening = "A full phrase drifted away from the quote in this attempt."
    elif mismatch_pattern == "widespread mismatch":
        opening = "Several words did not align clearly with the quote."
    elif focus_phrase:
        opening = f"Good effort, but the wording around {focus_phrase} needs another pass."
    else:
        opening = "Good effort, but a few words were unclear."

    suggestion = _next_attempt_suggestion(
        quote_text=quote_text or "",
        quote_token_count=quote_token_count,
        transcript_token_count=transcript_token_count,
        mismatch_pattern=mismatch_pattern,
    )
    feedback = f"{opening} On your next attempt, {suggestion}."
    return _truncate_to_word_limit(feedback, max_words=_MAX_INFO_FEEDBACK_WORDS)


def build_perfect_feedback() -> str:
    """Returns concise positive feedback for perfect results."""

    return "Nice work. This attempt stayed close to the quote text."


def build_unavailable_feedback(*, reason: str) -> str:
    """Returns concise unavailability feedback for app-facing responses."""

    clean_reason = reason.strip() or "review could not be completed"
    return f"Review unavailable: {clean_reason}."


def _dedup_words(words: list[str], *, limit: int) -> list[str]:
    selected: list[str] = []
    seen: set[str] = set()
    for word in words:
        cleaned = word.strip()
        if not cleaned:
            continue

        key = cleaned.lower()
        if key in seen:
            continue

        seen.add(key)
        selected.append(cleaned)
        if len(selected) >= limit:
            break

    return selected


def _focus_phrase(words: list[str]) -> str:
    if not words:
        return ""
    if len(words) == 1:
        return f"'{words[0]}'"
    return f"'{words[0]}' and '{words[1]}'"


def _count_tokens(text: Optional[str]) -> int:
    if not text:
        return 0
    return len(_TOKEN_PATTERN.findall(text))


def _next_attempt_suggestion(
    *,
    quote_text: str,
    quote_token_count: int,
    transcript_token_count: int,
    mismatch_pattern: Optional[str],
) -> str:
    if quote_token_count and transcript_token_count:
        ratio = transcript_token_count / quote_token_count
        if ratio < 0.75:
            return "slow slightly and include each small connecting word from the quote"
        if ratio > 1.25:
            return "stay closer to the exact quote wording and avoid adding filler words"

    if mismatch_pattern in {"phrase-level drift", "widespread mismatch"}:
        if _has_phrase_break_punctuation(quote_text):
            return "read one phrase at a time and pause briefly at punctuation before continuing"
        return "read one short phrase at a time, then pause briefly before the next phrase"

    return "keep a steady pace and stay close to the quote wording from start to finish"


def _has_phrase_break_punctuation(text: str) -> bool:
    return any(mark in text for mark in ",;:.!?")


def _truncate_to_word_limit(text: str, *, max_words: int) -> str:
    words = text.split()
    if len(words) <= max_words:
        return text
    return " ".join(words[:max_words]).rstrip(".,;:!?") + "."
