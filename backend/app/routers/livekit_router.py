import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from livekit import api

from app.config import settings
from app.auth.auth_bearer import AuthenticatedUser, get_current_user

logger = logging.getLogger("backend.livekit")
router = APIRouter(prefix="/v1/livekit", tags=["LiveKit"])


class TokenRequest(BaseModel):
    room_name: Optional[str] = None
    mode: Optional[str] = "general"


class TokenResponse(BaseModel):
    token: str
    url: str
    room_name: str
    participant_identity: str
    mode: str


@router.post("/token", response_model=TokenResponse)
async def create_livekit_token(
    request: TokenRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Mints a short-lived, user-scoped LiveKit access token for real-time voice sessions.
    """
    try:
        room_name = request.room_name or f"sbx-{current_user.id[:8]}-{request.mode}"
        participant_identity = f"user-{current_user.id}"

        # Initialize AccessToken with server credentials
        grant = api.VideoGrants(
            room_join=True,
            room=room_name,
            can_publish=True,
            can_subscribe=True,
            can_publish_data=True,
        )

        token_builder = api.AccessToken(
            api_key=settings.LIVEKIT_API_KEY,
            api_secret=settings.LIVEKIT_API_SECRET,
        )
        token_builder.with_identity(participant_identity)
        token_builder.with_name(current_user.metadata.get("full_name", participant_identity))
        token_builder.with_grants(grant)

        # Embed mode metadata in token
        token_builder.with_metadata(f'{{"mode":"{request.mode}","user_id":"{current_user.id}"}}')

        token = token_builder.to_jwt()
        logger.info(f"Minted LiveKit token for user {current_user.id} in room {room_name} (mode: {request.mode})")

        return TokenResponse(
            token=token,
            url=settings.LIVEKIT_URL,
            room_name=room_name,
            participant_identity=participant_identity,
            mode=request.mode or "general",
        )

    except Exception as e:
        logger.error(f"Failed to generate LiveKit token: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Token generation failed: {str(e)}",
        )
