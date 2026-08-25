import asyncio
import json
import logging
import os
import textwrap
from datetime import datetime
from typing import Any, Dict, List, Optional

import urllib.parse
import urllib.request

from dotenv import load_dotenv
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    JobContext,
    TurnHandlingOptions,
    cli,
    inference,
    llm,
    room_io,
)
from livekit.plugins import ai_coustics, groq, silero

logger = logging.getLogger("agent")

load_dotenv(".env.local")
AGENT_NAME = os.getenv("AGENT_NAME", "voice_agent")


import re
import uuid

_offline_projects_store = {}
_room_chat_memory: Dict[str, list] = {}


def get_agent_backend_shared_secret() -> str:
    return (os.getenv("AGENT_BACKEND_SHARED_SECRET") or os.getenv("LIVEKIT_API_SECRET") or "").strip()


def build_backend_headers(*, request_user_id: Optional[str] = None, request_user_email: Optional[str] = None) -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    shared_secret = get_agent_backend_shared_secret()
    if request_user_id and shared_secret:
        headers["X-Sana-Agent-User-Id"] = request_user_id
        headers["X-Sana-Agent-Secret"] = shared_secret
        if request_user_email:
            headers["X-Sana-Agent-User-Email"] = request_user_email
    return headers


def extract_participant_user_context(participant: Any) -> dict[str, Optional[str]]:
    metadata_user_id = None
    mode = None
    if getattr(participant, "metadata", None):
        try:
            meta = json.loads(participant.metadata)
            if isinstance(meta, dict):
                metadata_user_id = meta.get("user_id")
                mode = meta.get("mode")
        except Exception:
            pass

    identity = getattr(participant, "identity", "") or ""
    identity_user_id = identity[5:] if identity.startswith("user-") else None
    # The backend signs participant identity. Participant metadata can be changed
    # by the client, so it must never override identity for authorization.
    user_id = identity_user_id or metadata_user_id
    return {
        "user_id": user_id,
        "mode": mode,
        "identity": identity or None,
    }


def get_latest_pending_offline_project_id() -> Optional[str]:
    pending_projects = [
        (project_id, project_data.get("created_at", ""))
        for project_id, project_data in _offline_projects_store.items()
        if isinstance(project_data, dict) and project_data.get("status") == "plan_generated"
    ]
    if not pending_projects:
        return None
    pending_projects.sort(key=lambda item: item[1], reverse=True)
    return pending_projects[0][0]

RESTORED_MEMORY_MAX_MESSAGES = 40
RESTORED_MEMORY_MAX_CONTENT_CHARS = 4000


def get_backend_url() -> str:
    return os.getenv("BACKEND_URL", "").strip()


def is_remote_backend_url(backend_url: str) -> bool:
    if not backend_url:
        return False
    try:
        hostname = (urllib.parse.urlparse(backend_url).hostname or "").strip().lower()
    except Exception:
        return True
    return hostname not in {"", "127.0.0.1", "localhost"}


def get_local_build_workspaces_root() -> str:
    configured_root = os.getenv("SANA_BUILD_WORKSPACES_ROOT", "").strip()
    if configured_root:
        return os.path.abspath(configured_root)
    return os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "drafts")
    )


def build_local_draft_workspace(title: str, *, project_id: Optional[str] = None) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_-]", "_", title.lower()).strip("_")
    slug = slug or (project_id or f"project_{uuid.uuid4().hex[:8]}")
    return os.path.abspath(os.path.join(get_local_build_workspaces_root(), slug))


def build_project_download_url(backend_url: str, project_id: str) -> str:
    base = backend_url.rstrip("/")
    return f"{base}/v1/build/projects/{project_id}/download"


def _safe_architecture_id(text: str, *, prefix: str = "arch") -> str:
    slug = re.sub(r"[^a-z0-9_-]", "-", text.lower()).strip("-_")
    slug = re.sub(r"-+", "-", slug)[:40].strip("-_")
    if not slug or not slug[0].isalpha():
        slug = f"{prefix}-{slug or uuid.uuid4().hex[:8]}"
    return slug[:64]


def _infer_overview_components(specification: str) -> list[dict[str, str]]:
    text = specification.lower()
    backend_requested = any(term in text for term in ("api", "backend", "server", "fastapi", "endpoint"))
    components: list[dict[str, str]] = [
        {"id": "frontend", "name": "Project UI", "type": "frontend", "technology": "HTML/CSS/JavaScript"},
        {
            "id": "api",
            "name": "FastAPI Backend" if backend_requested else "Application Logic",
            "type": "service",
            "technology": "Python" if backend_requested else "Browser JavaScript",
        },
    ]
    if any(term in text for term in ("database", "data", "store", "save", "persist", "supabase", "login", "auth")):
        components.append({"id": "database", "name": "Supabase PostgreSQL", "type": "database"})
    if any(term in text for term in ("ai", "agent", "voice", "livekit", "llm", "speech")):
        components.append({"id": "agent", "name": "Soul Voice Agent", "type": "agent"})
    return components


def _build_architecture_operations(architecture_id: str, components: list[dict[str, str]]) -> list[dict[str, Any]]:
    operations: list[dict[str, Any]] = []
    sequence = 1
    for component in components:
        operations.append(
            {
                "sequence_number": sequence,
                "idempotency_key": f"{architecture_id}-add-{component['id']}",
                "operation": {
                    "operation_id": f"op-{sequence}",
                    "architecture_id": architecture_id,
                    "base_version": 1,
                    "operation_type": "add_node",
                    "actor": "soul_agent",
                    "payload": {"component": component},
                },
            }
        )
        sequence += 1

    for source, target, protocol in (
        ("frontend", "api", "HTTPS"),
        ("api", "database", "SQL"),
        ("frontend", "agent", "LiveKit"),
        ("agent", "api", "HTTPS"),
    ):
        if not any(component["id"] == source for component in components):
            continue
        if not any(component["id"] == target for component in components):
            continue
        connection_id = f"{source}-{target}"
        operations.append(
            {
                "sequence_number": sequence,
                "idempotency_key": f"{architecture_id}-connect-{connection_id}",
                "operation": {
                    "operation_id": f"op-{sequence}",
                    "architecture_id": architecture_id,
                    "base_version": 1,
                    "operation_type": "connect_nodes",
                    "actor": "soul_agent",
                    "payload": {
                        "connection": {
                            "id": connection_id,
                            "source_id": source,
                            "target_id": target,
                            "protocol": protocol,
                        }
                    },
                },
            }
        )
        sequence += 1
    return operations


@llm.function_tool
async def create_overview_architecture(
    title: str,
    specification: str,
    *,
    request_user_id: Optional[str] = None,
    request_user_email: Optional[str] = None,
    conversation_id: Optional[str] = None,
    project_id: Optional[str] = None,
    on_created: Optional[Any] = None,
) -> str:
    """Create a persistent Overview Architecture Blueprint and progressive canvas operations."""
    configured_backend_url = get_backend_url()
    backend_url = configured_backend_url or "http://127.0.0.1:8000"
    architecture_id = _safe_architecture_id(f"arch-{title}-{uuid.uuid4().hex[:6]}")
    components = _infer_overview_components(specification)

    try:
        create_payload: dict[str, Any] = {
            "title": title,
            "conversation_id": conversation_id,
            "project_id": project_id,
            "blueprint": {
                "architecture_id": architecture_id,
                "project_id": project_id if project_id and re.match(r"^[a-z][a-z0-9_-]{0,63}$", project_id) else None,
                "version": 1,
                "components": [],
                "connections": [],
            },
        }
        req = urllib.request.Request(
            f"{backend_url}/v1/architectures",
            data=json.dumps(create_payload).encode("utf-8"),
            headers=build_backend_headers(request_user_id=request_user_id, request_user_email=request_user_email),
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            created = json.loads(resp.read().decode("utf-8"))
            architecture_id = created.get("architecture_id") or architecture_id

        # Notify client of architecture creation before publishing canvas events
        if on_created:
            await on_created(architecture_id)
            await asyncio.sleep(0.8) # Wait for client to connect to WebSocket

        operations = _build_architecture_operations(architecture_id, components)
        accepted = 0
        for operation_payload in operations:
            req = urllib.request.Request(
                f"{backend_url}/v1/architectures/{architecture_id}/events",
                data=json.dumps(operation_payload).encode("utf-8"),
                headers=build_backend_headers(request_user_id=request_user_id, request_user_email=request_user_email),
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                json.loads(resp.read().decode("utf-8"))
                accepted += 1
            
            # Progressively stream each event at a human-visible cadence
            await asyncio.sleep(1.0)

        component_names = ", ".join(component["name"] for component in components)
        return (
            f"Architecture Blueprint created with ID {architecture_id}. "
            f"Drew {len(components)} components and {accepted - len(components)} connections progressively: {component_names}."
        )
    except Exception as e:
        logger.warning(f"Error creating overview architecture: {e}")
        return (
            f"I could not create the live architecture for '{title}' through the configured backend. "
            "No canvas operations were saved. Please retry after verifying the backend and user session."
        )



def normalize_restored_messages(
    messages: Any,
    *,
    max_messages: int = RESTORED_MEMORY_MAX_MESSAGES,
) -> list[dict[str, str]]:
    if not isinstance(messages, list):
        return []
    normalized: list[dict[str, str]] = []
    for item in messages:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = item.get("content")
        if role not in {"user", "assistant"} or not isinstance(content, str):
            continue
        content = content.strip()
        if not content:
            continue
        message_id = item.get("id")
        if not isinstance(message_id, str) or not message_id.strip():
            message_id = f"restored-{uuid.uuid4().hex}"
        normalized.append(
            {
                "id": message_id,
                "role": role,
                "content": content[-RESTORED_MEMORY_MAX_CONTENT_CHARS:],
            }
        )
    return normalized[-max_messages:]


def build_restored_chat_context(
    existing_chat_ctx: llm.ChatContext,
    messages: Any,
) -> llm.ChatContext:
    del existing_chat_ctx
    chat_ctx = llm.ChatContext()
    for message in normalize_restored_messages(messages):
        chat_ctx.add_message(
            id=message["id"],
            role=message["role"],
            content=message["content"],
        )
    return chat_ctx


@llm.function_tool
async def create_build_project_plan(title: str, specification: str, *, request_user_id: Optional[str] = None, request_user_email: Optional[str] = None) -> str:
    """Draft a new build project plan and return the project ID and generated plan summary."""
    configured_backend_url = get_backend_url()
    backend_url = configured_backend_url or "http://127.0.0.1:8000"
    requested_workspace = None
    if not is_remote_backend_url(backend_url):
        requested_workspace = build_local_draft_workspace(title)

    try:
        payload = {
            "title": title,
            "specification": specification,
        }
        if requested_workspace:
            payload["workspace_path"] = requested_workspace

        req_data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{backend_url}/v1/build/projects",
            data=req_data,
            headers=build_backend_headers(request_user_id=request_user_id, request_user_email=request_user_email),
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            pid = data.get("project_id")
            architecture_id = data.get("architecture_id")
            summary = data.get("plan_summary")
            actual_workspace = data.get("workspace_path") or requested_workspace or "backend-managed workspace"
            architecture_text = f" Architecture ID: {architecture_id}." if architecture_id else ""
            return (
                f"Project created successfully with ID {pid}. "
                f"Workspace: {actual_workspace}.{architecture_text} Plan Summary: {summary}"
            )
    except Exception as e:
        logger.warning(f"Error calling create_build_project_plan backend endpoint: {e}")
        if configured_backend_url and is_remote_backend_url(configured_backend_url):
            return (
                f"I could not draft '{title}' through the configured backend. "
                "No project workspace was created, so no files were saved. "
                "Please verify the hosted backend deployment and Build Mode storage configuration."
            )

        fallback_pid = f"proj-{uuid.uuid4().hex[:8]}"
        draft_workspace = requested_workspace or build_local_draft_workspace(title, project_id=fallback_pid)
        _offline_projects_store[fallback_pid] = {
            "title": title,
            "specification": specification,
            "workspace_path": draft_workspace,
            "status": "plan_generated",
            "created_at": datetime.utcnow().isoformat(),
        }
        return (
            f"Project plan drafted for '{title}' with ID {fallback_pid}. "
            f"Draft workspace: '{draft_workspace}'. Awaiting explicit user approval before execution."
        )


@llm.function_tool
async def approve_and_execute_build_project(project_id: Optional[str] = None, *, request_user_id: Optional[str] = None, request_user_email: Optional[str] = None) -> str:
    """Explicitly approve and trigger execution for a drafted build project. Call this without a project ID when the user says yes to the latest pending build plan."""
    configured_backend_url = get_backend_url()
    backend_url = configured_backend_url or "http://127.0.0.1:8000"
    approval_target = project_id or "latest pending build project"
    approval_url = (
        f"{backend_url}/v1/build/projects/{project_id}/approve"
        if project_id
        else f"{backend_url}/v1/build/projects/approve-latest"
    )
    try:
        req = urllib.request.Request(
            approval_url,
            data=b"{}",
            headers=build_backend_headers(request_user_id=request_user_id, request_user_email=request_user_email),
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            resolved_project_id = data.get("project_id") or project_id
            summary = data.get("result_summary") or "Build execution completed."
            workspace = data.get("workspace_path")
            generated_files = data.get("generated_files") or []
            download_url = data.get("download_url")
            download_path = data.get("download_path")
            extras = []
            if workspace:
                extras.append(f"Workspace: {workspace}.")
            if generated_files:
                extras.append(f"Files: {', '.join(generated_files)}.")
            if download_url:
                extras.append(f"Download: {download_url}.")
            elif configured_backend_url and download_path and resolved_project_id:
                extras.append(
                    f"Download: {build_project_download_url(configured_backend_url, resolved_project_id)}."
                )
            extra_text = f" {' '.join(extras)}" if extras else ""
            return f"Execution result summary: {summary}{extra_text}"
    except Exception as e:
        logger.warning(
            f"Error calling approve_and_execute_build_project backend endpoint: {e}."
        )
        if configured_backend_url and is_remote_backend_url(configured_backend_url):
            return (
                f"Build execution failed for {approval_target} through the configured backend. "
                "No files were saved to your PC because this agent is running remotely. "
                "Please verify the hosted backend deployment and retry."
            )

        resolved_project_id = project_id or get_latest_pending_offline_project_id()
        if not resolved_project_id:
            return (
                "There is no pending build project to approve yet. "
                "I need to draft a build plan before I can execute it."
            )

        offline_data = _offline_projects_store.get(resolved_project_id, {})
        workspace = offline_data.get("workspace_path") or build_local_draft_workspace(
            title=offline_data.get("title") or "Build Target",
            project_id=resolved_project_id,
        )
        spec = offline_data.get("specification") or "Scaffold project"
        title = offline_data.get("title") or "Build Target"

        import re

        os.makedirs(workspace, exist_ok=True)
        package_name = re.sub(r"[^a-zA-Z0-9_]", "_", title.lower()).strip("_") or "build_target"
        if package_name[0].isdigit():
            package_name = f"project_{package_name}"

        files_to_write = {
            "project_spec.md": (
                f"# Project Blueprint & Specification: {title}\n\n"
                f"**Specification:** {spec}\n"
                "**Status:** Executed\n"
            ),
            "README.md": (
                f"# {title}\n\n"
                "Generated locally by Soul Build Mode fallback.\n\n"
                "## Request\n"
                f"{spec}\n"
            ),
            ".gitignore": "__pycache__/\n*.pyc\n.pytest_cache/\n.venv/\n.env\n",
            "pyproject.toml": (
                "[project]\n"
                f'name = "{package_name.replace("_", "-")}"\n'
                'version = "0.1.0"\n'
                'description = "Generated by Soul Build Engine fallback"\n'
                'requires-python = ">=3.11"\n'
            ),
            "main.py": (
                f"from src.{package_name}.app import main\n\n"
                "if __name__ == '__main__':\n"
                "    main()\n"
            ),
            os.path.join("src", package_name, "__init__.py"): '"""Generated fallback package."""\n',
            os.path.join("src", package_name, "app.py"): (
                f"PROMPT = {spec!r}\n\n"
                "def build_summary() -> str:\n"
                '    return f"Soul generated fallback scaffold for: {PROMPT}"\n\n'
                "def main() -> None:\n"
                "    print(build_summary())\n"
            ),
            os.path.join("tests", "test_app.py"): (
                f"from src.{package_name}.app import build_summary\n\n"
                "def test_build_summary_mentions_generated_scaffold():\n"
                "    summary = build_summary()\n"
                '    assert "generated fallback scaffold" in summary\n'
            ),
        }

        for relative_path, content in files_to_write.items():
            absolute_path = os.path.join(workspace, relative_path)
            os.makedirs(os.path.dirname(absolute_path), exist_ok=True)
            with open(absolute_path, "w", encoding="utf-8") as f:
                f.write(content)

        offline_data["status"] = "completed"
        offline_data["completed_at"] = datetime.utcnow().isoformat()
        _offline_projects_store[resolved_project_id] = offline_data

        return (
            f"Build execution completed for project {resolved_project_id}. "
            f"Generated files {', '.join(sorted(files_to_write.keys()))} in workspace '{workspace}'."
        )

def get_greeting_for_mode(mode: str) -> str:
    openings = {
        "debate": (
            "Bring me your strongest argument. I am ready to tear into the weak spots, "
            "so what are we debating?"
        ),
        "brainstorm": (
            "Let us make some sparks. Give me the rough idea, and we will turn it into "
            "something bold. What are we exploring?"
        ),
        "build": (
            "Let us build this properly. Tell me what you want to create, and I will help "
            "shape the plan before we touch the code. What are we making?"
        ),
        "general": "Hey, I am Soul. What is on your mind today?",
    }
    return openings.get(mode.lower(), openings["general"])


def get_resume_opening_instructions(mode: str) -> str:
    normalized_mode = mode.lower()
    mode_direction = {
        "debate": (
            "Stay in debate mode: sound fierce and confident, challenge the latest claim "
            "or unresolved assumption, and invite the user to defend it."
        ),
        "brainstorm": (
            "Stay in brainstorm mode: sound energetic and imaginative, reconnect to the "
            "most promising idea, and invite the next creative step."
        ),
        "build": (
            "Stay in build mode: sound like a decisive but approachable tech lead, name the "
            "current requirement or decision, and ask for the next planning step without "
            "executing anything."
        ),
        "general": (
            "Stay in general mode: sound warm and conversational, reconnect to the latest "
            "topic, and invite the user to continue."
        ),
    }.get(normalized_mode, "Stay warm, conversational, and helpful.")
    return (
        "The selected chat has a restored conversation history. Give one brief reopening "
        "of no more than two spoken sentences. Mention one specific topic, decision, or "
        "unresolved point from the latest restored turns, then ask one natural question "
        f"that continues the work. {mode_direction} Do not give a generic greeting, recap "
        "the whole chat, or claim you cannot remember it."
    )


def get_mode_instructions(mode: str = "general") -> str:
    today_str = datetime.now().strftime("%B %d, %Y")
    normalized_mode = mode.lower()

    if normalized_mode == "debate":
        mode_header = """\
# MANDATORY ACTIVE ROLE: DEBATE SPARRING PARTNER
You are Soul, an unyielding, fierce, and highly analytical technical sparring partner. You are currently in DEBATE MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- YOU MUST NEVER AGREE WITH THE USER AT ANY POINT IN THIS CONVERSATION.
- NEVER SAY "THAT IS A FAIR POINT", "YOU HAVE A POINT", "GOOD POINT", OR "I AGREE". DO NOT CONCEDE GROUND.
- EVEN IF THE USER PRESENTS A STRONG ARGUMENT, IMMEDIATELY PUSH BACK WITH A COUNTER-EXAMPLE, FLAWS, HIDDEN COSTS, OR SCALABILITY RISKS.
- START EVERY RESPONSE DIRECTLY WITH A REBUTTAL OR SKEPTICAL CHALLENGE.
- Force the user to continuously defend their reasoning and choices.
- Sound fierce, quick, and human rather than robotic: use sharp conversational phrasing, vary your challenges, and press one weak point at a time.
- If asked what mode you are in, answer clearly: "I am in Debate Mode."
"""
    elif normalized_mode == "brainstorm":
        mode_header = """\
# MANDATORY ACTIVE ROLE: CREATIVE BRAINSTORMING PARTNER
You are Soul, an energetic, creative co-founder and ideation partner. You are currently in BRAINSTORM MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- ALWAYS PITCH BOLD, UNVENTURED CREATIVE IDEAS AND HELP EXPAND INCOMPLETE CONCEPTS.
- NEVER GIVE PASSIVE, GENERIC ASSISTANT REPLIES OR SIMPLE AGREEMENTS.
- FOR EVERY USER STATEMENT, OFFER 2 TO 3 INNOVATIVE FEATURE VARIATIONS OR UNCONVENTIONAL ANGLES.
- ASK AT LEAST ONE PROBING QUESTION ABOUT TARGET USERS, KEY FEATURES, TECH STACK OPTIONS, OR PRODUCT VISION.
- Sound like an excited creative partner in a real conversation: react directly to the user's idea before expanding it, and avoid repetitive canned enthusiasm.
- BRAINSTORM TO BUILD HANDOFF: When the user expresses clear intent to build (e.g., "Let's build it", "Make this a project", "I want to start building"), acknowledge their decision warmly, state a 2-sentence summary of the vision, and ask if they are ready to transition to Build Mode.
- If asked what mode you are in, answer clearly: "I am in Brainstorm Mode."
"""
    elif normalized_mode == "build":
        mode_header = """\
# MANDATORY ACTIVE ROLE: TECH LEAD & BUILD ORCHESTRATOR
You are Soul, a decisive, precise Tech Lead and Build Orchestrator. You are currently in BUILD MODE.

YOUR MANDATORY BEHAVIOR FOR EVERY SINGLE TURN:
- HELP THE USER DEFINE CLEAR PROJECT REQUIREMENTS, SPECIFICATIONS, AND ARCHITECTURE PLANS.
- Sound like an approachable, decisive tech lead in a working session: refer naturally to earlier decisions and move the discussion forward one concrete choice at a time.
- When the user asks to build or create a project/app, call create_build_project_plan_tool with a concise title and finalized specification; that tool also creates the linked live architecture canvas.
- When the user asks only to show, draw, map, or update an architecture/canvas/technical plan, call create_overview_architecture_tool with a concise title and the finalized specification before saying it is available on the canvas.
- EXPLICIT APPROVAL GATE: NEVER TRIGGER CODE EXECUTION OR FILE MUTATION AUTOMATICALLY. ALWAYS PRESENT THE PLAN CLEARLY AND ASK FOR THE USER'S EXPLICIT APPROVAL ("Are you ready to approve and execute this plan?").
- WHEN BUILD EXECUTION FINISHES, SUMMARIZE THE GENERATED FILES AND VERIFICATION RESULTS IN 2 TO 3 CLEAR, DIRECT SENTENCES.
- If asked what mode you are in, answer clearly: "I am in Build Mode."
"""
    else:
        mode_header = """\
# MANDATORY ACTIVE ROLE: GENERAL ASSISTANT
You are Soul, an intelligent, friendly, and reliable developer assistant. You are currently in GENERAL MODE.

YOUR MANDATORY BEHAVIOR:
- Provide clear, helpful, and direct answers to developer questions.
- Keep replies brief, warm, conversational, and professional. Respond directly to what the user just said and refer naturally to relevant earlier context.
- If asked what mode you are in, answer clearly: "I am in General Mode."
"""

    grounding_and_rules = f"""\
# Temporal Grounding
- Today's date is {today_str}.
- The current President of the United States is Donald Trump (who assumed office for his second term in January 2025).

# Conversational continuity
- Speak like an engaged human collaborator, not a scripted menu or support bot.
- Preserve the active mode's personality on every turn while varying sentence openings and phrasing.
- Use relevant details from the conversation naturally; do not repeatedly summarize or announce that you remember them.

# Output rules (Voice Output)
- Respond in plain text only. Never use JSON, markdown, bullet points, numbered lists, tables, code blocks, emojis, or formatting tags.
- Keep replies brief: one to three sentences max per response. Ask one question at a time.
- Spell out numbers, phone numbers, or email addresses.
- Omit `https://` when listing URLs.

# Guardrails
- Stay within safe, lawful, and appropriate use; decline harmful requests.
- For medical, legal, or financial topics, provide general info only.
"""

    return f"{mode_header}\n{grounding_and_rules}"


class Assistant(Agent):
    def __init__(self, mode: str = "general") -> None:
        self.current_mode = mode
        super().__init__(
            llm=inference.LLM(model="google/gemma-4-31b-it"),
            instructions=get_mode_instructions(mode),
        )

    async def set_mode(self, new_mode: str) -> None:
        self.current_mode = new_mode
        new_inst = get_mode_instructions(new_mode)
        self._instructions = new_inst
        await self.update_instructions(new_inst)
        logger.info(f"Updated Assistant instructions for mode: {new_mode}")


server = AgentServer()


@server.rtc_session(agent_name=AGENT_NAME)
async def my_agent(ctx: JobContext):
    groq_key = os.getenv("GROQ_API_KEY")
    logger.info(
        f"Connecting session in room '{ctx.room.name}' as agent '{AGENT_NAME}'. GROQ_API_KEY present: {bool(groq_key)}. Using LiveKit Inference for Cartesia TTS."
    )

    assistant = Assistant(mode="general")
    greeting_spoken = False
    current_build_user_id: Optional[str] = None
    current_build_user_email: Optional[str] = None

    @llm.function_tool
    async def create_build_project_plan_tool(title: str, specification: str) -> str:
        plan_result = await create_build_project_plan(
            title,
            specification,
            request_user_id=current_build_user_id,
            request_user_email=current_build_user_email,
        )
        project_match = re.search(r"Project created successfully with ID ([A-Za-z0-9_-]+)", plan_result)
        project_id = project_match.group(1) if project_match else None
        architecture_match = re.search(r"Architecture ID: ([A-Za-z0-9_-]+)", plan_result)
        architecture_id = architecture_match.group(1) if architecture_match else None

        if architecture_id:
            try:
                payload = json.dumps({
                    "type": "architecture_created",
                    "architecture_id": architecture_id,
                    "project_id": project_id,
                })
                if ctx.room.local_participant:
                    await ctx.room.local_participant.publish_data(payload.encode("utf-8"))
                    logger.info(f"Published architecture_created packet to LiveKit room for {architecture_id}")
            except Exception as pe:
                logger.warning(f"Failed to publish architecture_created room packet: {pe}")

        return plan_result

    @llm.function_tool
    async def approve_and_execute_build_project_tool(project_id: Optional[str] = None) -> str:
        return await approve_and_execute_build_project(
            project_id,
            request_user_id=current_build_user_id,
            request_user_email=current_build_user_email,
        )

    @llm.function_tool
    async def create_overview_architecture_tool(title: str, specification: str, conversation_id: Optional[str] = None, project_id: Optional[str] = None) -> str:
        async def on_created_callback(arch_id: str):
            try:
                payload = json.dumps({
                    "type": "architecture_created",
                    "architecture_id": arch_id,
                })
                if ctx.room.local_participant:
                    await ctx.room.local_participant.publish_data(payload.encode("utf-8"))
                    logger.info(f"Published architecture_created packet to LiveKit room for {arch_id}")
            except Exception as pe:
                logger.warning(f"Failed to publish architecture_created room packet: {pe}")

        return await create_overview_architecture(
            title,
            specification,
            request_user_id=current_build_user_id,
            request_user_email=current_build_user_email,
            conversation_id=conversation_id,
            project_id=project_id,
            on_created=on_created_callback,
        )


    session = AgentSession(
        stt=groq.STT(model="whisper-large-v3-turbo", api_key=groq_key),
        llm=groq.LLM(model="llama-3.3-70b-versatile", api_key=groq_key),
        tts=inference.TTS(
            model="cartesia/sonic-3",
            voice="f786b574-daa5-4673-aa0c-cbe3e8534c02",
            language="en",
        ),
        vad=silero.VAD.load(),
        tools=[create_build_project_plan_tool, approve_and_execute_build_project_tool, create_overview_architecture_tool],
        preemptive_generation=False,
    )

    await session.start(
        agent=assistant,
        room=ctx.room,
    )

    current_applied_mode = None
    restored_conversation_id: Optional[str] = None
    restore_lock = asyncio.Lock()

    async def restore_conversation(payload: dict[str, Any]) -> None:
        nonlocal restored_conversation_id, greeting_spoken
        conversation_id = payload.get("conversation_id")
        if not isinstance(conversation_id, str) or not conversation_id:
            return
        async with restore_lock:
            if restored_conversation_id == conversation_id:
                return
            restored_messages = normalize_restored_messages(payload.get("messages"))
            if not restored_messages:
                return
            greeting_spoken = True
            restored_mode = payload.get("mode", current_applied_mode or "general")
            if not isinstance(restored_mode, str):
                restored_mode = "general"
            await apply_mode(restored_mode)
            chat_ctx = build_restored_chat_context(
                assistant.chat_ctx, restored_messages
            )
            await assistant.update_chat_ctx(chat_ctx)
            _room_chat_memory[ctx.room.name] = restored_messages
            restored_conversation_id = conversation_id
            session.generate_reply(
                instructions=get_resume_opening_instructions(restored_mode),
                allow_interruptions=True,
            )

    async def apply_mode(new_mode: str):
        nonlocal current_applied_mode
        if current_applied_mode == new_mode:
            return
        current_applied_mode = new_mode
        logger.info(f"Applying mode switch: '{new_mode}'")
        await assistant.set_mode(new_mode)

        # Update system message IN PLACE at index 0 of session.history
        new_instructions = get_mode_instructions(new_mode)
        if hasattr(session, "history") and session.history:
            try:
                system_found = False
                for msg in session.history.messages():
                    if getattr(msg, "role", None) == "system":
                        msg.content = [new_instructions]
                        system_found = True
                        logger.info(
                            f"Updated in-place system message at index 0 for mode: '{new_mode}'"
                        )
                        break
                if not system_found:
                    session.history.add_message(
                        role="system",
                        content=new_instructions,
                    )
            except Exception as e:
                logger.warning(f"Failed to update session.history system prompt: {e}")

    async def speak_greeting(mode: str):
        nonlocal greeting_spoken
        await asyncio.sleep(0.8)
        if greeting_spoken:
            return
        greeting_spoken = True
        greeting = get_greeting_for_mode(mode)
        logger.info(f"Speaking initial mode greeting for mode '{mode}': '{greeting}'")
        try:
            await session.say(greeting)
        except Exception as e:
            logger.warning(f"Failed to speak initial mode greeting: {e}", exc_info=True)

    @ctx.room.on("data_received")
    def on_data_received(data_packet):
        try:
            payload = json.loads(data_packet.data.decode("utf-8"))
            if payload.get("type") == "mode_switch":
                new_mode = payload.get("mode", "general")
                is_initial = payload.get("is_initial", False)
                if current_applied_mode == new_mode:
                    return
                logger.info(
                    f"Received mode switch payload: {new_mode} (is_initial: {is_initial})"
                )
                asyncio.create_task(apply_mode(new_mode))

                if is_initial:
                    asyncio.create_task(speak_greeting(new_mode))
            elif payload.get("type") == "conversation_restore":
                asyncio.create_task(restore_conversation(payload))
        except Exception as e:
            logger.warning(f"Error parsing data packet in voice agent: {e}")

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, old_metadata, new_metadata):
        nonlocal current_build_user_id, current_build_user_email
        logger.info(f"Participant metadata changed: {new_metadata}")
        participant_ctx = extract_participant_user_context(participant)
        if participant_ctx.get("user_id"):
            current_build_user_id = participant_ctx["user_id"]
            current_build_user_email = None
            logger.info(f"Updated build user context from metadata: {current_build_user_id}")
        if new_metadata:
            try:
                meta = json.loads(new_metadata)
                mode = meta.get("mode", "general")
                asyncio.create_task(apply_mode(mode))
            except Exception as e:
                logger.warning(f"Error parsing updated metadata: {e}")

    @ctx.room.on("participant_connected")
    def on_participant_connected(participant):
        nonlocal current_build_user_id, current_build_user_email
        logger.info(f"Participant connected: {participant.identity}")
        mode = "general"
        participant_ctx = extract_participant_user_context(participant)
        if participant_ctx.get("user_id"):
            current_build_user_id = participant_ctx["user_id"]
            current_build_user_email = None
            logger.info(f"Initialized build user context from participant: {current_build_user_id}")
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                mode = meta.get("mode", mode)
            except Exception:
                pass
        asyncio.create_task(apply_mode(mode))
        asyncio.create_task(speak_greeting(mode))

    # Fallback greeting if participant is already connected upon agent join
    for p in ctx.room.remote_participants.values():
        participant_ctx = extract_participant_user_context(p)
        if participant_ctx.get("user_id"):
            current_build_user_id = participant_ctx["user_id"]
            current_build_user_email = None
            logger.info(f"Recovered build user context from existing participant: {current_build_user_id}")
        mode = "general"
        if p.metadata:
            try:
                meta = json.loads(p.metadata)
                mode = meta.get("mode", mode)
            except Exception:
                pass
        asyncio.create_task(apply_mode(mode))
        asyncio.create_task(speak_greeting(mode))


if __name__ == "__main__":
    cli.run_app(server)
