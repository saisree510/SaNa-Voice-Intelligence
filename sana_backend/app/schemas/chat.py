from pydantic import BaseModel, Field, field_validator


class ChatMessageRequest(BaseModel):
    conversation_id: str | None = None
    mode: str
    message: str = Field(min_length=1, max_length=8000)

    @field_validator('message')
    @classmethod
    def message_must_not_be_blank(cls, value: str) -> str:
        # min_length=1 alone lets a single space through — this catches
        # "   " too, matching the spec's "empty message" error case.
        if not value.strip():
            raise ValueError('Message cannot be empty.')
        return value


class ChatMessageResponse(BaseModel):
    conversation_id: str
    mode: str
    response: str
