# SaNa FastAPI Backend

FastAPI application backend for SaNa Voice Intelligence.

## Features
- **LiveKit Token Service**: Mint short-lived, user-scoped tokens via `POST /v1/livekit/token`.
- **Supabase Authentication**: Verify JWT bearer tokens for secure user isolation.
- **Conversation Endpoints**: Query and update user conversation sessions.

## Setup & Running locally

```bash
# Sync dependencies
uv sync

# Run dev server
uv run uvicorn app.main:app --reload --port 8000
```


## Vercel deployment

This backend can be deployed to **Vercel** by importing the repository as a monorepo project and setting the **Root Directory** to `backend/`.

Required environment variables in Vercel:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `LIVEKIT_AGENT_NAME` (recommended: `voice_agent`)
- `SUPABASE_URL`
- `SUPABASE_JWT_SECRET`
- `BUILD_MODE_ENABLED` (recommended for the hosted demo right now: `false`)

Notes:

- `backend/index.py` is the Vercel FastAPI entrypoint.
- `mobile/` release builds should pass `--dart-define=SANA_BACKEND_URL=https://<your-backend>.vercel.app`.
- `mobile/` release builds can optionally pass `--dart-define=SANA_AGENT_NAME=voice_agent`, though release builds default to `voice_agent`.
- The current Build Mode implementation still depends on server-local files and in-memory state, so hosted Vercel demos should keep `BUILD_MODE_ENABLED=false` until persistent hosted build storage is implemented.


## Railway deployment

For a Build Mode demo, Railway is the preferred backend host over Vercel because the current implementation needs persistent project metadata and writable workspace storage.

Recommended Railway setup:

- Deploy the `backend/` directory as the service root
- Attach a persistent volume and mount it at `/data`
- Set `BUILD_STORAGE_ROOT=/data/sana-builds`
- Set `BUILD_MODE_ENABLED=true`
- Set `LIVEKIT_AGENT_NAME=voice_agent` for the hosted demo path

Required environment variables:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `LIVEKIT_AGENT_NAME`
- `SUPABASE_URL`
- `SUPABASE_JWT_SECRET`
- `BUILD_MODE_ENABLED=true`
- `BUILD_STORAGE_ROOT=/data/sana-builds`

Notes:

- Railway's attached volume is the trusted build root for demo project workspaces.
- The mobile app release build should pass `--dart-define=SANA_BACKEND_URL=https://<your-railway-backend>.up.railway.app`.
- The mobile app release build can optionally pass `--dart-define=SANA_AGENT_NAME=voice_agent`, though release builds default to `voice_agent`.
