import asyncio
import os
from dotenv import load_dotenv
from livekit.plugins import cartesia
from livekit.agents import utils

load_dotenv(".env.local")

async def main():
    async with utils.http_context.open():
        print("Testing Direct Cartesia TTS Synthesis with User API Key...")
        c_key = os.getenv("CARTESIA_API_KEY")
        print(f"CARTESIA_API_KEY present: {bool(c_key)} (Starts with: {c_key[:7] if c_key else 'NONE'})")
        
        try:
            tts = cartesia.TTS(api_key=c_key)
            stream = tts.synthesize("Hello! This is Sana speaking directly via Cartesia's ultra fast voice API.")
            frames = 0
            async for event in stream:
                if hasattr(event, "frame") and event.frame:
                    frames += 1
            print(f"[SUCCESS] Direct Cartesia synthesized successfully with {frames} audio frames!")
        except Exception as e:
            print(f"[FAILED] Direct Cartesia failed: {type(e).__name__}: {e}")

if __name__ == "__main__":
    asyncio.run(main())
