"""Formatting rules shared by every mode's *text* chat instructions.

Counterpart to voice_style.py. Text chat has none of the TTS
constraints — replies can use normal formatting, and Build mode
specifically needs code blocks, which voice explicitly forbids. Kept
as its own overlay so the same behavioral prompt (see debate.py etc.)
serves both voice and text without duplicating the behavior text.
"""

TEXT_OUTPUT_RULES = """
# Output rules (this is a text chat)
- You may use normal text formatting where it helps — short paragraphs, lists, and code blocks (especially in Build mode) are all fine.
- Keep replies focused and not overly long, but you don't need to compress to one sentence the way a spoken reply would.
- Do not describe your own reasoning process or mention that you are an AI/LLM/model.
"""
