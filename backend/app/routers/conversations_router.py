import logging
from typing import List, Optional
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from supabase import create_client, Client

from app.config import settings
from app.auth.auth_bearer import AuthenticatedUser, get_current_user

logger = logging.getLogger("backend.conversations")
router = APIRouter(prefix="/v1/conversations", tags=["Conversations"])


class ConversationModel(BaseModel):
    id: str
    user_id: str
    title: str
    mode: str
    created_at: str
    updated_at: str
    preview_text: Optional[str] = None


class ModeUpdateRequest(BaseModel):
    mode: str


def get_supabase_client() -> Optional[Client]:
    if settings.SUPABASE_URL and (settings.SUPABASE_SERVICE_ROLE_KEY or settings.SUPABASE_ANON_KEY):
        key = settings.SUPABASE_SERVICE_ROLE_KEY or settings.SUPABASE_ANON_KEY
        return create_client(settings.SUPABASE_URL, key)
    return None


@router.get("", response_model=List[ConversationModel])
async def list_conversations(
    limit: int = 20,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Fetches past conversations for the authenticated user from Supabase PostgreSQL.
    """
    client = get_supabase_client()
    if not client:
        # Dev fallback when Supabase keys not set
        return []

    try:
        response = (
            client.table("conversations")
            .select("*")
            .eq("user_id", current_user.id)
            .order("updated_at", desc=True)
            .limit(limit)
            .execute()
        )
        items = response.data or []
        return [
            ConversationModel(
                id=item["id"],
                user_id=item["user_id"],
                title=item.get("title", "New Conversation"),
                mode=item.get("mode", "general"),
                created_at=str(item.get("created_at")),
                updated_at=str(item.get("updated_at")),
                preview_text=item.get("preview_text"),
            )
            for item in items
        ]
    except Exception as e:
        logger.error(f"Failed to list conversations: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database query failed: {str(e)}",
        )


@router.patch("/{conversation_id}/mode")
async def update_conversation_mode(
    conversation_id: str,
    request: ModeUpdateRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Updates the active conversation mode and logs a mode_changed event.
    """
    client = get_supabase_client()
    if not client:
        return {"status": "ok", "mode": request.mode}

    try:
        # Update conversations table
        client.table("conversations").update({
            "mode": request.mode,
            "updated_at": datetime.utcnow().isoformat(),
        }).eq("id", conversation_id).eq("user_id", current_user.id).execute()

        # Log conversation_events table
        client.table("conversation_events").insert({
            "conversation_id": conversation_id,
            "event_type": "mode_changed",
            "payload": {"mode": request.mode},
        }).execute()

        return {"status": "ok", "conversation_id": conversation_id, "mode": request.mode}
    except Exception as e:
        logger.error(f"Failed to update conversation mode: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update mode: {str(e)}",
        )
