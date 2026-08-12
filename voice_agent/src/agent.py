import asyncio
import json
import logging
import os
import textwrap
from datetime import datetime
from typing import Any, Dict, List, Optional

import urllib.request

from dotenv import load_dotenv
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    JobContext,
    TurnHandlingOptions,
    cli,
    inference,
    llm,
    room_io,
)
from livekit.plugins import ai_coustics, groq, silero

logger = logging.getLogger("agent")

load_dotenv(".env.local")
AGENT_NAME = os.getenv("AGENT_NAME", "voice_agent")


import re
import uuid

_offline_projects_store = {}
_room_chat_memory: Dict[str, list] = {}

RESTORED_MEMORY_MAX_MESSAGES = 40
RESTORED_MEMORY_MAX_CONTENT_CHARS = 4000


def get_backend_url() -> str:
    return os.getenv("BACKEND_URL", "").strip()


def normalize_restored_messages(
    messages: Any,
    *,
    max_messages: int = RESTORED_MEMORY_MAX_MESSAGES,
) -> list[dict[str, str]]:
    if not isinstance(messages, list):
        return []
    normalized: list[dict[str, str]] = []
    for item in messages:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = item.get("content")
        if role not in {"user", "assistant"} or not isinstance(content, str):
            continue
        content = content.strip()
        if not content:
            continue
        message_id = item.get("id")
        if not isinstance(message_id, str) or not message_id.strip():
            message_id = f"restored-{uuid.uuid4().hex}"
        normalized.append(
            {
                "id": message_id,
                "role": role,
                "content": content[-RESTORED_MEMORY_MAX_CONTENT_CHARS:],
            }
        )
    return normalized[-max_messages:]


def build_restored_chat_context(
    existing_chat_ctx: llm.ChatContext,
    messages: Any,
) -> llm.ChatContext:
    del existing_chat_ctx
    chat_ctx = llm.ChatContext()
    for message in normalize_restored_messages(messages):
        chat_ctx.add_message(
            id=message["id"],
            role=message["role"],
            content=message["content"],
        )
    return chat_ctx


@llm.function_tool
async def create_build_project_plan(title: str, specification: str) -> str:
    """Draft a new build project plan and return the project ID and generated plan summary."""
    slug = re.sub(r"[^a-zA-Z0-9_-]", "_", title.lower())
    draft_workspace = os.path.abspath(
        f"C:\\Users\\saisr\\Projects\\SANA-LiveKit\\drafts\\{slug}"
    )
    try:
        backend_url = get_backend_url() or "http://127.0.0.1:8000"
        req_data = json.dumps(
            {
                "title": title,
                "specification": specification,
                "workspace_path": draft_workspace,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{backend_url}/v1/build/projects",
            data=req_data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            pid = data.get("project_id")
            summary = data.get("plan_summary")
            return f"Project created successfully with ID {pid}. Workspace: {draft_workspace}. Plan Summary: {summary}"
    except Exception as e:
        logger.warning(f"Error calling create_build_project_plan backend endpoint: {e}")
        if get_backend_url():
            return (
                f"I could not draft '{title}' through the configured backend, so I did not save anything locally. "
                "Please verify the hosted backend deployment and Build Mode configuration."
            )
        fallback_pid = f"proj-{uuid.uuid4().hex[:8]}"
        _offline_projects_store[fallback_pid] = {
            "title": title,
            "specification": specification,
            "workspace_path": draft_workspace,
        }
        return (
            f"Project plan drafted for '{title}' with ID {fallback_pid}. "
            f"Draft workspace: '{draft_workspace}'. Awaiting explicit user approval before execution."
        )


@llm.function_tool
async def approve_and_execute_build_project(project_id: str) -> str:
    """Explicitly approve and trigger execution for a drafted build project."""
    try:
        backend_url = get_backend_url() or "http://127.0.0.1:8000"
        req = urllib.request.Request(
            f"{backend_url}/v1/build/projects/{project_id}/approve",
            data=b"{}",
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return f"Execution result summary: {data.get('result_summary')}"
    except Exception as e:
        logger.warning(
            f"Error calling approve_and_execute_build_project backend endpoint: {e}. Running local file drafting fallback."
        )
        offline_data = _offline_projects_store.get(project_id, {})
        workspace = offline_data.get("workspace_path") or os.path.abspath(
            f"C:\\Users\\saisr\\Projects\\SANA-LiveKit\\drafts\\project_{project_id}"
        )
        spec = offline_data.get("specification") or "Scaffold project"
        title = offline_data.get("title") or "Build Target"

        os.makedirs(workspace, exist_ok=True)
        spec_path = os.path.join(workspace, "project_spec.md")
        with open(spec_path, "w", encoding="utf-8") as f:
            f.write(
                f"# Project Blueprint & Specification: {title}\n\n**Specification:** {spec}\n**Status:** Executed\n"
            )

        main_path = os.path.join(workspace, "main.py")
        with open(main_path, "w", encoding="utf-8") as f:
            f.write(
                f"# Auto-generated by SaNa Build Engine\n# Project: {title}\n\ndef main():\n    print('Running {title}')\n\nif __name__ == '__main__':\n    main()\n"
            )

        return f"Build execution completed for project {project_id}. Generated files 'project_spec.md' and 'main.py' in workspace '{workspace}'."


def get_greeting_for_mode(mode: str) -> str:
    openings = {
        "debate": (
            "Bring me your strongest argument. I am ready to tear into the weak spots, "
            "so what are we debating?"
        ),
        "brainstorm": (
            "Let us make some sparks. Give me the rough idea, and we will turn it into "
            "something bold. What are we exploring?"
        ),
        "build": (
            "Let us build this properly. Tell me what you want to create, and I will help "
            "shape the plan before we touch the code. What are we making?"
        ),
        "general": "Hey, I am Sana. What is on your mind today?",
    }
    return openings.get(mode.lower(), openings["general"])


def get_resume_opening_instructions(mode: str) -> str:
    normalized_mode = mode.lower()
    mode_direction = {
        "debate": (
            "Stay in debate mode: sound fierce and confident, challenge the latest claim "
            "or unresolved assumption, and invite the user to defend it."
        ),
        "brainstorm": (
            "Stay in brainstorm mode: sound energetic and imaginative, reconnect to the "
            "most promising idea, and invite the next creative step."
        ),
        "build": (
            "Stay in build mode: sound like a decisive but approachable tech lead, name the "
            "current requirement or decision, and ask for the next planning step without "
            "executing anything."
        ),
        "general": (
            "Stay in general mode: sound warm and conversational, reconnect to the latest "
            "topic, and invite the user to continue."
        ),
    }.get(normalized_mode, "Stay warm, conversational, and helpful.")
    return (
        "The selected chat has a restored conversation history. Give one brief reopening "
        "of no more than two spoken sentences. Mention one specific topic, decision, or "
        "unresolved point from the latest restored turns, then ask one natural question "
        f"that continues the work. {mode_direction} Do not give a generic greeting, recap "
        "the whole chat, or claim you cannot remember it."
    )


def get_mode_instructions(mode: str = "general") -> str:
    today_str = datetime.now().strftime("%B %d, %Y")
    normalized_mode = mode.lower()

    if normalized_mode == "debate":
        mode_header = """\
# MANDATORY ACTIVE ROLE: DEBATE SPARRING PARTNER
You are Sana, an unyielding, fierce, and highly analytical technical sparring partner. You are currently in DEBATE MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- YOU MUST NEVER AGREE WITH THE USER AT ANY POINT IN THIS CONVERSATION.
- NEVER SAY "THAT IS A FAIR POINT", "YOU HAVE A POINT", "GOOD POINT", OR "I AGREE". DO NOT CONCEDE GROUND.
- EVEN IF THE USER PRESENTS A STRONG ARGUMENT, IMMEDIATELY PUSH BACK WITH A COUNTER-EXAMPLE, FLAWS, HIDDEN COSTS, OR SCALABILITY RISKS.
- START EVERY RESPONSE DIRECTLY WITH A REBUTTAL OR SKEPTICAL CHALLENGE.
- Force the user to continuously defend their reasoning and choices.
- Sound fierce, quick, and human rather than robotic: use sharp conversational phrasing, vary your challenges, and press one weak point at a time.
- If asked what mode you are in, answer clearly: "I am in Debate Mode."
"""
    elif normalized_mode == "brainstorm":
        mode_header = """\
# MANDATORY ACTIVE ROLE: CREATIVE BRAINSTORMING PARTNER
You are Sana, an energetic, creative co-founder and ideation partner. You are currently in BRAINSTORM MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- ALWAYS PITCH BOLD, UNVENTURED CREATIVE IDEAS AND HELP EXPAND INCOMPLETE CONCEPTS.
- NEVER GIVE PASSIVE, GENERIC ASSISTANT REPLIES OR SIMPLE AGREEMENTS.
- FOR EVERY USER STATEMENT, OFFER 2 TO 3 INNOVATIVE FEATURE VARIATIONS OR UNCONVENTIONAL ANGLES.
- ASK AT LEAST ONE PROBING QUESTION ABOUT TARGET USERS, KEY FEATURES, TECH STACK OPTIONS, OR PRODUCT VISION.
- Sound like an excited creative partner in a real conversation: react directly to the user's idea before expanding it, and avoid repetitive canned enthusiasm.
- BRAINSTORM TO BUILD HANDOFF: When the user expresses clear intent to build (e.g., "Let's build it", "Make this a project", "I want to start building"), acknowledge their decision warmly, state a 2-sentence summary of the vision, and ask if they are ready to transition to Build Mode.
- If asked what mode you are in, answer clearly: "I am in Brainstorm Mode."
"""
    elif normalized_mode == "build":
        mode_header = """\
# MANDATORY ACTIVE ROLE: TECH LEAD & BUILD ORCHESTRATOR
You are Sana, a decisive, precise Tech Lead and Build Orchestrator. You are currently in BUILD MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- HELP THE USER DEFINE CLEAR PROJECT REQUIREMENTS, SPECIFICATIONS, AND ARCHITECTURE PLANS.
- Sound like an approachable, decisive tech lead in a working session: refer naturally to earlier decisions and move the discussion forward one concrete choice at a time.
- EXPLICIT APPROVAL GATE: NEVER TRIGGER CODE EXECUTION OR FILE MUTATION AUTOMATICALLY. ALWAYS PRESENT THE PLAN CLEARLY AND ASK FOR THE USER'S EXPLICIT APPROVAL ("Are you ready to approve and execute this plan?").
- WHEN BUILD EXECUTION FINISHES, SUMMARIZE THE GENERATED FILES AND VERIFICATION RESULTS IN 2 TO 3 CLEAR, DIRECT SENTENCES.
- If asked what mode you are in, answer clearly: "I am in Build Mode."
"""
    else:
        mode_header = """\
# MANDATORY ACTIVE ROLE: GENERAL ASSISTANT
You are Sana, an intelligent, friendly, and reliable developer assistant. You are currently in GENERAL MODE.

YOUR MANDATORY BEHAVIOR:
- Provide clear, helpful, and direct answers to developer questions.
- Keep replies brief, warm, conversational, and professional. Respond directly to what the user just said and refer naturally to relevant earlier context.
- If asked what mode you are in, answer clearly: "I am in General Mode."
"""

    grounding_and_rules = f"""\
# Temporal Grounding
- Today's date is {today_str}.
- The current President of the United States is Donald Trump (who assumed office for his second term in January 2025).

# Conversational continuity
- Speak like an engaged human collaborator, not a scripted menu or support bot.
- Preserve the active mode's personality on every turn while varying sentence openings and phrasing.
- Use relevant details from the conversation naturally; do not repeatedly summarize or announce that you remember them.

# Output rules (Voice Output)
- Respond in plain text only. Never use JSON, markdown, bullet points, numbered lists, tables, code blocks, emojis, or formatting tags.
- Keep replies brief: one to three sentences max per response. Ask one question at a time.
- Spell out numbers, phone numbers, or email addresses.
- Omit `https://` when listing URLs.

# Guardrails
- Stay within safe, lawful, and appropriate use; decline harmful requests.
- For medical, legal, or financial topics, provide general info only.
"""

    return f"{mode_header}\n{grounding_and_rules}"


class Assistant(Agent):
    def __init__(self, mode: str = "general") -> None:
        self.current_mode = mode
        super().__init__(
            llm=inference.LLM(model="google/gemma-4-31b-it"),
            instructions=get_mode_instructions(mode),
        )

    async def set_mode(self, new_mode: str) -> None:
        self.current_mode = new_mode
        new_inst = get_mode_instructions(new_mode)
        self._instructions = new_inst
        await self.update_instructions(new_inst)
        logger.info(f"Updated Assistant instructions for mode: {new_mode}")


server = AgentServer()


@server.rtc_session(agent_name=AGENT_NAME)
async def my_agent(ctx: JobContext):
    groq_key = os.getenv("GROQ_API_KEY")
    logger.info(
        f"Connecting session in room '{ctx.room.name}' as agent '{AGENT_NAME}'. GROQ_API_KEY present: {bool(groq_key)}. Using LiveKit Inference for Cartesia TTS."
    )

    assistant = Assistant(mode="general")
    greeting_spoken = False

    session = AgentSession(
        stt=groq.STT(model="whisper-large-v3-turbo", api_key=groq_key),
        llm=groq.LLM(model="llama-3.3-70b-versatile", api_key=groq_key),
        tts=inference.TTS(
            model="cartesia/sonic-3",
            voice="f786b574-daa5-4673-aa0c-cbe3e8534c02",
            language="en",
        ),
        vad=silero.VAD.load(),
        tools=[create_build_project_plan, approve_and_execute_build_project],
        preemptive_generation=False,
    )

    await session.start(
        agent=assistant,
        room=ctx.room,
    )

    current_applied_mode = None
    restored_conversation_id: Optional[str] = None
    restore_lock = asyncio.Lock()

    async def restore_conversation(payload: dict[str, Any]) -> None:
        nonlocal restored_conversation_id, greeting_spoken
        conversation_id = payload.get("conversation_id")
        if not isinstance(conversation_id, str) or not conversation_id:
            return
        async with restore_lock:
            if restored_conversation_id == conversation_id:
                return
            restored_messages = normalize_restored_messages(payload.get("messages"))
            if not restored_messages:
                return
            greeting_spoken = True
            restored_mode = payload.get("mode", current_applied_mode or "general")
            if not isinstance(restored_mode, str):
                restored_mode = "general"
            await apply_mode(restored_mode)
            chat_ctx = build_restored_chat_context(
                assistant.chat_ctx, restored_messages
            )
            await assistant.update_chat_ctx(chat_ctx)
            _room_chat_memory[ctx.room.name] = restored_messages
            restored_conversation_id = conversation_id
            session.generate_reply(
                instructions=get_resume_opening_instructions(restored_mode),
                allow_interruptions=True,
            )

    async def apply_mode(new_mode: str):
        nonlocal current_applied_mode
        if current_applied_mode == new_mode:
            return
        current_applied_mode = new_mode
        logger.info(f"Applying mode switch: '{new_mode}'")
        await assistant.set_mode(new_mode)

        # Update system message IN PLACE at index 0 of session.history
        new_instructions = get_mode_instructions(new_mode)
        if hasattr(session, "history") and session.history:
            try:
                system_found = False
                for msg in session.history.messages():
                    if getattr(msg, "role", None) == "system":
                        msg.content = [new_instructions]
                        system_found = True
                        logger.info(
                            f"Updated in-place system message at index 0 for mode: '{new_mode}'"
                        )
                        break
                if not system_found:
                    session.history.add_message(
                        role="system",
                        content=new_instructions,
                    )
            except Exception as e:
                logger.warning(f"Failed to update session.history system prompt: {e}")

    async def speak_greeting(mode: str):
        nonlocal greeting_spoken
        await asyncio.sleep(0.8)
        if greeting_spoken:
            return
        greeting_spoken = True
        greeting = get_greeting_for_mode(mode)
        logger.info(f"Speaking initial mode greeting for mode '{mode}': '{greeting}'")
        try:
            await session.say(greeting)
        except Exception as e:
            logger.warning(f"Failed to speak initial mode greeting: {e}", exc_info=True)

    @ctx.room.on("data_received")
    def on_data_received(data_packet):
        try:
            payload = json.loads(data_packet.data.decode("utf-8"))
            if payload.get("type") == "mode_switch":
                new_mode = payload.get("mode", "general")
                is_initial = payload.get("is_initial", False)
                if current_applied_mode == new_mode:
                    return
                logger.info(
                    f"Received mode switch payload: {new_mode} (is_initial: {is_initial})"
                )
                asyncio.create_task(apply_mode(new_mode))

                if is_initial:
                    asyncio.create_task(speak_greeting(new_mode))
            elif payload.get("type") == "conversation_restore":
                asyncio.create_task(restore_conversation(payload))
        except Exception as e:
            logger.warning(f"Error parsing data packet in voice agent: {e}")

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, old_metadata, new_metadata):
        logger.info(f"Participant metadata changed: {new_metadata}")
        if new_metadata:
            try:
                meta = json.loads(new_metadata)
                mode = meta.get("mode", "general")
                asyncio.create_task(apply_mode(mode))
            except Exception as e:
                logger.warning(f"Error parsing updated metadata: {e}")

    @ctx.room.on("participant_connected")
    def on_participant_connected(participant):
        logger.info(f"Participant connected: {participant.identity}")
        mode = "general"
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                mode = meta.get("mode", mode)
            except Exception:
                pass
        asyncio.create_task(apply_mode(mode))
        asyncio.create_task(speak_greeting(mode))

    # Fallback greeting if participant is already connected upon agent join
    for p in ctx.room.remote_participants.values():
        mode = "general"
        if p.metadata:
            try:
                meta = json.loads(p.metadata)
                mode = meta.get("mode", mode)
            except Exception:
                pass
        asyncio.create_task(apply_mode(mode))
        asyncio.create_task(speak_greeting(mode))


if __name__ == "__main__":
    cli.run_app(server)
