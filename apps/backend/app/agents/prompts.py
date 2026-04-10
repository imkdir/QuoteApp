"""Prompt helpers for the QuoteApp speaking tutor agent."""

from __future__ import annotations


def build_tutor_quote_script(*, quote_text: str) -> str:
    """Returns the short script the tutor should speak in the LiveKit room."""

    normalized_quote = quote_text.strip()
    if not normalized_quote:
        return "Let's practice speaking. I cannot read a quote right now."

    return (
        "Let's practice this quote. Listen once, then repeat it clearly.\n"
        f"{normalized_quote}"
    )


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
