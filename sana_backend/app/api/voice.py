import json
import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException, Response
from livekit.api import AccessToken, RoomAgentDispatch, RoomConfiguration, VideoGrants
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..db.session import get_db
from ..models.conversation import Conversation
from ..models.user import User
from ..modes import MODE_INSTRUCTIONS
from .deps import get_current_user

logger = logging.getLogger('sana-backend')

router = APIRouter(prefix='/api/voice', tags=['voice'])

# Must match the agent_name the worker registers with in agent/voice_agent.py.
AGENT_NAME = 'sana-agent'

# Same Cartesia voice the live voice-mode agent uses (agent/voice_agent.py)
# — one-off lines like the onboarding greeting should sound like the same
# SANA, not a second, different-sounding voice.
_TTS_MODEL = 'cartesia/sonic-3'
_TTS_VOICE = '9626c31c-bec5-4cca-baa8-f8ba9e84c8bc'


class TokenRequest(BaseModel):
    mode: str
    user_id: str
    user_name: str
    # Set to resume an existing voice conversation (e.g. the user just
    # stopped the mic and started it again a moment later) instead of
    # starting a fresh one — see voice_agent.py, which loads that
    # conversation's prior turns into the agent's context so it actually
    # remembers what was already said. None/omitted starts a new one.
    conversation_id: str | None = None


class TokenResponse(BaseModel):
    url: str
    token: str
    room_name: str
    # Always the conversation this call is (now) part of — a freshly
    # created one if the request didn't provide conversation_id, or the
    # same one echoed back if it did. The client remembers this and
    # passes it back on the *next* token request to keep resuming the
    # same thread across mic stop/start, until "New Chat" clears it.
    conversation_id: str


@router.post('/token', response_model=TokenResponse)
def create_voice_token(body: TokenRequest, db: Session = Depends(get_db)) -> TokenResponse:
    if body.mode not in MODE_INSTRUCTIONS:
        raise HTTPException(status_code=400, detail=f"Unknown mode '{body.mode}'.")

    if body.conversation_id:
        conversation = db.get(Conversation, body.conversation_id)
        if conversation is None:
            raise HTTPException(status_code=404, detail='Conversation not found.')
        if conversation.user_id != body.user_id:
            raise HTTPException(status_code=403, detail='You do not have access to this conversation.')
        if conversation.mode != body.mode:
            raise HTTPException(
                status_code=400,
                detail=f"This conversation is in '{conversation.mode}' mode, not '{body.mode}'.",
            )
    else:
        # Created now, synchronously, rather than lazily by the agent on
        # the first turn (the old behavior) — the client needs the real
        # id back in this same response so it can offer to resume this
        # exact call next time, even one that ends before anyone says
        # anything. Title is filled in later (see voice_transcript_service.py),
        # once the user's first real words exist to title it with.
        conversation = Conversation(user_id=body.user_id, mode=body.mode)
        db.add(conversation)
        db.commit()
        db.refresh(conversation)

    settings = get_settings()
    room_name = f'sana-{body.mode}-{secrets.token_hex(4)}'

    # Metadata travels with the agent dispatch, so the worker knows which
    # mode's instructions to load and who it's talking to — without the
    # client needing a second round trip. userId is what lets the agent
    # save the transcript under the right account; conversationId is
    # what lets it resume one instead of always starting fresh (see
    # voice_agent.py).
    agent_metadata = json.dumps(
        {
            'mode': body.mode,
            'userName': body.user_name,
            'userId': body.user_id,
            'conversationId': conversation.id,
        }
    )

    token = (
        AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
        .with_identity(body.user_id)
        .with_name(body.user_name)
        .with_grants(
            VideoGrants(
                room_join=True,
                room=room_name,
                can_publish=True,
                can_subscribe=True,
            )
        )
        .with_room_config(
            RoomConfiguration(
                agents=[RoomAgentDispatch(agent_name=AGENT_NAME, metadata=agent_metadata)],
            )
        )
        .to_jwt()
    )

    return TokenResponse(
        url=settings.livekit_url, token=token, room_name=room_name, conversation_id=conversation.id
    )


class SpeakRequest(BaseModel):
    # Capped well above any real UI line (the onboarding greeting is a
    # sentence) so this can't be turned into a way to synthesize
    # arbitrary long-form audio through a paid provider.
    text: str = Field(min_length=1, max_length=500)


@router.post('/speak')
async def speak(body: SpeakRequest, user: User = Depends(get_current_user)) -> Response:
    """Synthesizes [body.text] with the same voice the live voice-mode
    agent uses, for one-off lines outside a LiveKit room (currently:
    the onboarding screen's spoken greeting). Returns raw WAV bytes.

    Requires auth purely to keep this from being an open, unmetered
    TTS proxy — any logged-in user's text is fine to synthesize, there's
    nothing sensitive about the endpoint itself.
    """
    # Imported lazily, same reasoning as ai_service.py's LiveKitInferenceProvider:
    # keeps livekit-agents off the import path for anything that doesn't need it.
    from livekit.agents import APIConnectionError, APIError, APITimeoutError
    from livekit.agents.inference import TTS
    from livekit.agents.utils import http_context

    tts = TTS(model=_TTS_MODEL, voice=_TTS_VOICE)
    try:
        # Outside a LiveKit job/agent context (this is a plain FastAPI
        # request handler) the plugin has no aiohttp session to reuse —
        # http_context.open() stands one up for the call, kept open
        # through aclose() too since teardown may still use it.
        async with http_context.open():
            try:
                frame = await tts.synthesize(body.text).collect()
            finally:
                await tts.aclose()
    except APITimeoutError as e:
        raise HTTPException(status_code=504, detail='Voice synthesis timed out.') from e
    except (APIConnectionError, APIError) as e:
        logger.warning('TTS synthesis failed: %s', e)
        raise HTTPException(status_code=502, detail='Voice synthesis is unavailable right now.') from e

    return Response(content=frame.to_wav_bytes(), media_type='audio/wav')
