import asyncio
import os
from dotenv import load_dotenv
from livekit.agents import inference, utils

load_dotenv(".env.local")

async def test_model(model_name):
    print(f"\n--- Testing Sandbox Model: {model_name} ---")
    try:
        tts = inference.TTS(model=model_name)
        stream = tts.synthesize("Hello world!")
        frames = 0
        async for event in stream:
            if hasattr(event, "frame") and event.frame:
                frames += 1
        print(f"[SUCCESS] {model_name} returned {frames} audio frames!")
        return True
    except Exception as e:
        print(f"[FAILED] {model_name}: {e}")
        return False

async def main():
    async with utils.http_context.open():
        print("Checking LiveKit Cloud Inference Gateway Sandbox Rate Limits...\n")
        models = [
            "cartesia/sonic-2",
            "cartesia/sonic",
            "elevenlabs/eleven_multilingual_v2",
            "deepgram/aura-asteria-en",
        ]
        for m in models:
            await test_model(m)

if __name__ == "__main__":
    asyncio.run(main())
