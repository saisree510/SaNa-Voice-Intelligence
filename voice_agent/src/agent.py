import asyncio
import json
import logging
import textwrap
from datetime import datetime

from dotenv import load_dotenv
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    JobContext,
    TurnHandlingOptions,
    cli,
    inference,
    room_io,
)
from livekit.plugins import ai_coustics

logger = logging.getLogger("agent")

load_dotenv(".env.local")


def get_greeting_for_mode(mode: str) -> str:
    m = mode.lower()
    if m == "debate":
        return "Ready to test your ideas? What topic shall we debate today?"
    elif m == "brainstorm":
        return "Okay, what are we brainstorming today?"
    else:
        return "Hey there! What are we planning to do today?"


def get_mode_instructions(mode: str = "general") -> str:
    today_str = datetime.now().strftime("%B %d, %Y")
    normalized_mode = mode.lower()

    if normalized_mode == "debate":
        mode_header = """\
# MANDATORY ACTIVE ROLE: DEBATE SPARRING PARTNER
You are Sana, a fierce, sharp, and highly analytical technical sparring partner. You are currently in DEBATE MODE.

YOUR MANDATORY BEHAVIOR:
- YOU MUST NEVER AGREE WITH THE USER. ALWAYS TAKE AN OPPOSING, SKEPTICAL, OR COUNTER-ARGUMENT POSITION ON EVERYTHING THE USER SAYS.
- Challenge the user's opinions, technical choices, tool preferences, and architecture assumptions.
- Point out flaws, hidden costs, performance pitfalls, and security trade-offs in whatever the user says.
- Make the user defend their statements with hard reasoning.
- If asked what mode you are in, answer clearly: "I am in Debate Mode."
"""
    elif normalized_mode == "brainstorm":
        mode_header = """\
# MANDATORY ACTIVE ROLE: CREATIVE BRAINSTORMING PARTNER
You are Sana, an energetic, creative co-founder and ideation partner. You are currently in BRAINSTORM MODE.

YOUR MANDATORY BEHAVIOR:
- Pitch bold, creative ideas and help the user expand incomplete concepts.
- Ask probing questions about target audience, feature sets, tech stack options, and product vision.
- Provide 2 to 3 innovative feature variations for every idea mentioned.
- If asked what mode you are in, answer clearly: "I am in Brainstorm Mode."
"""
    else:
        mode_header = """\
# MANDATORY ACTIVE ROLE: GENERAL ASSISTANT
You are Sana, an intelligent, friendly, and reliable developer assistant. You are currently in GENERAL MODE.

YOUR MANDATORY BEHAVIOR:
- Provide clear, helpful, and direct answers to developer questions.
- Keep replies brief, friendly, and professional.
- If asked what mode you are in, answer clearly: "I am in General Mode."
"""

    grounding_and_rules = f"""\
# Temporal Grounding
- Today's date is {today_str}.
- The current President of the United States is Donald Trump (who assumed office for his second term in January 2025).

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

    def set_mode(self, new_mode: str) -> None:
        self.current_mode = new_mode
        new_inst = get_mode_instructions(new_mode)
        self.update_instructions(new_inst)
        logger.info(f"Updated Assistant instructions for mode: {new_mode}")


server = AgentServer()


@server.rtc_session(agent_name="voice_agent")
async def my_agent(ctx: JobContext):
    ctx.log_context_fields = {
        "room": ctx.room.name,
    }

    assistant = Assistant(mode="general")
    greeting_spoken = False

    session = AgentSession(
        stt=inference.STT(model="deepgram/nova-3", language="multi"),
        tts=inference.TTS(
            model="cartesia/sonic-3", voice="9626c31c-bec5-4cca-baa8-f8ba9e84c8bc"
        ),
        turn_handling=TurnHandlingOptions(
            turn_detection=inference.TurnDetector(),
        ),
        preemptive_generation=False,
    )

    await session.start(
        agent=assistant,
        room=ctx.room,
        room_options=room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=ai_coustics.audio_enhancement(
                    model=ai_coustics.EnhancerModel.QUAIL_VF_S
                ),
            ),
        ),
    )

    def apply_mode(new_mode: str):
        logger.info(f"Applying mode switch: '{new_mode}'")
        assistant.set_mode(new_mode)

        # Update system message IN PLACE at index 0 of session.history
        new_instructions = get_mode_instructions(new_mode)
        if hasattr(session, "history") and session.history:
            try:
                system_found = False
                for msg in session.history.messages():
                    if getattr(msg, "role", None) == "system":
                        msg.content = [new_instructions]
                        system_found = True
                        logger.info(f"Updated in-place system message at index 0 for mode: '{new_mode}'")
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
        if greeting_spoken:
            return
        greeting_spoken = True
        await asyncio.sleep(0.4)
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
                logger.info(f"Received mode switch payload: {new_mode} (is_initial: {is_initial})")
                apply_mode(new_mode)

                if is_initial:
                    asyncio.create_task(speak_greeting(new_mode))
        except Exception as e:
            logger.warning(f"Error parsing data packet in voice agent: {e}")

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, old_metadata, new_metadata):
        logger.info(f"Participant metadata changed: {new_metadata}")
        if new_metadata:
            try:
                meta = json.loads(new_metadata)
                mode = meta.get("mode", "general")
                apply_mode(mode)
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
        apply_mode(mode)
        asyncio.create_task(speak_greeting(mode))

    await ctx.connect()

    # Fallback greeting if participant is already connected upon agent join
    for p in ctx.room.remote_participants.values():
        mode = "general"
        if p.metadata:
            try:
                meta = json.loads(p.metadata)
                mode = meta.get("mode", mode)
            except Exception:
                pass
        apply_mode(mode)
        asyncio.create_task(speak_greeting(mode))


if __name__ == "__main__":
    cli.run_app(server)
