import asyncio
import os
from dotenv import load_dotenv
from livekit.agents import inference, utils

load_dotenv(".env.local")

async def main():
    async with utils.http_context.open():
        print("Testing LiveKit Cloud Sandbox Gateway TTS synthesis...")
        print(f"LIVEKIT_URL: {os.getenv('LIVEKIT_URL')}")
        print(f"LIVEKIT_API_KEY present: {bool(os.getenv('LIVEKIT_API_KEY'))}")
        
        for model_name in ["cartesia/sonic-2", "deepgram/aura-asteria-en", "openai/tts-1"]:
            print(f"\n--- Testing {model_name} ---")
            try:
                tts = inference.TTS(model=model_name)
                stream = tts.synthesize("Hello! Testing LiveKit sandbox rate limit.")
                frames = 0
                async for event in stream:
                    if hasattr(event, "frame") and event.frame:
                        frames += 1
                print(f"[SUCCESS] {model_name} synthesized successfully with {frames} audio frames!")
            except Exception as e:
                print(f"[FAILED] {model_name} failed: {type(e).__name__}: {e}")

if __name__ == "__main__":
    asyncio.run(main())
