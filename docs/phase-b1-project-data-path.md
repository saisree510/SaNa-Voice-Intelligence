# Phase B1: Project Data Path Audit

## Current path

1. A Build Mode voice request reaches `voice_agent/src/agent.py`.
2. The agent calls `POST /v1/build/projects` on the FastAPI backend with the authenticated user's internal identity.
3. `backend/app/routers/build_router.py` creates a `BuildProjectModel` and writes it through `BuildProjectStore`.
4. `BuildProjectStore` persists the record to `.sana_build_projects.json` under `BUILD_STORAGE_ROOT` and places generated files in the same local filesystem tree.
5. Flutter requests `GET /v1/build/projects` and shows the returned records in the Projects tab.

## Root cause

Railway service filesystems are not durable database storage. A service replacement, redeploy, volume misconfiguration, or an instance change can remove or detach the JSON index and generated workspace. The API and Flutter UI therefore agree on one source during a running instance, but that source is not a reliable persistent source across deployment lifecycle events.

## Legacy handling decision

Existing JSON records are not imported automatically because their ownership and workspace contents cannot be verified after an instance change. They remain quarantined in the local build root and are never exposed across users. Only records created after the Supabase migration and durable-store activation are authoritative Phase B projects.

## Phase B storage target

Supabase stores project metadata, build runs, immutable run events, and generated-file metadata. The FastAPI backend continues to enforce authenticated ownership for every request and uses its server-only service-role key for writes. Generated artifacts remain a separate persistence concern; the Phase B schema reserves `artifact_path` for the secure object-storage handoff.
