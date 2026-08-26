# SANA backend

Three things live here:

1. **FastAPI server** (`app/`) — auth, text chat, conversation history,
   and LiveKit voice tokens. What the mobile app talks to.
2. **Voice agent worker** (`agent/voice_agent.py`) — a separate
   long-running process that joins the LiveKit room as SANA and runs
   the speech-to-text → LLM → text-to-speech pipeline for voice calls.
3. **Database** — users, conversations, and messages (PostgreSQL in
   production, SQLite with zero setup for local dev — see below).

## Architecture

```
Mobile App
  │
  ├─ POST /auth/register, /auth/login ─────► auth_service.py ─► users table
  │
  ├─ POST /chat/message ─────────────────────► chat_service.py
  │                                                 │
  │                                                 ├─► loads mode's system prompt (app/modes/)
  │                                                 ├─► loads prior messages (conversations/messages tables)
  │                                                 ├─► AIService ─► AI provider (LiveKit Inference, or Mock)
  │                                                 └─► saves both messages
  │
  ├─ GET/DELETE /conversations ───────────────► conversations table (yours only)
  │
  └─ POST /api/voice/token ───────────────────► mints a LiveKit token,
                                                  dispatches agent/voice_agent.py
                                                  into the room for real-time voice
```

`AIService` (`app/services/ai_service.py`) is the one seam anything AI-related
goes through — routes and `chat_service.py` never call an AI SDK directly, so
the provider can change without touching either. Two providers ship:

- **`livekit`** (default) — real LLM replies via LiveKit Inference, reusing
  the LiveKit credentials you already have for voice. No separate AI account.
- **`mock`** — canned, mode-flavored responses, zero network calls. What the
  automated test suite uses, and available any time via `AI_PROVIDER=mock`.

The three modes' *behavior* (what Debate/Brainstorm/Build mode does) lives once
in `app/modes/{debate,brainstorm,build}.py` and is shared by both voice and
text chat — only the *output formatting* differs (voice: brief, no markdown;
text: normal formatting, code blocks allowed, especially for Build mode).

## 1. Install dependencies

```bash
cd sana_backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

## 2. Database setup

**Default (zero setup):** `.env`'s `DATABASE_URL` defaults to a local SQLite
file (`sana.db`, created automatically on first run). Nothing to install —
this is what the automated tests and a first local run use.

**PostgreSQL (recommended before anything real):**

1. Install PostgreSQL (postgresql.org, or your OS package manager) and start it.
2. Create a database and user:
   ```sql
   CREATE DATABASE sana;
   CREATE USER sana WITH PASSWORD 'yourpassword';
   GRANT ALL PRIVILEGES ON DATABASE sana TO sana;
   ```
3. Set `DATABASE_URL` in `.env`:
   ```
   DATABASE_URL=postgresql+psycopg2://sana:yourpassword@localhost:5432/sana
   ```
4. Restart the server — tables are created automatically (`app/db/init_db.py`,
   called on startup). No separate migration step for V1 (no Alembic yet —
   see "What's next" at the bottom).

No code changes needed either way — every query in this backend is plain,
portable SQLAlchemy.

## 3. Environment variables

Copy `.env.example` to `.env` and fill in real values. Full reference:

| Variable | Required | Purpose |
|---|---|---|
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | Yes | Voice tokens **and** the default `livekit` AI provider. See existing setup steps below if you don't have these yet. |
| `DATABASE_URL` | No (defaults to SQLite) | `sqlite:///./sana.db` or `postgresql+psycopg2://user:pass@host:5432/dbname` |
| `JWT_SECRET_KEY` | **Yes** | Signs auth tokens. Generate with `python -c "import secrets; print(secrets.token_hex(32))"`. The app refuses to start without one — no insecure default. |
| `JWT_ALGORITHM` | No | Defaults to `HS256` |
| `JWT_EXPIRE_MINUTES` | No | Defaults to 10080 (7 days) |
| `AI_PROVIDER` | No | `livekit` (default, real) or `mock` (canned, offline) |
| `AI_MODEL` | No | Defaults to `google/gemma-4-31b-it` |
| `PORT` | No | Defaults to 8000 |

Never commit `.env` — it's git-ignored. `.env.example` has no real values.

### If you don't have LiveKit credentials yet

1. Go to https://cloud.livekit.io and sign up (free tier).
2. Create a project → **Settings → Keys** → generate a key. Copy the API Key
   and Secret immediately (the secret is only shown once).
3. Note the Project URL (starts with `wss://`).

## 4. Start the server

```bash
uvicorn app.main:app --reload --port 8000
```

Visit `http://localhost:8000/docs` for interactive API docs (Swagger UI) —
generated automatically from the code, always up to date.

For **voice** as well, run the agent worker in a second terminal:

```bash
python agent/voice_agent.py dev
```

(`dev` mode also gives a browser link to talk to the agent directly without
the mobile app, useful for sanity-checking voice on its own.)

## API endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | No | Liveness check |
| POST | `/auth/register` | No | Create an account, returns a token |
| POST | `/auth/login` | No | Returns a token for an existing account |
| POST | `/chat/message` | Yes | Send a message in a mode, get SANA's reply |
| GET | `/conversations` | Yes | List your conversations (no messages, summary only) |
| GET | `/conversations/{id}` | Yes | One conversation with its full message history |
| DELETE | `/conversations/{id}` | Yes | Delete a conversation |
| POST | `/api/voice/token` | No* | Mint a LiveKit token for a voice call |

\* Voice token issuance doesn't check the new JWT auth yet — it predates this
work and takes its own `user_id`/`user_name` in the request body. Wiring it
to require a real JWT too is a natural next step (see bottom of this file).

### Authentication flow

1. `POST /auth/register` (or `/auth/login`) → `{"access_token": "...", "user": {...}}`
2. Send that token on every other request: `Authorization: Bearer <token>`
3. Token is a JWT with `sub` = user id, expires per `JWT_EXPIRE_MINUTES`. No
   refresh-token flow in V1 — a client re-logs in after expiry.

### `POST /chat/message`

Request:
```json
{
  "conversation_id": null,
  "mode": "debate",
  "message": "I think AI will replace software developers."
}
```
- `conversation_id`: `null` to start a new conversation, or an existing one's
  id to continue it. Must belong to the caller and match `mode`, or you get a
  403/400.
- `mode`: `"debate"`, `"brainstorm"`, or `"build"`.

Response:
```json
{
  "conversation_id": "e69d1ddf-...",
  "mode": "debate",
  "response": "That is a bold claim, but it's one that conflates coding with software engineering..."
}
```

## How the three AI modes work

Same architecture as voice, reused for text — one `AIService`, three system
prompts (`app/modes/`):

- **Debate** — challenges assumptions, presents counterarguments, asks
  probing questions, distinguishes evidence from assumption, never
  auto-agrees, stays respectful.
- **Brainstorm** — expands ideas, suggests alternatives, combines related
  ideas, asks creative questions, avoids premature judgment.
- **Build** — clarifies what's being built, breaks it into tasks, recommends
  technologies, designs features, generates real code on request, helps
  debug, tracks the objective across the conversation.

Each mode's full behavioral prompt is in its own file
(`app/modes/debate.py` etc.) if you want to read or tune exactly what SANA is
told to do.

### Build mode can see this project's own code

In Build mode's **text** chat only (not voice), SANA has two read-only tools
(`app/services/build_tools.py`) to look at the real `sana_app`/`sana_backend`
source instead of only discussing it in the abstract:

- `list_project_files(directory)` — list a folder's contents
- `read_project_file(path)` — read one file

Both are backed by `app/services/file_access.py`, which enforces real
boundaries, not just prompt-level politeness — verified by both automated
tests (`tests/test_file_access.py`) and a live test where the model was
directly asked to read `.env` and refused because the tool itself blocked it:

- Only `sana_app/` and `sana_backend/` are reachable at all.
- `.env`, `.git`, `.venv`, `sana.db`, `node_modules`, and similar are denylisted.
- Path-traversal (`../..`) is rejected.
- Files are capped at 50KB (truncated beyond that, not refused).
- **Read-only** — there is no write/delete tool. Modifying files from a chat
  message is a deliberate non-goal for now; ask before extending this.

## Configuring a real AI provider

**Already configured** if you have LiveKit credentials — `AI_PROVIDER=livekit`
(the default) uses them, no extra account needed. To use a different provider
later (OpenAI, Anthropic, etc.), implement `AIProvider` in
`app/services/ai_service.py` (one method: `generate_reply`) and add it to
`get_ai_provider()`'s branch — nothing else in the codebase changes, per the
AIService abstraction.

## How to test

```bash
pytest tests/ -v
```

41 tests, fully offline (uses `AI_PROVIDER`-independent mock injection and an
in-memory SQLite database per test — no real database or AI credentials
needed to run the suite). Covers: registration, login (valid/invalid),
protected-endpoint auth (missing/malformed token), all three modes,
Build mode's file-access tool boundaries (denylist, path traversal, unknown
project names — `tests/test_file_access.py`),
multi-turn conversation history, invalid mode, empty message, conversation
not found, cross-user access being forbidden, and AI-provider failure
handling (timeout/unexpected response/generic outage all map to the right
HTTP status without corrupting the conversation).

### Manually testing register/login/chat

```bash
# Register
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"password123"}'
# → copy the access_token from the response

# Chat (replace TOKEN)
curl -X POST http://localhost:8000/chat/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer TOKEN" \
  -d '{"conversation_id": null, "mode": "debate", "message": "AI will replace developers."}'
```

Or use `http://localhost:8000/docs` — click "Authorize", paste `Bearer TOKEN`,
and every protected endpoint becomes clickable.

## How the mobile app should communicate with the backend

1. Register/login once, store the returned `access_token` securely on-device.
2. Send it as `Authorization: Bearer <token>` on every `/chat/message` and
   `/conversations` request.
3. Text chat: `POST /chat/message` with `conversation_id: null` for a new
   conversation; reuse the returned `conversation_id` for follow-up messages
   in the same thread.
4. To show past conversations: `GET /conversations` for the list, then
   `GET /conversations/{id}` when the user opens one.
5. Voice stays exactly as it already works today: `POST /api/voice/token`,
   then connect via `livekit_client` — unaffected by anything in this update.

The mobile app's own `AppConfig.backendBaseUrl` (`sana_app/lib/core/constants/app_config.dart`)
already points at this backend for voice; the same base URL now also serves
auth/chat/conversations.

## What's next before connecting the mobile frontend for real

- **Wire the Flutter app's mock auth/chat to these real endpoints** — today
  the app's login and text chat are still local mocks (`MockAuthService`,
  `MockConversationService`); this backend is ready but nothing calls it yet
  for auth/chat (only voice-token issuance is already wired).
- **Secure token storage on-device** (e.g. `flutter_secure_storage`) instead
  of wherever the mock session currently lives.
- **Alembic migrations** — `create_all()` is fine for V1's additive schema,
  but any future column change needs a real migration tool, not this.
- **Rate limiting** on `/auth/*` (register/login) — not implemented in V1.
- **Consider requiring a real JWT on `/api/voice/token` too**, instead of a
  self-reported `user_id`, once the app is sending one anyway.
