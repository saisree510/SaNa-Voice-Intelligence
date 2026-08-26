from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..db.session import get_db
from ..models.user import User
from ..schemas.chat import ChatMessageRequest, ChatMessageResponse
from ..services.ai_service import AIProvider, get_ai_provider
from ..services.chat_service import send_message
from .deps import get_current_user

router = APIRouter(prefix='/chat', tags=['chat'])


@router.post('/message', response_model=ChatMessageResponse)
async def chat_message(
    body: ChatMessageRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    ai_provider: AIProvider = Depends(get_ai_provider),
) -> ChatMessageResponse:
    conversation, reply = await send_message(
        db,
        user=user,
        conversation_id=body.conversation_id,
        mode=body.mode,
        message=body.message,
        ai_provider=ai_provider,
    )
    return ChatMessageResponse(conversation_id=conversation.id, mode=conversation.mode, response=reply)
