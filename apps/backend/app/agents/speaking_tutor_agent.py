"""LiveKit speaking tutor agent runtime for QuoteApp."""

from __future__ import annotations

import argparse
import asyncio
import audioop
import base64
import io
import inspect
import json
import logging
import wave
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from threading import Event, Lock
from time import sleep
from typing import Literal

from app.agents.prompts import build_tutor_quote_script, build_tutor_reading_instruction
from app.config import Settings, get_settings
from app.services.livekit_service import (
    LiveKitConfigError,
    LiveKitTokenNotReadyError,
    create_room_token,
)

TutorStatus = Literal["pending", "reading", "ready", "failed"]

logger = logging.getLogger(__name__)
_SUPPORTED_TTS_PROVIDERS = frozenset({"auto", "openai", "gemini"})
_TARGET_LIVEKIT_SAMPLE_RATE = 48_000


@dataclass(frozen=True)
class TutorTTSProfile:
    """Resolved backend TTS configuration used for one playback session."""

    provider: str
    model: str
    voice: str
    speed: float
    timeout_seconds: float
    api_key: str
    base_url: str


@dataclass
class TutorSessionContext:
    """Inspectable per-session tutor context tracked by the backend runtime."""

    session_id: str
    room_name: str
    quote_text: str
    tutor_identity: str
    status: TutorStatus = "pending"
    status_message: str = "Tutor is pending startup."
    tts_voice_name: str | None = None
    latest_attempt_id: str | None = None
    latest_review_state: str | None = None


class SpeakingTutorAgentRuntime:
    """Small background runtime that starts one tutor task per practice session."""

    def __init__(self) -> None:
        self._contexts: dict[str, TutorSessionContext] = {}
        self._playback_stop_events: dict[str, Event] = {}
        self._tts_profiles: dict[str, TutorTTSProfile] = {}
        self._lock = Lock()
        self._executor = ThreadPoolExecutor(
            max_workers=2,
            thread_name_prefix="quoteapp-tutor-agent",
        )

    def ensure_session_tutor(
        self,
        *,
        session_id: str,
        room_name: str,
        quote_text: str,
        settings: Settings,
    ) -> TutorSessionContext:
        """Creates session context and starts tutor worker once per session."""

        with self._lock:
            existing = self._contexts.get(session_id)
            if existing is not None:
                return existing

            profile: TutorTTSProfile | None
            status: TutorStatus
            status_message: str
            try:
                profile = _resolve_tutor_tts_profile(settings=settings)
                status = "ready"
                status_message = (
                    "Tutor is ready for playback "
                    f"({profile.provider} {profile.model}, voice: {profile.voice})."
                )
            except RuntimeError as exc:
                profile = None
                status = "failed"
                status_message = f"backend tutor audio unavailable: {exc}"

            context = TutorSessionContext(
                session_id=session_id,
                room_name=room_name,
                quote_text=quote_text,
                tutor_identity=f"tutor-{session_id[:8]}",
                status=status,
                status_message=status_message,
                tts_voice_name=profile.voice if profile else None,
            )
            self._contexts[session_id] = context
            self._playback_stop_events[session_id] = Event()
            if profile is not None:
                self._tts_profiles[session_id] = profile
        return context

    def request_quote_playback(self, *, session_id: str, settings: Settings) -> TutorSessionContext:
        """Starts tutor playback for the session quote as backend-published audio."""

        context = self.context_for_session(session_id)
        if context is None:
            raise RuntimeError(f"tutor session context is missing: {session_id}")
        if context.status == "failed":
            raise RuntimeError(context.status_message)

        with self._lock:
            stop_event = self._playback_stop_events.setdefault(session_id, Event())
            stop_event.clear()
            profile = self._tts_profiles.get(session_id)

        if profile is None:
            profile = _resolve_tutor_tts_profile(settings=settings)
            with self._lock:
                self._tts_profiles[session_id] = profile
                stored_context = self._contexts.get(session_id)
                if stored_context is not None:
                    stored_context.tts_voice_name = profile.voice

        self._executor.submit(self._run_tutor_job, session_id, settings, profile)
        return context

    def stop_quote_playback(self, *, session_id: str) -> None:
        """Signals active tutor playback to stop for this session."""

        with self._lock:
            stop_event = self._playback_stop_events.get(session_id)
            if stop_event is None:
                return
            stop_event.set()

    def note_latest_attempt(
        self,
        *,
        session_id: str,
        attempt_id: str,
        review_state: str,
    ) -> None:
        """Updates inspectable context with latest attempt/review ownership."""

        with self._lock:
            context = self._contexts.get(session_id)
            if context is None:
                return
            context.latest_attempt_id = attempt_id
            context.latest_review_state = review_state

    def context_for_session(self, session_id: str) -> TutorSessionContext | None:
        """Returns a snapshot of tutor context for one session."""

        with self._lock:
            context = self._contexts.get(session_id)
            if context is None:
                return None
            return TutorSessionContext(**context.__dict__)

    def tutor_availability(self, session_id: str) -> tuple[bool, str | None]:
        """Reports whether the tutor path is available for review shaping."""

        with self._lock:
            context = self._contexts.get(session_id)
            if context is None:
                return False, "tutor session context is missing"

            if context.status == "failed":
                return False, context.status_message

            return True, None

    def _set_status(
        self,
        *,
        session_id: str,
        status: TutorStatus,
        message: str,
    ) -> None:
        with self._lock:
            context = self._contexts.get(session_id)
            if context is None:
                return
            context.status = status
            context.status_message = message

    def _run_tutor_job(
        self,
        session_id: str,
        settings: Settings,
        tts_profile: TutorTTSProfile,
    ) -> None:
        context = self.context_for_session(session_id)
        if context is None:
            return

        self._set_status(
            session_id=session_id,
            status="reading",
            message="Tutor is joining the LiveKit room and reading the quote.",
        )

        try:
            with self._lock:
                stop_event = self._playback_stop_events.setdefault(session_id, Event())
            self._connect_and_read_quote(
                context=context,
                settings=settings,
                stop_event=stop_event,
                tts_profile=tts_profile,
            )
            final_message = (
                "Tutor playback stopped."
                if stop_event.is_set()
                else "Tutor played quote audio in the room."
            )
            self._set_status(session_id=session_id, status="ready", message=final_message)
        except Exception as exc:  # noqa: BLE001 - defensive runtime boundary
            logger.exception("Tutor agent failed for session %s", session_id)
            self._set_status(
                session_id=session_id,
                status="failed",
                message=f"tutor agent failed: {exc}",
            )

    def _connect_and_read_quote(
        self,
        *,
        context: TutorSessionContext,
        settings: Settings,
        stop_event: Event,
        tts_profile: TutorTTSProfile,
    ) -> None:
        token_result = create_room_token(
            settings=settings,
            identity=context.tutor_identity,
            room=context.room_name,
            name="QuoteApp Tutor",
        )

        quote_script = build_tutor_quote_script(quote_text=context.quote_text)
        if not quote_script:
            raise RuntimeError("Selected quote text is empty; tutor playback requires quote text.")
        asyncio.run(
            _publish_quote_audio_to_livekit_room(
                url=token_result.url,
                token=token_result.token,
                session_id=context.session_id,
                quote_script=quote_script,
                tts_profile=tts_profile,
                stop_event=stop_event,
            )
        )


async def _publish_quote_audio_to_livekit_room(
    *,
    url: str,
    token: str,
    session_id: str,
    quote_script: str,
    tts_profile: TutorTTSProfile,
    stop_event: Event,
) -> None:
    """Connects to LiveKit and publishes tutor audio, with optional companion metadata."""

    try:
        from livekit import rtc  # type: ignore[import-not-found]
    except Exception as exc:  # noqa: BLE001 - package may be absent in local env
        raise RuntimeError(
            "livekit.rtc is unavailable; install LiveKit RTC runtime to enable tutor playback"
        ) from exc

    audio_bytes, sample_rate, num_channels = _synthesize_quote_audio(
        quote_script,
        tts_profile=tts_profile,
    )
    samples_per_channel = len(audio_bytes) // (2 * max(1, num_channels))
    word_count = max(1, len(quote_script.split()))
    estimated_duration_sec = (
        float(samples_per_channel) / float(sample_rate)
        if sample_rate > 0
        else max(0.2, word_count * 0.28)
    )

    room = rtc.Room()
    await room.connect(url, token)

    try:
        local_participant = getattr(room, "local_participant", None)
        publish_data = getattr(local_participant, "publish_data", None) if local_participant else None

        audio_source = rtc.AudioSource(sample_rate, num_channels)
        audio_track = rtc.LocalAudioTrack.create_audio_track("quoteapp-tutor-audio", audio_source)

        publish_track = getattr(local_participant, "publish_track", None)
        if publish_track is None:
            raise RuntimeError("LiveKit local participant does not support publish_track")

        track_publication = None
        maybe_publication = publish_track(audio_track)
        if inspect.isawaitable(maybe_publication):
            track_publication = await maybe_publication
        else:
            track_publication = maybe_publication

        frame_duration_ms = 20
        frame_samples_per_channel = max(1, int(sample_rate * (frame_duration_ms / 1000.0)))
        bytes_per_frame = frame_samples_per_channel * num_channels * 2
        silence_frame_data = b"\x00" * bytes_per_frame
        preroll_frames = 8
        tail_padding_frames = 5

        for _ in range(preroll_frames):
            await audio_source.capture_frame(
                rtc.AudioFrame(
                    data=silence_frame_data,
                    sample_rate=sample_rate,
                    num_channels=num_channels,
                    samples_per_channel=frame_samples_per_channel,
                )
            )

        await _publish_playback_event(
            publish_data=publish_data,
            session_id=session_id,
            event="started",
            word_count=word_count,
            estimated_duration_sec=estimated_duration_sec,
            voice_name=tts_profile.voice,
        )
        await _publish_tutor_script_metadata(
            publish_data=publish_data,
            quote_script=quote_script,
        )

        stopped_early = False
        for offset in range(0, len(audio_bytes), bytes_per_frame):
            if stop_event.is_set():
                stopped_early = True
                break

            chunk = audio_bytes[offset : offset + bytes_per_frame]
            if len(chunk) % (num_channels * 2) != 0:
                pad = (num_channels * 2) - (len(chunk) % (num_channels * 2))
                chunk += b"\x00" * pad

            chunk_samples_per_channel = len(chunk) // (2 * num_channels)
            frame = rtc.AudioFrame(
                data=chunk,
                sample_rate=sample_rate,
                num_channels=num_channels,
                samples_per_channel=chunk_samples_per_channel,
            )
            await audio_source.capture_frame(frame)

        if stopped_early:
            if hasattr(audio_source, "clear_queue"):
                audio_source.clear_queue()
            await _publish_playback_event(
                publish_data=publish_data,
                session_id=session_id,
                event="stopped",
                word_count=word_count,
                estimated_duration_sec=estimated_duration_sec,
                voice_name=tts_profile.voice,
            )
        else:
            for _ in range(tail_padding_frames):
                await audio_source.capture_frame(
                    rtc.AudioFrame(
                        data=silence_frame_data,
                        sample_rate=sample_rate,
                        num_channels=num_channels,
                        samples_per_channel=frame_samples_per_channel,
                    )
                )

            wait_for_playout = getattr(audio_source, "wait_for_playout", None)
            if wait_for_playout is not None:
                maybe_wait = wait_for_playout()
                if inspect.isawaitable(maybe_wait):
                    await maybe_wait

            await _publish_playback_event(
                publish_data=publish_data,
                session_id=session_id,
                event="finished",
                word_count=word_count,
                estimated_duration_sec=estimated_duration_sec,
                voice_name=tts_profile.voice,
            )

        if track_publication is not None:
            unpublish_track = getattr(local_participant, "unpublish_track", None)
            publication_sid = getattr(track_publication, "sid", None)
            if unpublish_track is not None and publication_sid:
                maybe_unpublish = unpublish_track(publication_sid)
                if inspect.isawaitable(maybe_unpublish):
                    await maybe_unpublish

        close_audio_source = getattr(audio_source, "aclose", None)
        if close_audio_source is not None:
            maybe_close = close_audio_source()
            if inspect.isawaitable(maybe_close):
                await maybe_close
    finally:
        maybe_disconnect = getattr(room, "disconnect", None)
        if maybe_disconnect is not None:
            result = maybe_disconnect()
            if inspect.isawaitable(result):
                await result


def _synthesize_quote_audio(
    quote_script: str,
    *,
    tts_profile: TutorTTSProfile,
    emit_style_log: bool = True,
) -> tuple[bytes, int, int]:
    if emit_style_log:
        logger.info(
            (
                "Tutor playback synthesis using backend %s model '%s' voice '%s' "
                "with quote-reader style: %s"
            ),
            tts_profile.provider,
            tts_profile.model,
            tts_profile.voice,
            build_tutor_reading_instruction(),
        )

    if tts_profile.provider == "openai":
        pcm, sample_rate, num_channels = _synthesize_quote_audio_with_openai(
            quote_script=quote_script,
            tts_profile=tts_profile,
        )
    elif tts_profile.provider == "gemini":
        pcm, sample_rate, num_channels = _synthesize_quote_audio_with_gemini(
            quote_script=quote_script,
            tts_profile=tts_profile,
        )
    else:
        raise RuntimeError(f"Unsupported tutor TTS provider: {tts_profile.provider}")

    sample_width = 2
    if num_channels > 1:
        pcm = audioop.tomono(pcm, sample_width, 0.5, 0.5)
        num_channels = 1

    if sample_rate != _TARGET_LIVEKIT_SAMPLE_RATE:
        pcm, _ = audioop.ratecv(
            pcm,
            sample_width,
            num_channels,
            sample_rate,
            _TARGET_LIVEKIT_SAMPLE_RATE,
            None,
        )
        sample_rate = _TARGET_LIVEKIT_SAMPLE_RATE

    pcm = _trim_silence_edges(
        pcm,
        sample_width=sample_width,
        num_channels=num_channels,
        sample_rate=sample_rate,
    )
    pcm = _apply_edge_fade(
        pcm,
        sample_width=sample_width,
        num_channels=num_channels,
        sample_rate=sample_rate,
    )

    if not pcm:
        raise RuntimeError("backend TTS synthesis returned empty audio data")

    return pcm, sample_rate, num_channels


def _resolve_tutor_tts_profile(*, settings: Settings) -> TutorTTSProfile:
    """Resolves backend TTS model/voice configuration for tutor playback."""

    provider = settings.tutor_tts_provider_normalized
    if provider not in _SUPPORTED_TTS_PROVIDERS:
        supported = ", ".join(sorted(_SUPPORTED_TTS_PROVIDERS))
        raise RuntimeError(f"Unsupported TTS provider '{provider}'. Supported: {supported}.")

    if provider == "auto":
        if settings.openai_api_key:
            provider = "openai"
        elif settings.gemini_api_key:
            provider = "gemini"
        else:
            raise RuntimeError(
                "No TTS credentials found. Set OPENAI_API_KEY or GEMINI_API_KEY, "
                "or configure TUTOR_TTS_PROVIDER explicitly."
            )

    if provider == "openai":
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is required when TUTOR_TTS_PROVIDER=openai.")
        model = (settings.tutor_tts_model or settings.tutor_tts_openai_model).strip()
        voice = (settings.tutor_tts_voice or settings.tutor_tts_openai_voice).strip()
        return TutorTTSProfile(
            provider=provider,
            model=model,
            voice=voice,
            speed=settings.tutor_tts_speed_clamped,
            timeout_seconds=settings.tutor_tts_timeout_seconds_clamped,
            api_key=settings.openai_api_key,
            base_url=settings.openai_base_url_normalized,
        )

    if provider == "gemini":
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY is required when TUTOR_TTS_PROVIDER=gemini.")
        model = (settings.tutor_tts_model or settings.tutor_tts_gemini_model).strip()
        voice = (settings.tutor_tts_voice or settings.tutor_tts_gemini_voice).strip()
        return TutorTTSProfile(
            provider=provider,
            model=model,
            voice=voice,
            speed=settings.tutor_tts_speed_clamped,
            timeout_seconds=settings.tutor_tts_timeout_seconds_clamped,
            api_key=settings.gemini_api_key,
            base_url=settings.gemini_base_url_normalized,
        )

    raise RuntimeError(f"Unsupported tutor TTS provider: {provider}")


def _synthesize_quote_audio_with_openai(
    *,
    quote_script: str,
    tts_profile: TutorTTSProfile,
) -> tuple[bytes, int, int]:
    """Generates tutor speech audio from OpenAI TTS as backend-owned inference."""

    endpoint = f"{tts_profile.base_url}/audio/speech"
    payload = {
        "model": tts_profile.model,
        "voice": tts_profile.voice,
        "input": quote_script,
        "response_format": "wav",
        "speed": tts_profile.speed,
        "instructions": build_tutor_reading_instruction(),
    }
    request_bytes = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=request_bytes,
        method="POST",
        headers={
            "Authorization": f"Bearer {tts_profile.api_key}",
            "Content-Type": "application/json",
            "Accept": "audio/wav",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=tts_profile.timeout_seconds) as response:
            content_type = response.headers.get("Content-Type", "")
            response_bytes = response.read()
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"OpenAI TTS request failed ({exc.code}): {_truncate_error_body(error_body)}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"OpenAI TTS network error: {exc.reason}") from exc

    if not response_bytes:
        raise RuntimeError("OpenAI TTS returned empty audio payload.")

    if "application/json" in content_type:
        error_json = response_bytes.decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI TTS returned JSON instead of audio: {_truncate_error_body(error_json)}")

    try:
        return _extract_pcm_from_wav(response_bytes)
    except RuntimeError as exc:
        raise RuntimeError(f"OpenAI TTS produced invalid wav audio: {exc}") from exc


def _synthesize_quote_audio_with_gemini(
    *,
    quote_script: str,
    tts_profile: TutorTTSProfile,
) -> tuple[bytes, int, int]:
    """Generates tutor speech audio from Gemini TTS as backend-owned inference."""

    endpoint = f"{tts_profile.base_url}/models/{tts_profile.model}:generateContent"
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        # Keep quote content exact; no preamble/instruction text in spoken payload.
                        "text": quote_script,
                    }
                ]
            }
        ],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": {
                        "voiceName": tts_profile.voice,
                    }
                }
            },
        },
    }
    request_bytes = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=request_bytes,
        method="POST",
        headers={
            "x-goog-api-key": tts_profile.api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=tts_profile.timeout_seconds) as response:
            response_bytes = response.read()
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Gemini TTS request failed ({exc.code}): {_truncate_error_body(error_body)}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Gemini TTS network error: {exc.reason}") from exc

    if not response_bytes:
        raise RuntimeError("Gemini TTS returned empty response payload.")

    try:
        response_json = json.loads(response_bytes.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("Gemini TTS response was not valid JSON.") from exc

    inline_data = _extract_inline_audio_data_from_gemini_response(response_json)
    try:
        audio_bytes = base64.b64decode(inline_data["data"], validate=True)
    except (ValueError, KeyError) as exc:
        raise RuntimeError("Gemini TTS audio payload was not valid base64 data.") from exc

    mime_type = str(inline_data.get("mimeType") or "").lower()
    if "wav" in mime_type:
        return _extract_pcm_from_wav(audio_bytes)

    # Gemini REST TTS commonly returns raw 16-bit PCM at 24kHz mono.
    if not audio_bytes:
        raise RuntimeError("Gemini TTS returned empty audio bytes.")
    return audio_bytes, 24_000, 1


def _extract_inline_audio_data_from_gemini_response(response_json: dict) -> dict:
    """Extracts `inlineData` audio block from Gemini generateContent JSON."""

    candidates = response_json.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise RuntimeError("Gemini TTS response had no candidates.")

    first_candidate = candidates[0]
    content = first_candidate.get("content") if isinstance(first_candidate, dict) else None
    parts = content.get("parts") if isinstance(content, dict) else None
    if not isinstance(parts, list):
        raise RuntimeError("Gemini TTS response did not contain content parts.")

    for part in parts:
        if not isinstance(part, dict):
            continue
        inline_data = part.get("inlineData")
        if isinstance(inline_data, dict) and inline_data.get("data"):
            return inline_data

    raise RuntimeError("Gemini TTS response did not contain inline audio data.")


def _extract_pcm_from_wav(wav_bytes: bytes) -> tuple[bytes, int, int]:
    """Extracts mono/stereo PCM from a wav payload."""

    with io.BytesIO(wav_bytes) as stream:
        with wave.open(stream, "rb") as wav_file:
            num_channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            sample_rate = wav_file.getframerate()
            frame_count = wav_file.getnframes()
            pcm = wav_file.readframes(frame_count)

    if not pcm:
        raise RuntimeError("wav payload has no audio frames")

    if sample_width != 2:
        pcm = audioop.lin2lin(pcm, sample_width, 2)

    return pcm, sample_rate, max(1, num_channels)


def _truncate_error_body(raw: str, limit: int = 220) -> str:
    clean = " ".join(raw.strip().split())
    if len(clean) <= limit:
        return clean
    return f"{clean[:limit]}..."


def _trim_silence_edges(
    pcm: bytes,
    *,
    sample_width: int,
    num_channels: int,
    sample_rate: int,
    window_ms: int = 10,
    max_trim_ms: int = 320,
    keep_ms: int = 36,
    silence_rms_threshold: int = 55,
) -> bytes:
    """Trims long synthesized silence at start/end while preserving soft boundaries."""

    if not pcm or sample_width <= 0 or num_channels <= 0 or sample_rate <= 0:
        return pcm

    frame_size = sample_width * num_channels
    total_frames = len(pcm) // frame_size
    if total_frames <= 0:
        return pcm

    window_frames = max(1, int(sample_rate * (window_ms / 1000.0)))
    keep_frames = max(0, int(sample_rate * (keep_ms / 1000.0)))
    max_trim_frames = max(0, int(sample_rate * (max_trim_ms / 1000.0)))

    def _window_is_silent(start_frame: int) -> bool:
        start_byte = start_frame * frame_size
        end_byte = min((start_frame + window_frames) * frame_size, len(pcm))
        window = pcm[start_byte:end_byte]
        if not window:
            return True
        return audioop.rms(window, sample_width) <= silence_rms_threshold

    leading_trim_frames = 0
    cursor = 0
    while cursor < total_frames and leading_trim_frames < max_trim_frames:
        if not _window_is_silent(cursor):
            break
        cursor += window_frames
        leading_trim_frames += window_frames

    trailing_trim_frames = 0
    cursor = max(0, total_frames - window_frames)
    while cursor >= 0 and trailing_trim_frames < max_trim_frames:
        if not _window_is_silent(cursor):
            break
        trailing_trim_frames += window_frames
        if cursor == 0:
            break
        cursor = max(0, cursor - window_frames)

    if leading_trim_frames <= keep_frames and trailing_trim_frames <= keep_frames:
        return pcm

    start_frame = max(0, leading_trim_frames - keep_frames)
    end_frame = total_frames - max(0, trailing_trim_frames - keep_frames)
    if end_frame <= start_frame:
        return pcm

    start_byte = start_frame * frame_size
    end_byte = min(len(pcm), end_frame * frame_size)
    trimmed = pcm[start_byte:end_byte]
    return trimmed or pcm


def _apply_edge_fade(
    pcm: bytes,
    *,
    sample_width: int,
    num_channels: int,
    sample_rate: int,
    fade_ms: int = 32,
) -> bytes:
    """Adds a short fade-in/out so quote boundaries sound less abrupt."""

    if not pcm or sample_width <= 0 or num_channels <= 0 or sample_rate <= 0:
        return pcm

    frame_size = sample_width * num_channels
    total_frames = len(pcm) // frame_size
    fade_frames = min(int(sample_rate * (fade_ms / 1000.0)), total_frames // 2)
    if fade_frames <= 1:
        return pcm

    shaped = bytearray(pcm)
    for frame_index in range(fade_frames):
        gain = float(frame_index + 1) / float(fade_frames)

        start = frame_index * frame_size
        end = start + frame_size
        shaped[start:end] = audioop.mul(bytes(shaped[start:end]), sample_width, gain)

        tail_start = (total_frames - frame_index - 1) * frame_size
        tail_end = tail_start + frame_size
        shaped[tail_start:tail_end] = audioop.mul(
            bytes(shaped[tail_start:tail_end]),
            sample_width,
            gain,
        )

    return bytes(shaped)


async def _publish_playback_event(
    *,
    publish_data,
    session_id: str,
    event: str,
    word_count: int,
    estimated_duration_sec: float,
    voice_name: str | None = None,
) -> None:
    if publish_data is None:
        return

    payload = json.dumps(
        {
            "session_id": session_id,
            "event": event,
            "word_count": max(0, word_count),
            "estimated_duration_sec": max(0.0, estimated_duration_sec),
            "voice_name": voice_name,
        }
    ).encode("utf-8")
    maybe_result = publish_data(
        payload,
        reliable=True,
        topic="quoteapp.tutor.playback",
    )
    try:
        if inspect.isawaitable(maybe_result):
            await maybe_result
    except Exception:  # noqa: BLE001 - metadata is optional companion output
        logger.debug("Failed to publish tutor playback metadata", exc_info=True)


async def _publish_tutor_script_metadata(
    *,
    publish_data,
    quote_script: str,
) -> None:
    """Publishes companion text metadata; tutor audio remains the primary playback source."""

    if publish_data is None:
        return

    try:
        maybe_result = publish_data(
            quote_script.encode("utf-8"),
            reliable=True,
            topic="quoteapp.tutor.quote_script",
        )
        if inspect.isawaitable(maybe_result):
            await maybe_result
    except Exception:  # noqa: BLE001 - metadata is optional companion output
        logger.debug("Failed to publish tutor script metadata", exc_info=True)


def run_session_tutor_process(
    *,
    session_id: str,
    room_name: str,
    quote_text: str,
) -> int:
    """CLI-friendly single-session agent runner."""

    settings = get_settings()
    runtime = SpeakingTutorAgentRuntime()
    runtime.ensure_session_tutor(
        session_id=session_id,
        room_name=room_name,
        quote_text=quote_text,
        settings=settings,
    )

    # Wait for one terminal state for process-mode operation.
    while True:
        context = runtime.context_for_session(session_id)
        if context is None:
            return 1
        if context.status in {"ready", "failed"}:
            return 0 if context.status == "ready" else 1
        sleep(0.1)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="QuoteApp speaking tutor agent process")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--room-name", required=True)
    parser.add_argument("--quote-text", required=True)
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()
    try:
        return run_session_tutor_process(
            session_id=args.session_id,
            room_name=args.room_name,
            quote_text=args.quote_text,
        )
    except (LiveKitConfigError, LiveKitTokenNotReadyError, RuntimeError) as exc:
        logger.error("Tutor process failed: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
