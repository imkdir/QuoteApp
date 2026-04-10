"""LiveKit speaking tutor agent runtime for QuoteApp."""

from __future__ import annotations

import argparse
import asyncio
import inspect
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from threading import Lock
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
            )
            self._contexts[session_id] = context

        self._executor.submit(self._run_tutor_job, session_id, settings)
        return context

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
            self._connect_and_read_quote(context=context, settings=settings)
            self._set_status(
                session_id=session_id,
                status="ready",
                message="Tutor read the quote in the room.",
            )
        except Exception as exc:  # noqa: BLE001 - defensive runtime boundary
            logger.exception("Tutor agent failed for session %s", session_id)
            self._set_status(
                session_id=session_id,
                status="failed",
                message=f"tutor agent failed: {exc}",
            )

    def _connect_and_read_quote(self, *, context: TutorSessionContext, settings: Settings) -> None:
        token_result = create_room_token(
            settings=settings,
            identity=context.tutor_identity,
            room=context.room_name,
            name="QuoteApp Tutor",
        )

        quote_script = build_tutor_quote_script(quote_text=context.quote_text)
        asyncio.run(
            _publish_script_to_livekit_room(
                url=token_result.url,
                token=token_result.token,
                quote_script=quote_script,
            )
        )


async def _publish_script_to_livekit_room(*, url: str, token: str, quote_script: str) -> None:
    """Connects to LiveKit and pushes tutor script into the room data channel."""

    try:
        from livekit import rtc  # type: ignore[import-not-found]
    except Exception as exc:  # noqa: BLE001 - package may be absent in local env
        raise RuntimeError(
            "livekit.rtc is unavailable; install LiveKit RTC runtime to enable tutor playback"
        ) from exc

    room = rtc.Room()
    await room.connect(url, token)

    try:
        local_participant = getattr(room, "local_participant", None)
        publish_data = getattr(local_participant, "publish_data", None) if local_participant else None

        if publish_data is None:
            raise RuntimeError("LiveKit local participant does not support publish_data")

        maybe_result = publish_data(
            quote_script.encode("utf-8"),
            reliable=True,
            topic="quoteapp.tutor.quote_script",
        )
        if inspect.isawaitable(maybe_result):
            await maybe_result

        # Keep the tutor connected briefly to model quote-read ownership in-room.
        word_count = max(1, len(quote_script.split()))
        await asyncio.sleep(min(8.0, 1.0 + (word_count * 0.12)))
    finally:
        maybe_disconnect = getattr(room, "disconnect", None)
        if maybe_disconnect is not None:
            result = maybe_disconnect()
            if inspect.isawaitable(result):
                await result


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
