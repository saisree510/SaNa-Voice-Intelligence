import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import livekit_router, conversations_router, build_router

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("backend")

app = FastAPI(
    title=settings.APP_NAME,
    version="0.8.0",
    description="SaNa Developer Conversational Intelligence Backend",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register API routers
app.include_router(livekit_router.router)
app.include_router(conversations_router.router)
app.include_router(build_router.router)


@app.get("/health", tags=["Health"])
async def health_check():
    """
    Health check endpoint returning service status.
    """
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "environment": settings.ENVIRONMENT,
    }


@app.get("/v1/status", tags=["Health"])
async def system_status():
    """
    Detailed system status endpoint.
    """
    return {
        "status": "online",
        "livekit_url": settings.LIVEKIT_URL,
        "supabase_url": settings.SUPABASE_URL,
        "version": "0.7.0",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=settings.PORT, reload=True)
