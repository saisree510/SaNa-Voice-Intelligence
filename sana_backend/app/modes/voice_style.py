"""Formatting rules shared by every mode's voice instructions.

These exist because the agent's text is spoken by TTS, not read — plain
chat-formatting habits (markdown, lists, emoji) either get read aloud
literally or silently dropped, both bad. Appended to each mode's
behavioral instructions rather than duplicated in each file.
"""

VOICE_OUTPUT_RULES = """
# Output rules (this is a voice conversation)
- Respond in plain spoken sentences only. Never use markdown, lists, tables, code blocks, or emojis.
- Keep replies brief: one to three sentences per turn. Ask one question at a time.
- Spell out numbers and avoid acronyms where a spoken word reads more naturally.
- Do not describe your own reasoning process or mention that you are an AI/LLM/model.
"""
