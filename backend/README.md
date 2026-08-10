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
