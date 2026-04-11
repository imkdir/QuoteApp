"""LiveKit speaking tutor agent runtime for QuoteApp."""

from __future__ import annotations

import argparse
import asyncio
import inspect
import json
import logging
import os
import shutil
import subprocess
import tempfile
import audioop
import wave
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from threading import Event, Lock
from time import sleep
from typing import Literal

from app.agents.prompts import build_tutor_quote_script
from app.config import Settings, get_settings
from app.services.livekit_service import (
    LiveKitConfigError,
    LiveKitTokenNotReadyError,
    create_room_token,
)

TutorStatus = Literal["pending", "reading", "ready", "failed"]

logger = logging.getLogger(__name__)


@dataclass
class TutorSessionContext:
    """Inspectable per-session tutor context tracked by the backend runtime."""

    session_id: str
    room_name: str
    quote_text: str
    tutor_identity: str
    status: TutorStatus = "pending"
    status_message: str = "Tutor is pending startup."
    latest_attempt_id: str | None = None
    latest_review_state: str | None = None


class SpeakingTutorAgentRuntime:
    """Small background runtime that starts one tutor task per practice session."""

    def __init__(self) -> None:
        self._contexts: dict[str, TutorSessionContext] = {}
        self._playback_stop_events: dict[str, Event] = {}
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

            context = TutorSessionContext(
                session_id=session_id,
                room_name=room_name,
                quote_text=quote_text,
                tutor_identity=f"tutor-{session_id[:8]}",
                status="ready",
                status_message="Tutor is ready for playback.",
            )
            self._contexts[session_id] = context
            self._playback_stop_events[session_id] = Event()
        return context

    def request_quote_playback(self, *, session_id: str, settings: Settings) -> TutorSessionContext:
        """Starts tutor playback for the session quote as backend-published audio."""

        context = self.context_for_session(session_id)
        if context is None:
            raise RuntimeError(f"tutor session context is missing: {session_id}")

        with self._lock:
            stop_event = self._playback_stop_events.setdefault(session_id, Event())
            stop_event.clear()

        self._executor.submit(self._run_tutor_job, session_id, settings)
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

    def _run_tutor_job(self, session_id: str, settings: Settings) -> None:
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
            self._connect_and_read_quote(context=context, settings=settings, stop_event=stop_event)
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
    ) -> None:
        token_result = create_room_token(
            settings=settings,
            identity=context.tutor_identity,
            room=context.room_name,
            name="QuoteApp Tutor",
        )

        quote_script = build_tutor_quote_script(quote_text=context.quote_text)
        asyncio.run(
            _publish_quote_audio_to_livekit_room(
                url=token_result.url,
                token=token_result.token,
                session_id=context.session_id,
                quote_script=quote_script,
                stop_event=stop_event,
            )
        )


async def _publish_quote_audio_to_livekit_room(
    *,
    url: str,
    token: str,
    session_id: str,
    quote_script: str,
    stop_event: Event,
) -> None:
    """Connects to LiveKit and publishes tutor audio, with optional companion metadata."""

    try:
        from livekit import rtc  # type: ignore[import-not-found]
    except Exception as exc:  # noqa: BLE001 - package may be absent in local env
        raise RuntimeError(
            "livekit.rtc is unavailable; install LiveKit RTC runtime to enable tutor playback"
        ) from exc

    audio_bytes, sample_rate, num_channels = _synthesize_quote_audio(quote_script)
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
        await _publish_tutor_script_metadata(
            publish_data=publish_data,
            quote_script=quote_script,
        )

        await _publish_playback_event(
            publish_data=publish_data,
            session_id=session_id,
            event="started",
            word_count=word_count,
            estimated_duration_sec=estimated_duration_sec,
        )

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
            )
        else:
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


def _synthesize_quote_audio(quote_script: str) -> tuple[bytes, int, int]:
    say_bin = shutil.which("say")
    if say_bin is None:
        raise RuntimeError("No backend TTS engine is available to produce tutor audio.")
    afconvert_bin = shutil.which("afconvert")
    if afconvert_bin is None:
        raise RuntimeError("afconvert is required to normalize tutor audio output.")

    with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as tmp_source:
        source_path = Path(tmp_source.name)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_output:
        output_path = Path(tmp_output.name)

    try:
        synth_completed = subprocess.run(
            [
                say_bin,
                "-v",
                "Samantha",
                "-o",
                str(source_path),
                quote_script,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if synth_completed.returncode != 0:
            stderr = (
                synth_completed.stderr.strip()
                if synth_completed.stderr
                else "unknown error"
            )
            raise RuntimeError(f"backend TTS synthesis failed: {stderr}")

        convert_completed = subprocess.run(
            [
                afconvert_bin,
                "-f",
                "WAVE",
                "-d",
                "LEI16@48000",
                "-c",
                "1",
                str(source_path),
                str(output_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if convert_completed.returncode != 0:
            stderr = (
                convert_completed.stderr.strip()
                if convert_completed.stderr
                else "unknown error"
            )
            raise RuntimeError(f"backend audio conversion failed: {stderr}")

        with wave.open(str(output_path), "rb") as wav_file:
            num_channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            sample_rate = wav_file.getframerate()
            frame_count = wav_file.getnframes()
            pcm = wav_file.readframes(frame_count)

        if sample_width != 2:
            pcm = audioop.lin2lin(pcm, sample_width, 2)
            sample_width = 2

        if num_channels > 1:
            pcm = audioop.tomono(pcm, sample_width, 0.5, 0.5)
            num_channels = 1

        target_sample_rate = 48_000
        if sample_rate != target_sample_rate:
            pcm, _ = audioop.ratecv(
                pcm,
                sample_width,
                num_channels,
                sample_rate,
                target_sample_rate,
                None,
            )
            sample_rate = target_sample_rate

        if not pcm:
            raise RuntimeError("backend TTS synthesis returned empty audio data")

        return pcm, sample_rate, num_channels
    finally:
        try:
            os.remove(source_path)
        except OSError:
            pass
        try:
            os.remove(output_path)
        except OSError:
            pass


async def _publish_playback_event(
    *,
    publish_data,
    session_id: str,
    event: str,
    word_count: int,
    estimated_duration_sec: float,
) -> None:
    if publish_data is None:
        return

    payload = json.dumps(
        {
            "session_id": session_id,
            "event": event,
            "word_count": max(0, word_count),
            "estimated_duration_sec": max(0.0, estimated_duration_sec),
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
