"""Prompt helpers for the QuoteApp speaking tutor agent."""

from __future__ import annotations

import re

_MARKDOWN_FENCE_PATTERN = re.compile(r"^\s*```")
_MARKDOWN_BLOCKQUOTE_PATTERN = re.compile(r"^\s*>\s?")
_ZERO_WIDTH_CHARS = str.maketrans("", "", "\ufeff\u200b\u200c\u200d")


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


def build_info_feedback(*, marked_words: list[str]) -> str:
    """Returns concise corrective feedback for info results."""

    if not marked_words:
        return "Good attempt. Try again with clearer pronunciation."

    focus = ", ".join(marked_words[:2])
    return f"Good attempt. Focus on: {focus}."


def build_perfect_feedback() -> str:
    """Returns concise positive feedback for perfect results."""

    return "Nice work. Your pacing and clarity were strong."


def build_unavailable_feedback(*, reason: str) -> str:
    """Returns concise unavailability feedback for app-facing responses."""

    clean_reason = reason.strip() or "review could not be completed"
    return f"Review unavailable: {clean_reason}."
