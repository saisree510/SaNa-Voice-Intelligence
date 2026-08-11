"""SANA's voice agent worker.

Run as its own long-running process (see README.md) — separate from the
FastAPI server in app/main.py. It registers with LiveKit as an agent
named AGENT_NAME and only joins a room when explicitly dispatched
(app/api/voice.py does this via RoomAgentDispatch when it mints a
token), carrying `{"mode": ..., "userName": ..., "userId": ...,
"conversationId": ...}` as job metadata so one worker serves all three
modes instead of running three agents, knows whose account to save the
transcript under, and — if conversationId points at a conversation with
prior turns — resumes it instead of starting fresh (see
_load_resume_context below).

Uses LiveKit Inference for STT/LLM/TTS (per project decision) — no
separate OpenAI/Deepgram/Cartesia accounts needed, just the LiveKit
project credentials already in .env.
"""

import json
import logging

from dotenv import load_dotenv
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, TurnHandlingOptions, cli, inference
from livekit.agents.llm import ChatContext, FunctionTool
from livekit.agents.voice.events import ConversationItemAddedEvent

from app.modes import MODE_INSTRUCTIONS, OPENING_LINES, current_datetime_note, user_name_note
from app.services.build_agent import BuildAgent
from app.services.build_tools import make_build_project_tool, make_check_build_progress_tool
from app.services.voice_transcript_service import VoiceTranscriptRecorder, load_conversation_history

logger = logging.getLogger('sana-agent')

load_dotenv('.env')

AGENT_NAME = 'sana-agent'
DEFAULT_MODE = 'build'


class SanaAssistant(Agent):
    def __init__(
        self,
        instructions: str,
        tools: list[FunctionTool] | None = None,
        chat_ctx: ChatContext | None = None,
    ) -> None:
        super().__init__(
            llm=inference.LLM(model='google/gemma-4-31b-it'),
            instructions=instructions,
            tools=tools or [],
            chat_ctx=chat_ctx,
        )


server = AgentServer()


@server.rtc_session(agent_name=AGENT_NAME)
async def sana_agent(ctx: JobContext) -> None:
    ctx.log_context_fields = {'room': ctx.room.name}

    mode = DEFAULT_MODE
    # None until real metadata says otherwise -- distinct from
    # `greeting_name` below, which always has *something* to address the
    # user by even when no real name is known. Passing 'there' itself
    # into user_name_note() would tell the model the user's name is
    # literally "there", which is wrong, not just unhelpful.
    user_name: str | None = None
    user_id: str | None = None
    conversation_id: str | None = None
    raw_metadata = ctx.job.metadata or ''
    if raw_metadata:
        try:
            parsed = json.loads(raw_metadata)
            mode = parsed.get('mode', DEFAULT_MODE)
            user_name = parsed.get('userName') or None
            user_id = parsed.get('userId')
            conversation_id = parsed.get('conversationId')
        except json.JSONDecodeError:
            logger.warning('Could not parse job metadata: %r', raw_metadata)
    greeting_name = user_name or 'there'

    instructions = MODE_INSTRUCTIONS.get(mode, MODE_INSTRUCTIONS[DEFAULT_MODE])
    # Computed fresh per call, not baked into MODE_INSTRUCTIONS -- see
    # current_datetime_note's/user_name_note's docstrings for why.
    instructions += current_datetime_note()
    instructions += user_name_note(user_name)
    opening_line = OPENING_LINES.get(mode, OPENING_LINES[DEFAULT_MODE])

    # If conversation_id points at a conversation with real prior turns,
    # this is a resumed call (user stopped the mic and started it again)
    # -- seed the agent's context with everything already said so it
    # doesn't act like it's meeting the user for the first time. Empty
    # for a genuinely new conversation, so resume_chat_ctx stays None
    # and SanaAssistant falls back to its normal empty context.
    resume_chat_ctx: ChatContext | None = None
    if conversation_id:
        prior_turns = load_conversation_history(conversation_id)
        if prior_turns:
            resume_chat_ctx = ChatContext.empty()
            for turn in prior_turns:
                role = turn.get('role')
                content = turn.get('content', '')
                if role in ('user', 'assistant') and content:
                    resume_chat_ctx.add_message(role=role, content=content)

    # Build mode only — Debate/Brainstorm get no tools, same as before.
    # Independent of VoiceTranscriptRecorder's conversation_id below:
    # this is its own workspace id, populated on the first build_project
    # call and reused for every one after in this same room session.
    # check_build_progress shares the same BuildAgent/holder as
    # build_project (see build_tools.py) so it's always asking about the
    # same job — voice especially needs this since build_project never
    # blocks the conversation until a build finishes (see its docstring:
    # doing that caused SANA to guess at "is it done" while a build was
    # still genuinely running, confirmed by live testing).
    agent_tools: list[FunctionTool] = []
    if mode == 'build':
        build_agent = BuildAgent()
        job_id_holder: dict[str, str | None] = {'job_id': None}
        agent_tools = [
            make_build_project_tool(
                build_agent, job_id_holder, user_id=user_id, conversation_id=conversation_id
            ),
            make_check_build_progress_tool(build_agent, job_id_holder),
        ]

    session = AgentSession(
        # language='en', not 'multi': confirmed by testing that letting
        # Deepgram auto-detect language per utterance occasionally
        # misreads ordinary English speech as a different language,
        # and the model would then reply in that (wrong) language —
        # SANA has no actual multi-language support today, so nothing
        # was gained by leaving this open, only an occasional broken
        # reply.
        stt=inference.STT(model='deepgram/nova-3', language='en'),
        tts=inference.TTS(model='cartesia/sonic-3', voice='9626c31c-bec5-4cca-baa8-f8ba9e84c8bc'),
        # preemptive_generation defaults to enabled=True already; no need
        # to pass it (it takes a PreemptiveGenerationOptions mapping, not
        # a bool — verified by testing, an earlier `True` here crashed
        # every job with "'bool' object is not a mapping").
        #
        # interruption overrides the framework's defaults, which is why
        # talking over SANA wasn't reliably stopping her (user report):
        # - mode left as the library default ("adaptive", an ML classifier
        #   judging whether overlapping speech is a *real* interruption)
        #   instead of "vad" (stop the instant real voice energy is
        #   detected, no judgment call) — the simple, immediate behavior
        #   people actually expect from "I started talking, so stop".
        #
        # That first fix (mode='vad') traded away the ML classifier's
        # other job: telling genuine interruptions apart from SANA's own
        # TTS audio leaking back into the mic (open speakers, no
        # headset) and getting mis-transcribed as user speech — live
        # testing showed exactly this, a self-referential loop where
        # SANA replied to a garbled echo of her own last sentence.
        # 'vad' mode has no "is this real" judgment call to make (that's
        # the whole point of it), but does still expose:
        # - min_duration raised slightly (0.5s -> 0.7s): a bump of
        #   sustained voice activity has to last a bit longer before it
        #   counts, filtering the shortest blips without meaningfully
        #   dulling the "I started talking, stop" responsiveness.
        # - min_words: 2 — even under 'vad', the interrupting audio's
        #   transcript still needs at least 2 words before it's treated
        #   as a real new turn worth replying to, not a one-syllable
        #   echo fragment.
        # - resume_false_interruption back to True (its actual default —
        #   the earlier fix turned this off): if nothing coherent
        #   follows an interruption within false_interruption_timeout,
        #   it's still recoverable — SANA resumes her original sentence
        #   instead of being stuck reacting to whatever the echo said.
        #   This only matters *after* SANA has already stopped instantly
        #   (mode='vad' still guarantees that part), so it doesn't bring
        #   back "interrupting didn't work" — it just stops a false
        #   trigger from derailing the rest of the conversation.
        #
        # Not independently verified against real microphone/speaker
        # audio (this environment can't do that) — worth confirming live.
        #
        # endpointing is a *separate* fix from the interruption block
        # above — interruption only governs audio detected while SANA is
        # actively speaking; this governs how a *fresh* turn gets
        # accepted at all, any other time (including the first moment of
        # a call, before anyone's said anything real yet). Live testing
        # caught this directly: a stray "Yes or no?" got recorded as a
        # user turn 133ms after the opening greeting was recorded — far
        # too fast to be a real reply, almost certainly noise/echo picked
        # up right as the call started. min_delay raised from the
        # streaming-turn-detector default (0.3s) to 0.9s: the mic has to
        # stay quiet noticeably longer after what it heard before that's
        # accepted as "the user is done speaking" — fewer brief blips
        # misread as complete turns, at the cost of SANA feeling a touch
        # slower to respond even to real speech.
        turn_handling=TurnHandlingOptions(
            turn_detection=inference.TurnDetector(),
            endpointing={'min_delay': 0.9, 'max_delay': 3.0},
            interruption={
                'mode': 'vad',
                'min_duration': 0.7,
                'min_words': 2,
                'resume_false_interruption': True,
            },
        ),
    )

    # Saves every turn to the same Conversation/Message tables text chat
    # uses (see voice_transcript_service.py), so a voice call shows up
    # in "Chats" like any other conversation instead of only ever
    # living in the app's local, on-device cache. Only skipped if a
    # (pre-this-change) client didn't send userId — no user_id, no
    # owner to save the conversation under.
    if user_id:
        recorder = VoiceTranscriptRecorder(user_id=user_id, mode=mode, conversation_id=conversation_id)

        def _on_item_added(event: ConversationItemAddedEvent) -> None:
            role = getattr(event.item, 'role', None)
            text = getattr(event.item, 'text_content', None)
            if role and text:
                recorder.record(role=role, text=text)

        session.on('conversation_item_added', _on_item_added)
    else:
        logger.warning('No userId in job metadata — this call\'s transcript will not be saved.')

    await session.start(
        agent=SanaAssistant(instructions, tools=agent_tools, chat_ctx=resume_chat_ctx), room=ctx.room
    )
    if resume_chat_ctx is None:
        # Genuinely new conversation -- the normal "hi, I'm SANA" opening.
        await session.generate_reply(
            instructions=f'Greet {greeting_name} briefly and say: "{opening_line}"'
        )
    else:
        # Resumed call -- re-introducing SANA or repeating the mode's
        # opening line would be strange when you were already mid-
        # conversation seconds ago. A brief "still here, go ahead"
        # instead of silence: the user just turned the mic back on
        # expecting to keep talking, not to wonder if the call connected.
        await session.generate_reply(
            instructions=(
                'The user just reconnected to continue this exact conversation, seconds or '
                'minutes after pausing it. Briefly acknowledge you are still with them (e.g. '
                '"I am still here" or similar, your own words) and naturally continue from where '
                'the conversation left off. Do not re-introduce yourself or repeat any opening line.'
            )
        )

    await ctx.connect()


if __name__ == '__main__':
    cli.run_app(server)
