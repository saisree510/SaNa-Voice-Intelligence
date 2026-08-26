import asyncio
import os
from dotenv import load_dotenv

load_dotenv(".env.local")
load_dotenv()

groq_key = os.getenv("GROQ_API_KEY")
print(f"--- DIAGNOSTIC CHECK ---")
print(f"GROQ_API_KEY present: {bool(groq_key)} (Starts with: {groq_key[:8] if groq_key else 'NONE'})")

from livekit.plugins import groq, deepgram, openai
from livekit.agents import inference

async def test_all():
    print("\n1. Testing Groq STT (whisper-large-v3-turbo)...")
    try:
        stt = groq.STT(model="whisper-large-v3-turbo", api_key=groq_key)
        print("[SUCCESS] Groq STT instantiated successfully:", type(stt))
    except Exception as e:
        print("[FAIL] Groq STT failed:", e)

    print("\n2. Testing Groq LLM (llama-3.3-70b-versatile)...")
    try:
        llm = groq.LLM(model="llama-3.3-70b-versatile", api_key=groq_key)
        chat_ctx = llm.chat(history=[{"role": "user", "content": "Hello! Reply with 'LLM working'"}])
        print("[SUCCESS] Groq LLM instantiated successfully:", type(llm))
    except Exception as e:
        print("[FAIL] Groq LLM failed:", e)

    print("\n3. Testing LiveKit Cloud Inference TTS models...")
    for model_name in ["cartesia/sonic-2", "openai/tts-1", "elevenlabs/eleven_multilingual_v2", "deepgram/aura-asteria-en"]:
        try:
            tts_obj = inference.TTS(model=model_name)
            print(f"[SUCCESS] LiveKit inference.TTS for '{model_name}' instantiated: {type(tts_obj)}")
        except Exception as e:
            print(f"[FAIL] LiveKit inference.TTS for '{model_name}' failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_all())
