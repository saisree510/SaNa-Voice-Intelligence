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
    server_url: str
    serverUrl: str
    participant_token: str
    participantToken: str
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
            can_update_own_metadata=True,
            can_manage_agent_session=True,
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

        # Explicitly dispatch a LiveKit agent worker into the room.
        # Railway / LiveKit config has used both voice_agent and voice_agent_local;
        # try the configured name first, then known fallbacks.
        lk_api = None
        try:
            lk_api = api.LiveKitAPI(
                url=settings.LIVEKIT_URL,
                api_key=settings.LIVEKIT_API_KEY,
                api_secret=settings.LIVEKIT_API_SECRET,
            )
            candidate_names = []
            for candidate in (
                settings.LIVEKIT_AGENT_NAME,
                "voice_agent",
                "voice_agent_local",
            ):
                candidate = (candidate or "").strip()
                if candidate and candidate not in candidate_names:
                    candidate_names.append(candidate)

            dispatched_name = None
            last_dispatch_err = None
            for candidate_name in candidate_names:
                try:
                    await lk_api.agent_dispatch.create_dispatch(
                        api.CreateAgentDispatchRequest(
                            room=room_name,
                            agent_name=candidate_name,
                        )
                    )
                    dispatched_name = candidate_name
                    logger.info(
                        f"Successfully dispatched agent '{candidate_name}' into room {room_name}"
                    )
                    break
                except Exception as dispatch_err:
                    last_dispatch_err = dispatch_err
                    logger.warning(
                        f"Agent dispatch attempt failed for '{candidate_name}' in room {room_name}: {dispatch_err}"
                    )

            if dispatched_name is None and last_dispatch_err is not None:
                logger.warning(
                    f"All agent dispatch attempts failed for room {room_name}: {last_dispatch_err}"
                )
        finally:
            if lk_api is not None:
                await lk_api.aclose()

        return TokenResponse(
            token=token,
            url=settings.LIVEKIT_URL,
            server_url=settings.LIVEKIT_URL,
            serverUrl=settings.LIVEKIT_URL,
            participant_token=token,
            participantToken=token,
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
