"""Learner-audio transcription helpers for review analysis."""

from __future__ import annotations

import base64
import json
import mimetypes
from typing import Optional
from urllib import error, request
from uuid import uuid4

from app.config import Settings

_SUPPORTED_REVIEW_STT_PROVIDERS = frozenset({"auto", "openai", "gemini", "none", "disabled"})
_DEFAULT_REVIEW_STT_OPENAI_MODEL = "gpt-4o-mini-transcribe"
_DEFAULT_REVIEW_STT_GEMINI_MODEL = "gemini-2.5-flash"
_NO_SPEECH_SENTINEL = "<NO_USABLE_SPEECH>"


class TranscriptionError(RuntimeError):
    """Raised when learner-audio transcription cannot be completed."""


def transcribe_learner_audio(
    *,
    audio_bytes: bytes,
    filename: str,
    quote_text: Optional[str],
    settings: Settings,
) -> str:
    """Transcribes learner audio using the configured backend STT provider."""

    if not audio_bytes:
        raise TranscriptionError("submitted recording was empty")

    provider = _resolve_review_stt_provider(settings=settings)
    if provider in {"none", "disabled"}:
        raise TranscriptionError("learner review transcription is disabled")

    if provider == "openai":
        return _transcribe_with_openai(
            audio_bytes=audio_bytes,
            filename=filename,
            quote_text=quote_text,
            settings=settings,
        )
    if provider == "gemini":
        return _transcribe_with_gemini(
            audio_bytes=audio_bytes,
            filename=filename,
            quote_text=quote_text,
            settings=settings,
        )

    raise TranscriptionError(f"unsupported learner review STT provider: {provider}")


def _resolve_review_stt_provider(*, settings: Settings) -> str:
    provider = settings.review_stt_provider_normalized
    if provider not in _SUPPORTED_REVIEW_STT_PROVIDERS:
        supported = ", ".join(sorted(_SUPPORTED_REVIEW_STT_PROVIDERS))
        raise TranscriptionError(
            f"unsupported learner review STT provider '{provider}'. Supported: {supported}"
        )

    if provider in {"none", "disabled"}:
        return provider

    if provider == "auto":
        if settings.openai_api_key:
            return "openai"
        if settings.gemini_api_key:
            return "gemini"
        raise TranscriptionError(
            "no STT credentials found: set OPENAI_API_KEY or GEMINI_API_KEY"
        )

    if provider == "openai" and not settings.openai_api_key:
        raise TranscriptionError("OPENAI_API_KEY is required when REVIEW_STT_PROVIDER=openai")
    if provider == "gemini" and not settings.gemini_api_key:
        raise TranscriptionError("GEMINI_API_KEY is required when REVIEW_STT_PROVIDER=gemini")

    return provider


def _transcribe_with_openai(
    *,
    audio_bytes: bytes,
    filename: str,
    quote_text: Optional[str],
    settings: Settings,
) -> str:
    model = (settings.review_stt_model or _DEFAULT_REVIEW_STT_OPENAI_MODEL).strip()
    if not model:
        raise TranscriptionError("review STT model is not configured")

    prompt = _build_transcription_prompt(quote_text=quote_text)
    fields = [
        ("model", model),
        ("response_format", "json"),
        ("prompt", prompt),
    ]
    files = [
        (
            "file",
            filename or "attempt.m4a",
            _guess_audio_mime_type(filename),
            audio_bytes,
        )
    ]
    body, content_type = _encode_multipart_formdata(fields=fields, files=files)

    endpoint = f"{settings.openai_base_url_normalized}/audio/transcriptions"
    http_request = request.Request(
        endpoint,
        data=body,
        headers={
            "Authorization": f"Bearer {settings.openai_api_key}",
            "Content-Type": content_type,
        },
        method="POST",
    )
    try:
        with request.urlopen(
            http_request,
            timeout=settings.review_stt_timeout_seconds_clamped,
        ) as response:
            response_bytes = response.read()
    except error.HTTPError as exc:
        response_bytes = exc.read()
        detail = response_bytes.decode("utf-8", errors="replace").strip()[:240]
        raise TranscriptionError(
            f"learner transcription request failed ({exc.code}): {detail or exc.reason}"
        ) from exc
    except Exception as exc:  # noqa: BLE001 - network boundary
        raise TranscriptionError(f"learner transcription request failed: {exc}") from exc

    if not response_bytes:
        raise TranscriptionError("learner transcription returned no payload")

    try:
        response_json = json.loads(response_bytes.decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 - defensive payload parse
        raise TranscriptionError("learner transcription returned non-JSON payload") from exc

    transcript_text = ""
    if isinstance(response_json, dict):
        value = response_json.get("text")
        if isinstance(value, str):
            transcript_text = value.strip()

    if not transcript_text:
        raise TranscriptionError("learner transcription returned empty text")
    if _contains_no_speech_sentinel(transcript_text):
        raise TranscriptionError("no usable speech detected")

    return transcript_text


def _transcribe_with_gemini(
    *,
    audio_bytes: bytes,
    filename: str,
    quote_text: Optional[str],
    settings: Settings,
) -> str:
    model = (settings.review_stt_model or _DEFAULT_REVIEW_STT_GEMINI_MODEL).strip()
    if not model:
        raise TranscriptionError("review STT model is not configured")
    if not settings.gemini_api_key:
        raise TranscriptionError("GEMINI_API_KEY is required for Gemini learner transcription")

    endpoint = f"{settings.gemini_base_url_normalized}/models/{model}:generateContent"
    mime_type = _guess_audio_mime_type(filename)
    prompt = _build_gemini_transcription_prompt(quote_text=quote_text)
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inlineData": {
                            "mimeType": mime_type,
                            "data": base64.b64encode(audio_bytes).decode("ascii"),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0,
        },
    }
    request_bytes = json.dumps(payload).encode("utf-8")
    http_request = request.Request(
        endpoint,
        data=request_bytes,
        headers={
            "x-goog-api-key": settings.gemini_api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with request.urlopen(
            http_request,
            timeout=settings.review_stt_timeout_seconds_clamped,
        ) as response:
            response_bytes = response.read()
    except error.HTTPError as exc:
        response_bytes = exc.read()
        detail = response_bytes.decode("utf-8", errors="replace").strip()[:240]
        raise TranscriptionError(
            f"gemini transcription request failed ({exc.code}): {detail or exc.reason}"
        ) from exc
    except Exception as exc:  # noqa: BLE001 - network boundary
        raise TranscriptionError(f"gemini transcription request failed: {exc}") from exc

    if not response_bytes:
        raise TranscriptionError("gemini transcription returned no payload")

    try:
        response_json = json.loads(response_bytes.decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 - defensive payload parse
        raise TranscriptionError("gemini transcription returned non-JSON payload") from exc

    transcript_text = _extract_text_from_gemini_response(response_json).strip()
    if not transcript_text:
        raise TranscriptionError("gemini transcription returned empty text")
    if _contains_no_speech_sentinel(transcript_text):
        raise TranscriptionError("no usable speech detected")
    return transcript_text


def _build_transcription_prompt(*, quote_text: Optional[str]) -> str:
    return (
        "Transcribe the learner speech exactly as spoken. "
        f"If there is no usable speech, return exactly {_NO_SPEECH_SENTINEL}. "
        "Do not infer words from context."
    )


def _build_gemini_transcription_prompt(*, quote_text: Optional[str]) -> str:
    return (
        "Transcribe the learner speech exactly as spoken. "
        "Return only plain transcript text with no commentary. "
        f"If there is no usable speech, return exactly {_NO_SPEECH_SENTINEL}. "
        "Do not infer words from context."
    )


def _extract_text_from_gemini_response(response_json: dict) -> str:
    candidates = response_json.get("candidates")
    if not isinstance(candidates, list):
        return ""

    text_parts: list[str] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        content = candidate.get("content")
        if not isinstance(content, dict):
            continue
        parts = content.get("parts")
        if not isinstance(parts, list):
            continue

        for part in parts:
            if isinstance(part, dict):
                text_value = part.get("text")
                if isinstance(text_value, str) and text_value.strip():
                    text_parts.append(text_value.strip())

        if text_parts:
            break

    return " ".join(text_parts).strip()


def _contains_no_speech_sentinel(transcript_text: str) -> bool:
    normalized = transcript_text.strip().upper()
    return normalized == _NO_SPEECH_SENTINEL


def _guess_audio_mime_type(filename: str) -> str:
    guessed, _ = mimetypes.guess_type(filename or "")
    return guessed or "application/octet-stream"


def _encode_multipart_formdata(
    *,
    fields: list[tuple[str, str]],
    files: list[tuple[str, str, str, bytes]],
) -> tuple[bytes, str]:
    boundary = f"quoteapp-{uuid4().hex}"
    boundary_bytes = boundary.encode("ascii")
    body = bytearray()

    for name, value in fields:
        body.extend(b"--" + boundary_bytes + b"\r\n")
        body.extend(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8")
        )
        body.extend(value.encode("utf-8"))
        body.extend(b"\r\n")

    for field_name, filename, content_type, content_bytes in files:
        body.extend(b"--" + boundary_bytes + b"\r\n")
        body.extend(
            (
                f'Content-Disposition: form-data; name="{field_name}"; '
                f'filename="{filename}"\r\n'
            ).encode("utf-8")
        )
        body.extend(f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"))
        body.extend(content_bytes)
        body.extend(b"\r\n")

    body.extend(b"--" + boundary_bytes + b"--\r\n")
    return bytes(body), f"multipart/form-data; boundary={boundary}"
