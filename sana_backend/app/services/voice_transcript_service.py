"""Persists voice-mode transcripts to the same Conversation/Message
tables text chat uses (see chat_service.py) — so a voice call shows up
in "Chats" exactly like a typed one, instead of only ever existing in
the app's local, single-slot, on-device cache.

Used by agent/voice_agent.py, which runs as its own long-running
process (not a FastAPI request) — every call here opens and closes its
own short-lived [SessionLocal], since there's no per-request session to
borrow the way FastAPI's `get_db` dependency provides one.
"""

import logging

from ..db.session import SessionLocal
from ..models.conversation import Conversation
from ..models.message import Message

logger = logging.getLogger('sana-backend')


class VoiceTranscriptRecorder:
    """One instance per voice call. [conversation_id] is normally
    already known — app/api/voice.py's /api/voice/token creates (or
    validates/reuses, for a resumed call) the Conversation row up front
    and hands its id down through job metadata — but stays supported as
    None (created lazily on the first turn instead) for resilience
    against an older client that doesn't send one yet.
    """

    def __init__(self, *, user_id: str, mode: str, conversation_id: str | None = None) -> None:
        self._user_id = user_id
        self._mode = mode
        self.conversation_id: str | None = conversation_id

    def record(self, *, role: str, text: str) -> None:
        if role not in ('user', 'assistant') or not text.strip():
            return
        db = SessionLocal()
        try:
            if self.conversation_id is None:
                conversation = Conversation(user_id=self._user_id, mode=self._mode)
                db.add(conversation)
                db.flush()  # assigns conversation.id without committing yet
                self.conversation_id = conversation.id
            else:
                conversation = db.get(Conversation, self.conversation_id)
                if conversation is None:
                    logger.warning(
                        'Voice transcript conversation %s vanished mid-call; dropping this turn.',
                        self.conversation_id,
                    )
                    return

            # Title from the user's own words, not SANA's opening line —
            # matches text chat, where the title is always the first
            # thing *the user* said (chat_service.py's send_message).
            if role == 'user' and not conversation.title:
                conversation.title = text[:60]

            db.add(Message(conversation_id=conversation.id, role=role, content=text))
            db.commit()
        except Exception:
            # A transcript-save failure shouldn't take the call down —
            # log it and keep talking; worst case that one turn is
            # missing from history.
            logger.exception('Failed to save a voice transcript turn.')
            db.rollback()
        finally:
            db.close()


def load_conversation_history(conversation_id: str) -> list[dict[str, str]]:
    """[{"role": ..., "content": ...}, ...], oldest first — same shape
    ai_service.py builds from text-chat history, so voice_agent.py can
    seed a resumed call's ChatContext the same way. Empty list (not an
    error) if the conversation has no messages yet or doesn't exist —
    callers treat that the same as "nothing to resume", falling back to
    a normal fresh-start greeting.
    """
    db = SessionLocal()
    try:
        conversation = db.get(Conversation, conversation_id)
        if conversation is None:
            return []
        return [{'role': m.role, 'content': m.content} for m in conversation.messages]
    finally:
        db.close()
