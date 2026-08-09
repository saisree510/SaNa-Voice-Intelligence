from datetime import datetime

from pydantic import BaseModel


class MessageOut(BaseModel):
    id: str
    role: str
    content: str
    created_at: datetime

    model_config = {'from_attributes': True}


class ConversationSummary(BaseModel):
    """Used for the list endpoint — no messages, keeps the response small."""

    id: str
    mode: str
    title: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {'from_attributes': True}


class ConversationDetail(ConversationSummary):
    """Used for the single-conversation endpoint — includes full history."""

    messages: list[MessageOut]
