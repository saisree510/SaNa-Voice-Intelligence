"""SANA's voice agent worker.

Run as its own long-running process (see README.md) — separate from the
FastAPI server in app/main.py. It registers with LiveKit as an agent
named AGENT_NAME and only joins a room when explicitly dispatched
(app/api/voice.py does this via RoomAgentDispatch when it mints a
token), carrying `{"mode": ..., "userName": ..., "userId": ...}` as job
metadata so one worker serves all three modes instead of running three
agents, and knows whose account to save the transcript under.

Uses LiveKit Inference for STT/LLM/TTS (per project decision) — no
separate OpenAI/Deepgram/Cartesia accounts needed, just the LiveKit
project credentials already in .env.
"""

import json
import logging

from dotenv import load_dotenv
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, TurnHandlingOptions, cli, inference
from livekit.agents.voice.events import ConversationItemAddedEvent

from app.modes import MODE_INSTRUCTIONS, OPENING_LINES
from app.services.voice_transcript_service import VoiceTranscriptRecorder

logger = logging.getLogger('sana-agent')

load_dotenv('.env')

AGENT_NAME = 'sana-agent'
DEFAULT_MODE = 'build'


class SanaAssistant(Agent):
    def __init__(self, instructions: str) -> None:
        super().__init__(
            llm=inference.LLM(model='google/gemma-4-31b-it'),
            instructions=instructions,
        )


server = AgentServer()


@server.rtc_session(agent_name=AGENT_NAME)
async def sana_agent(ctx: JobContext) -> None:
    ctx.log_context_fields = {'room': ctx.room.name}

    mode = DEFAULT_MODE
    user_name = 'there'
    user_id: str | None = None
    raw_metadata = ctx.job.metadata or ''
    if raw_metadata:
        try:
            parsed = json.loads(raw_metadata)
            mode = parsed.get('mode', DEFAULT_MODE)
            user_name = parsed.get('userName', user_name)
            user_id = parsed.get('userId')
        except json.JSONDecodeError:
            logger.warning('Could not parse job metadata: %r', raw_metadata)

    instructions = MODE_INSTRUCTIONS.get(mode, MODE_INSTRUCTIONS[DEFAULT_MODE])
    opening_line = OPENING_LINES.get(mode, OPENING_LINES[DEFAULT_MODE])

    session = AgentSession(
        stt=inference.STT(model='deepgram/nova-3', language='multi'),
        tts=inference.TTS(model='cartesia/sonic-3', voice='9626c31c-bec5-4cca-baa8-f8ba9e84c8bc'),
        # preemptive_generation defaults to enabled=True already; no need
        # to pass it (it takes a PreemptiveGenerationOptions mapping, not
        # a bool — verified by testing, an earlier `True` here crashed
        # every job with "'bool' object is not a mapping").
        turn_handling=TurnHandlingOptions(turn_detection=inference.TurnDetector()),
    )

    # Saves every turn to the same Conversation/Message tables text chat
    # uses (see voice_transcript_service.py), so a voice call shows up
    # in "Chats" like any other conversation instead of only ever
    # living in the app's local, on-device cache. Only skipped if a
    # (pre-this-change) client didn't send userId — no user_id, no
    # owner to save the conversation under.
    if user_id:
        recorder = VoiceTranscriptRecorder(user_id=user_id, mode=mode)

        def _on_item_added(event: ConversationItemAddedEvent) -> None:
            role = getattr(event.item, 'role', None)
            text = getattr(event.item, 'text_content', None)
            if role and text:
                recorder.record(role=role, text=text)

        session.on('conversation_item_added', _on_item_added)
    else:
        logger.warning('No userId in job metadata — this call\'s transcript will not be saved.')

    await session.start(agent=SanaAssistant(instructions), room=ctx.room)
    await session.generate_reply(
        instructions=f'Greet {user_name} briefly and say: "{opening_line}"'
    )

    await ctx.connect()


if __name__ == '__main__':
    cli.run_app(server)
