from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..db.session import get_db
from ..models.conversation import Conversation
from ..models.user import User
from ..schemas.conversation import ConversationDetail, ConversationSummary
from .deps import get_current_user

router = APIRouter(prefix='/conversations', tags=['conversations'])


def _get_owned_conversation(db: Session, conversation_id: str, user: User) -> Conversation:
    conversation = db.get(Conversation, conversation_id)
    if conversation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Conversation not found.')
    if conversation.user_id != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail='You do not have access to this conversation.'
        )
    return conversation


@router.get('', response_model=list[ConversationSummary])
def list_conversations(
    db: Session = Depends(get_db), user: User = Depends(get_current_user)
) -> list[Conversation]:
    return (
        db.query(Conversation)
        .filter(Conversation.user_id == user.id)
        .order_by(Conversation.updated_at.desc())
        .all()
    )


@router.get('/{conversation_id}', response_model=ConversationDetail)
def get_conversation(
    conversation_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)
) -> Conversation:
    return _get_owned_conversation(db, conversation_id, user)


@router.delete('/{conversation_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(
    conversation_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)
) -> None:
    conversation = _get_owned_conversation(db, conversation_id, user)
    db.delete(conversation)
    db.commit()
