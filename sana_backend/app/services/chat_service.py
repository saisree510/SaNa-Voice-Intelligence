from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from ..models.conversation import Conversation
from ..models.message import Message
from ..models.user import User
from ..modes import VALID_MODES
from .ai_service import AIProvider, AIServiceError, AITimeoutError, AIUnexpectedResponseError


async def send_message(
    db: Session,
    *,
    user: User,
    conversation_id: str | None,
    mode: str,
    message: str,
    ai_provider: AIProvider,
) -> tuple[Conversation, str]:
    """Orchestrates one /chat/message request end to end (spec's 9 steps):
    validate mode -> get/create conversation -> load history -> call
    AIService -> persist both messages -> return. Auth (step 1) already
    happened via the get_current_user dependency before this runs.
    """
    if mode not in VALID_MODES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid mode '{mode}'. Must be one of: {', '.join(VALID_MODES)}.",
        )

    if conversation_id:
        conversation = db.get(Conversation, conversation_id)
        if conversation is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Conversation not found.')
        if conversation.user_id != user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail='You do not have access to this conversation.'
            )
        if conversation.mode != mode:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"This conversation is in '{conversation.mode}' mode, not '{mode}'.",
            )
    else:
        conversation = Conversation(user_id=user.id, mode=mode, title=message[:60])
        db.add(conversation)
        db.flush()  # assigns conversation.id without committing yet

    history = [{'role': m.role, 'content': m.content} for m in conversation.messages]

    try:
        reply_text = await ai_provider.generate_reply(
            mode=mode,
            history=history,
            user_message=message,
            conversation_id=conversation.id,
            user_name=user.name,
            user_id=user.id,
        )
    except AITimeoutError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT, detail='The AI took too long to respond. Please try again.'
        ) from e
    except AIUnexpectedResponseError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail='The AI returned an unexpected response. Please try again.',
        ) from e
    except AIServiceError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail='The AI service is currently unavailable.'
        ) from e

    db.add(Message(conversation_id=conversation.id, role='user', content=message))
    db.add(Message(conversation_id=conversation.id, role='assistant', content=reply_text))
    db.commit()
    db.refresh(conversation)

    return conversation, reply_text
