# Soul — Product Requirements Document

**Document version:** 0.6.0  
**Date:** 2026-08-21  
**Status:** Draft for founder review  
**Product stage:** Web MVP expansion  
**Previous product name:** SaNa  
**Primary audience:** Founder, product team, designers and implementers

---

## 1. Revision summary

Version 0.6.0 locks the product and technical decisions for Soul's **Live Architecture Canvas** while preserving the working SaNa-to-Soul foundation and the phase-by-phase implementation plan introduced in v0.5.1.

This is not a restart. The verified Flutter, FastAPI, Supabase and LiveKit implementation remains the foundation. The next release adds:

- Complete Soul branding
- Strict authenticated user-data isolation
- Public web deployment
- A persistent real-time architecture canvas
- Genuine DeepCode-backed project generation
- A complete Projects workspace
- Planning, build, review and validation workflows
- An embedded, open-source Excalidraw canvas with Figma-inspired visual polish
- A canonical Architecture Blueprint independent of any rendering library
- Validated, progressive WebSocket drawing operations and replayable canvas history
- Immutable architecture approval linked to DeepCode BuildRuns

### Implementation status update: Phase A through A6

**Updated:** 2026-08-21  
**Overall Phase A status:** Complete. A0-A6 are complete.

| Subphase | Status | Verified outcome |
|---|---|---|
| A0 - Repository and deployment snapshot | Complete | Branch, upstream, dirty worktree, deployed Railway backend, Soul LiveKit project, agent state, tests and secret exposure were audited without changing production state. |
| A1 - Authenticated ownership hardening | Complete | Backend and Flutter ownership controls were committed and pushed in `4280603`; the production-safe Supabase migration was prepared and backend tests passed. |
| A2 - Production RLS migration | Complete | Supabase migration was applied. RLS and authenticated policies for conversations, messages and conversation events were verified; invalid ownership rows were zero. |
| A3 - Two-account browser and voice verification | Complete | User A and User B were verified to see only their own data. Railway validates Supabase sessions, mints Soul LiveKit tokens, dispatches `voice_agent`, and the hosted agent joins and responds in the browser room. |
| A4 - Authenticated voice and Build Mode browser test | Complete | On the public web app, authenticated voice worked and a real Build Mode conversation created a project that User A could see in their Projects tab. Railway's isolated create-and-list persistence check also passed. |
| A5 - Soul rebrand pass | Complete | Web title and metadata, authentication, onboarding, home, voice conversation, project generation attribution, backend metadata and hosted-agent prompts now identify as Soul. Existing Sana-named storage keys and authenticated integration headers remain as compatibility internals. Flutter analysis and 14 tests passed; backend tests passed. |
| A6 - Public Flutter Web deployment | Complete | GitHub Pages serves the production Flutter Web build over HTTPS at `https://saisree510.github.io/SaNa-Voice-Intelligence/`, with repository-base routing and an SPA fallback. Public-browser verification passed for sign-in, refresh, voice connection, Projects, History, microphone permission and sign-out. |

**A3 decisions and findings:**

- Legacy local Build Project drafts with test or legacy owner IDs remain quarantined and are not exposed to either authenticated user.
- Failed connection attempts no longer create empty conversation records before LiveKit connects.
- Flutter Web now displays safe token/session connection errors instead of silently returning to Home.
- Railway must retain matching Soul LiveKit credentials plus `SUPABASE_URL` and `SUPABASE_ANON_KEY`; do not configure a legacy `SUPABASE_JWT_SECRET` for the migrated Supabase signing-key setup.
- `AGENT_BACKEND_SHARED_SECRET` is synchronized between Railway and the hosted agent for protected backend calls. Its value is not recorded in this document or Git.

**A6 hosting note:** GitHub Pages provides HTTPS and SPA fallback but does not apply the deployed `_headers` file. Browser microphone permission therefore uses the standard same-origin HTTPS permission flow; if an explicit `Permissions-Policy` header becomes mandatory, move the static site to a host with configurable response headers.

**Remaining Phase A work:** Phase A is complete. Phase B can begin with the persistent architecture canvas and project workspace expansion described in the PRD.

### Implementation status update: Phase B

**Updated:** 2026-08-22
**Overall Phase B status:** In progress. B1 is complete; B2 through B4 are implemented locally and await the controlled Supabase migration and Railway configuration; B5 remains pending end-to-end deployment verification.

| Subphase | Status | Verified outcome |
|---|---|---|
| B1 - Audit the existing project data path | Complete | The authoritative-path audit is recorded in `docs/phase-b1-project-data-path.md`. Project metadata currently lives in a Railway-local JSON file and generated files in the same local filesystem, which is not durable across service replacement or redeploy. |
| B2 - Normalize project and build data | In verification | Migration `09_persistent_build_projects.sql` is applied and Railway reports the Supabase store active. A first live project was created and reopened from durable metadata. A build-run persistence mapping defect was fixed with a regression test; completion and artifact verification remain. Legacy JSON records remain quarantined rather than being automatically claimed. |
| B3 - Project list experience | Implemented; deployment pending | Projects now show lifecycle phase, last update, plan summary, empty/error/retry states and a project-detail entry point without exposing local workspace paths. |
| B4 - Project detail experience | Implemented; deployment pending | The Flutter detail view includes specification, approved plan, Phase C architecture placeholder, build history, generated-file metadata, Resume and secure Download controls. |
| B5 - Resume and download verification | In verification | A completed project, its history and generated-file metadata persisted through browser refresh and re-login. The web download flow was adjusted to avoid browser popup blocking; public download and two-account access verification remain. |

### Version history

| Version | Date | Purpose |
|---|---|---|
| 0.3.0 | 2026-08-08 | Initial architecture and conversation persistence |
| 0.4.0 | 2026-08-09 | LiveKit-first implementation reset |
| 0.5.0 | 2026-08-21 | Soul Web MVP, secure multi-user ownership, live canvas and real DeepCode integration |
| 0.5.1 | 2026-08-21 | Expanded phase-by-phase implementation plan, tests, stop conditions, model guidance and review checkpoints |
| **0.6.0** | **2026-08-21** | **Finalized the Excalidraw live-canvas architecture, Architecture Blueprint, progressive drawing, replay, visibility and approval decisions** |

---

## 2. Product vision

Soul enables a person to move from an idea to a working, reviewed software project through conversation.

The user should be able to:

1. Speak or type an idea.
2. Explore it through General, Debate or Brainstorm Mode.
3. Ask Soul to create a live visual architecture.
4. Enter Build Mode and receive an implementation plan.
5. Explicitly approve execution.
6. Have DeepCode generate project-specific files inside a controlled workspace.
7. Follow progress, tests and review results.
8. Reopen the conversation, canvas and files from Projects.

### Product promise

> **From thought to working product through one secure, visual conversation.**

### Long-term direction

Soul becomes an agent-native software development environment that reduces dependence on IDEs, terminals and localhost workflows while keeping users in control of planning, approval and release decisions.

---

## 3. Product principles

1. **Solve one journey well:** idea → architecture → approved build → validated files.
2. **Human approval before execution:** entering Build Mode never starts code generation.
3. **Visual understanding:** important plans and architectures should be visible on a canvas.
4. **User ownership:** no user may see another user’s conversations, projects, files or canvas.
5. **Honest capability:** scaffold generation must never be presented as DeepCode execution.
6. **Web first, multi-platform later:** deliver the browser experience first while preserving Flutter mobile compatibility.
7. **Provider boundaries:** voice, model, canvas and coding-agent providers must remain replaceable.
8. **Safe execution:** coding agents operate only within validated project workspaces.
9. **Persistent work:** conversations, diagrams, decisions, build events and files survive reconnection.
10. **Quality before autonomy:** review, tests and traceability matter more than uncontrolled agent activity.
11. **Open-source-first:** core canvas, model and agent integrations should use open-source, self-hostable components with replaceable hosted adapters.
12. **Meaning before presentation:** the Architecture Blueprint is authoritative; Excalidraw and Mermaid are representations of that blueprint.

---

## 4. Target users

### Primary users

- Founders and product owners who need to turn ideas into demonstrable products
- Developers who want conversational planning and assisted implementation
- Technical teams that need reusable architectures, build records and project history

### Initial release assumptions

- Users have basic familiarity with software products but may not want to use a terminal.
- One authenticated person owns each project in the MVP; collaborators are not included.
- Projects are private by default. A future read-only public option may be enabled only after production RLS and ownership tests pass.
- Collaboration and organization workspaces are future scope.

---

## 5. Current verified foundation

The following capabilities exist and must be preserved:

- Flutter application with web build support
- Supabase account creation and sign-in
- FastAPI backend hosted on Railway
- User-authenticated LiveKit token generation
- Soul LiveKit Cloud project
- Hosted Python `voice_agent`
- Voice conversation with speech recognition, LLM response and text-to-speech
- General, Debate, Brainstorm and Build modes
- Conversation and Build Project ownership fields
- Account-aware frontend cache reset
- Build project statuses, generated-file metadata, listing and archive downloads
- Hosted-agent authentication for backend calls
- Supabase isolation migration prepared
- Production Flutter Web build
- Backend, Flutter and analysis tests passing at the v0.5.0 baseline

### Current external endpoints

- Railway backend: `https://sana-voice-intelligence-production.up.railway.app`
- LiveKit project: `wss://soul-txbxvhr6.livekit.cloud`
- Hosted LiveKit agent name: `voice_agent`

Secrets, API keys, service-role credentials and signing keys must never be recorded in this document, browser assets or Git.

---

## 6. Current gaps

The following items block a public Soul release:

1. Flutter Web is not publicly hosted.
2. The Supabase user-isolation migration has not been applied to production.
3. Full authenticated browser testing has not been completed.
4. Current changes have not been reviewed, committed and pushed.
5. SaNa/Sana names remain in internal folders, code identifiers and visible text.
6. Build Mode still needs verified genuine DeepCode runtime integration.
7. The live architecture canvas has not been implemented.
8. Projects does not yet act as the complete persistent product workspace.

---

## 7. MVP scope

### Included

- Public responsive Flutter Web application
- Supabase sign-up, sign-in, session restoration and sign-out
- Strict per-user conversation, project, canvas, build and file isolation
- Text and real-time voice interaction
- General, Debate, Brainstorm and Build modes in one conversation
- Live Overview Architecture canvas embedded in the conversation experience
- Progressive node-by-node architecture drawing with basic replay
- Persistent Architecture Blueprint, canvas events, snapshots and approved versions
- Build planning and explicit approval
- Real DeepCode execution behind a provider adapter
- Build progress and event streaming
- Generated-file browsing and archive download
- Automated tests and build review summary
- Projects workspace with resume capability
- Soul branding and installable web metadata

### Not included in this MVP

- Shared team workspaces
- Simultaneous multi-user canvas editing
- App Store or Play Store release
- Fully autonomous production deployment
- Unrestricted computer access
- Automatic destructive changes
- Every specialist agent shown in the Agent-Native SDLC vision
- Enterprise billing, subscriptions or usage metering
- Multiple simultaneous architecture views in the first canvas slice
- Advanced replay branching, timeline restoration or comparison UI
- Swark-based post-build architecture verification in the first canvas slice
- Full Microsoft Architecture Review Agent adoption

---

## 8. Core user experience

### 8.1 Authentication

1. User opens the Soul website.
2. User creates an account or signs in through Supabase.
3. Flutter receives a Supabase access token.
4. Flutter sends the token to FastAPI for protected operations.
5. FastAPI verifies the token and derives the authenticated `user_id`.
6. A new user sees empty History and Projects views.

### 8.2 Home and modes

The authenticated Home screen provides:

- Personalized greeting
- Soul voice control
- Text input
- General, Debate, Brainstorm and Build mode selector
- Recent project access
- Connection and agent status

Mode changes remain inside the same conversation and persist as conversation events.

### 8.3 Voice flow

1. Flutter requests a user-specific LiveKit token from FastAPI.
2. FastAPI validates the Supabase session.
3. Browser and hosted `voice_agent` join the same LiveKit room.
4. User speech is transcribed.
5. The selected mode determines the agent’s instructions.
6. The LLM produces a response.
7. TTS returns audio through LiveKit.
8. The user may interrupt the agent.
9. Final user and assistant turns persist; partial transcripts do not.

### 8.4 Build flow

1. User describes a product or feature.
2. Soul asks required clarification questions.
3. Soul creates a specification and architecture.
4. Soul creates an implementation plan.
5. Project status becomes `awaiting_approval`.
6. User reviews the plan and explicitly approves or rejects it.
7. On approval, FastAPI creates a controlled BuildRun.
8. The DeepCode adapter starts the verified coding-agent runtime.
9. Progress events stream to the web UI.
10. DeepCode generates or edits project files in the authorized workspace.
11. Tests and review checks run.
12. Results, logs and file metadata persist.
13. The user can inspect, resume or download the project from Projects.

### 8.5 Conversation and canvas experience

The canvas belongs to the active conversation and project; it is not a separate product or external account experience.

On desktop web:

- The conversation occupies approximately 35% of the available width.
- The live canvas occupies approximately 65%.
- A draggable divider allows resizing.
- The canvas can be collapsed or expanded to fullscreen.
- The canvas opens automatically for architecture/build requests and can also be opened manually.

On narrow/mobile layouts:

- Use `Conversation` and `Canvas` tabs instead of an unusable split view.
- Voice remains active while the user views the canvas.
- New canvas activity is indicated without interrupting the conversation.

Conversation messages summarize meaningful canvas changes and provide a `View on canvas` action. The full interactive canvas must not be embedded repeatedly inside message bubbles.

---

## 9. Live visual canvas

### Purpose

The canvas turns conversational reasoning into a structured, editable and replayable architecture. Users should watch Soul construct the design one meaningful step at a time, similar to watching a time-lapse of a drawing being created.

### 9.1 Locked technology decision

- **Canvas renderer/editor:** Excalidraw, MIT-licensed and embedded directly in Soul.
- **Canvas module:** a small React/Vite module in the same repository and deployment as Flutter Web.
- **Embedding boundary:** same-origin iframe/Flutter web element with a typed `postMessage` bridge.
- **Visual style:** clean Figma-inspired presentation using low/no roughness, rounded components, consistent spacing, Soul colors and restrained animation.
- **No external account:** users need only their Soul account; no Figma, Excalidraw or diagram-provider account is required.
- **Canonical model:** Architecture Blueprint (`ArchitectureSpec`) JSON.
- **Interactive representation:** Excalidraw scene JSON.
- **Documentation/export representation:** Mermaid.
- **Live transport:** authenticated FastAPI WebSocket for bidirectional canvas operations.
- **Persistence:** Supabase PostgreSQL events, periodic snapshots and immutable architecture versions.

Do not introduce a general microfrontend platform. The canvas is one bounded web module compiled and deployed with Soul.

### 9.2 Architecture Blueprint

`ArchitectureSpec` is the internal developer name. The user-facing product calls it the **Architecture Blueprint**.

The Blueprint records architectural meaning independently from visual position. It contains, at minimum:

- Architecture/project identifier and version
- Components with stable IDs, names, types, technology and optional metadata
- Connections with stable IDs, source, target, protocol and direction
- Groups/boundaries
- Annotations, decisions, assumptions and identified risks
- Diagram/view type
- Approval status and timestamps

Example:

```json
{
  "components": [
    {"id": "web", "name": "Flutter Web", "type": "frontend"},
    {"id": "api", "name": "FastAPI", "type": "service"}
  ],
  "connections": [
    {"id": "web-api", "from": "web", "to": "api", "protocol": "HTTPS"}
  ]
}
```

Moving or restyling a visual node must not change its architectural meaning. Excalidraw JSON is never the sole authoritative record.

### 9.3 Immediate MVP scope

The first complete slice supports one **Overview Architecture** canvas only. It must provide:

- Components, connections, groups and concise annotations
- Stable element IDs
- Zoom, pan, fit-to-screen, selection and fullscreen
- Progressive node and edge creation
- Basic node movement, label editing and deletion
- Save, reopen and reconnection recovery
- Basic Architecture Replay with play, pause, 1x and 2x speed
- PNG, Architecture Blueprint JSON and Mermaid export
- An accessible text summary
- Desktop split view and mobile tab view

Additional views such as Data Flow, Sequence, ER/Database, Deployment, Security, AI Agents and Build History are planned after the Overview slice is reliable. They must reuse the same Blueprint and primitives rather than become unrelated renderers.

### 9.4 Validated canvas operations

The AI and client communicate through a bounded operation contract. Initial operations are:

- `add_node`
- `update_node`
- `move_node`
- `delete_node`
- `connect_nodes`
- `disconnect_nodes`
- `create_group`
- `add_annotation`
- `highlight_risk`
- `focus_viewport`

For every operation, FastAPI validates:

- The authenticated user owns the project and architecture
- The operation type is allowlisted
- Referenced nodes/edges exist where required
- IDs are stable and non-duplicated
- The client version matches the current architecture version
- Payload, label, graph and rate limits are respected
- The operation cannot execute code or escape the canvas boundary

Invalid operations are rejected and recorded safely without corrupting the last valid architecture.

### 9.5 Progressive drawing behavior

- Partial voice transcripts may appear as captions but never mutate durable architecture.
- Finalized semantic phrases produce small batches of validated canvas operations.
- Target visible update cadence is approximately 0.8-1.5 seconds during active architecture generation, subject to model latency.
- Nodes should fade/scale into place; edges should appear as drawn paths; viewport movement must be smooth and restrained.
- Existing unaffected elements must not be regenerated.
- The canvas must respect reduced-motion settings.
- The canvas displays clear `Listening`, `Understanding`, `Drawing`, `Review needed` and `Saved` states.

### 9.6 Manual-edit precedence

User changes take priority over AI presentation choices. When a user moves, labels or styles an element, mark the affected properties as user-controlled. Soul must not overwrite those properties unless the user explicitly requests it or approves a proposed layout reset.

### 9.7 Event history, snapshots and replay

Every accepted operation becomes an immutable `canvas_event` with:

- `id`
- `user_id`
- `architecture_id`
- `architecture_version`
- `sequence_number`
- `idempotency_key`
- `event_type`
- Validated payload
- Actor (`user`, `soul_agent` or `system`)
- Timestamp

Examples include `canvas_started`, `node_added`, `node_moved`, `edge_connected`, `group_created`, `annotation_added`, `architecture_approved` and `canvas_completed`.

Periodic snapshots allow fast loading. On reconnect, Soul loads the newest valid snapshot and applies later events exactly once. Events should be recorded now even when advanced timeline controls are deferred.

Initial Architecture Replay includes play, pause and speed. Timeline scrubbing, branching, side-by-side comparison and restoration UI are later scope.

### 9.8 Approval and Build Mode handoff

When the user selects `Approve and Build`:

1. Validate the current Blueprint.
2. Create an immutable approved architecture version.
3. Show the exact version and Build plan to the user.
4. Bind the approval event and BuildRun to that immutable version.
5. Send the approved Blueprint, not raw canvas coordinates, to DeepCode through the BuildSpec.

Later canvas edits create a new draft version and do not silently alter an active or completed BuildRun. Execution-relevant changes require new approval.

### 9.9 Visibility and sharing

- Architectures and projects are `private` by default.
- Collaborators and simultaneous multi-user editing are not included now.
- Read-only public sharing may be enabled only after production RLS and two-account isolation tests pass.
- Public viewers cannot edit, approve, build, resume, download generated files or access private conversation data.
- Generated files and archives remain private unless a separate future sharing decision explicitly includes them.

### 9.10 Open-source references and boundaries

- Use Excalidraw and Excalidraw MCP patterns for progressive interactive rendering.
- Use relevant parser, component mapping and risk-review concepts from Microsoft's MIT-licensed Architecture Review Agent; do not adopt Azure OpenAI or Azure hosting as required dependencies.
- Mermaid remains a lightweight export/documentation format, not the primary canvas.
- Swark-style code-to-architecture verification is a later post-build capability; do not require GitHub Copilot or incorporate AGPL code without a license review.
- GenAI-DrawIO-Creator may inform validation and element-level update patterns but is not the core renderer.
- Figma/FigJam is not a runtime dependency because it is proprietary and would require external accounts. Figma may be used only as a design reference or optional future export.

### 9.11 Canvas safety

- Viewing, replaying or editing architecture never executes code.
- Canvas-generated architecture requires explicit Build Mode approval before becoming execution input.
- Every architecture, event, snapshot and version query enforces authenticated ownership or an explicitly allowed read-only public policy.
- WebSocket connections require authenticated session establishment and authorization before subscription.

---

## 10. DeepCode integration

### Current limitation

The existing `DeepCodeAdapter` has operated as a controlled scaffold generator. It can create starter files and build records but must not be described as genuine DeepCode execution unless the DeepCode runtime is actually invoked.

### Required target behavior

The backend must use a provider abstraction:

```text
Build Service
    → CodingAgentAdapter
        → DeepCodeAdapter
            → verified DeepCode CLI/runtime
```

### Verification gate

Before implementation, the coding agent must verify from the installed version:

1. Available DeepCode commands
2. Supported execution and loop modes
3. Structured/JSON output behavior
4. Workspace selection behavior
5. Resume/session behavior
6. Exit codes and error output
7. Cancellation behavior

Do not invent CLI commands, flags, endpoints or JSON schemas.

### DeepCode input

Each approved execution receives:

- Project specification
- Acceptance criteria
- Selected technical stack
- Immutable approved Architecture Blueprint version
- BuildSpec generated from that Blueprint
- Existing project files when resuming
- Workspace boundary
- Repository/project rules
- Test requirements
- Safety constraints

### DeepCode output

Soul must capture:

- Run status
- Structured progress events where supported
- Files created, modified or deleted
- Test commands and results
- Warnings and errors
- Completion summary
- Runtime/session identifier when supported

### Fallback behavior

If DeepCode is unavailable:

- Do not claim that DeepCode executed.
- Do not silently run the prototype scaffold.
- Offer a clearly labelled `Prototype Scaffold` only after user confirmation.
- Persist the blocker and failed BuildRun status.

---

## 11. Projects workspace

Projects is Soul’s persistent product workspace.

### Project list

Each card displays:

- Project title
- Current status
- Last updated time
- Current phase
- Latest build result
- Resume action

### Project detail

Each project includes:

- Overview and specification
- Linked conversation
- Latest draft and approved Architecture Blueprint
- Live canvas and Architecture Replay
- Approved implementation plan
- Build-run history
- Progress and event logs
- Generated files
- Test and review results
- Download archive
- Resume Build

### Project requirements

- Projects appear immediately after creation.
- Existing owned projects are backfilled without duplicates where required.
- Refresh occurs after creation and status changes.
- Projects survive browser refresh and account re-login.
- Users cannot access projects belonging to another account.
- Viewing, importing or downloading never executes code.

---

## 12. System architecture

```text
Flutter Web
  ├── Supabase Auth
  ├── FastAPI/Railway APIs
  ├── LiveKit browser client
  ├── Conversation + Projects UI
  └── Same-origin React/Vite Excalidraw canvas module

FastAPI on Railway
  ├── Supabase token verification
  ├── LiveKit token service
  ├── Conversation service
  ├── Architecture Blueprint service
  ├── Authenticated canvas WebSocket service
  ├── Canvas validation, snapshot and replay service
  ├── Project/build service
  ├── Coding-agent adapter
  └── Secure download service

LiveKit Cloud
  ├── Realtime rooms
  ├── Browser audio transport
  └── Hosted Python voice_agent

Supabase PostgreSQL
  ├── Profiles
  ├── Conversations/messages/events
  ├── Architecture Blueprints/versions
  ├── Canvas events/snapshots
  ├── Projects/build runs/build events
  └── Generated-file metadata

Controlled build workspace
  └── DeepCode runtime → project-specific files and tests
```

---

## 13. Data and ownership model

Every durable user resource must contain or resolve to an authenticated owner.

### Core entities

- `profiles`
- `conversations`
- `messages`
- `conversation_events`
- `architectures`
- `architecture_versions`
- `canvas_events`
- `canvas_snapshots`
- `build_projects`
- `build_runs`
- `build_events`
- `generated_files`

### Ownership requirements

- `user_id` is derived server-side from the verified Supabase token.
- The frontend cannot select or override ownership.
- Child records must resolve to a parent owned by the current user.
- Database RLS and backend authorization must both enforce isolation.
- Visibility is `private` by default; any future `public` policy is read-only and narrowly scoped.
- Downloads require authorization at request time.
- Service-role operations must retain explicit ownership predicates.

---

## 14. Security requirements

### Authentication and authorization

- Reject missing, invalid, expired or incorrectly issued Supabase tokens.
- Never accept frontend-provided identity as authoritative.
- Use user-derived LiveKit participant identities.
- Protect hosted voice-agent backend calls separately.
- Verify project ownership on list, read, modify, resume and download.

### Build workspace

- Canonicalize and validate every workspace path.
- Restrict execution to designated project roots.
- Block path traversal and symlink escapes.
- Never expose host credentials to generated code.
- Apply timeouts and cancellation.
- Require confirmation for destructive operations.
- Record auditable BuildRun and approval events.

### Secrets

- Secrets remain in approved environment stores.
- Browser bundles may contain only public configuration.
- LiveKit API secrets and Supabase service-role credentials never enter Flutter.
- `.env` and local credential files remain Git-ignored.
- Logs must redact credentials and tokens.

### Required isolation tests

- User A cannot list User B’s conversations.
- User A cannot retrieve User B’s project by ID.
- User A cannot download User B’s archive.
- User A cannot access User B’s canvas.
- A public viewer cannot edit, approve, build, resume or access private files/conversations.
- Account switching clears user-specific cached state.
- A new account begins with empty project and history views.

---

## 15. Build states

Recommended project and BuildRun states:

- `draft`
- `planning`
- `awaiting_approval`
- `approved`
- `queued`
- `running`
- `testing`
- `reviewing`
- `completed`
- `failed`
- `cancelled`
- `blocked`

All status transitions must be validated server-side and recorded as events.

---

## 16. Agent-native lifecycle

Soul’s target lifecycle is:

```text
Plan → Prototype → Build → Review → Validate → Deploy/Monitor
  ↑                                                     ↓
  └────────────── Continuous feedback loop ─────────────┘
```

### MVP agents/capabilities

1. **Planning and architecture:** clarifies the request and creates the plan/canvas.
2. **DeepCode build:** performs approved file generation and modifications.
3. **Test and review:** runs checks and summarizes readiness.

Security, accessibility, compliance, infrastructure and on-call specialist agents are future phases unless needed as deterministic checks in the MVP.

---

## 17. Non-functional requirements

### Performance

- Home and Projects should become interactive quickly on typical broadband.
- Voice connection state must be visible.
- Canvas animations should target 60 FPS on supported desktop browsers and avoid full-scene regeneration for incremental changes.
- Progressive operations should normally become visible within 1.5 seconds after a finalized semantic phrase, excluding provider outages or documented model latency.
- Build progress must update without requiring page refresh.
- Large project archives must stream rather than load fully into browser memory.

### Reliability

- Reconnecting must restore conversation and project state.
- Canvas reconnect loads the latest valid snapshot and applies later idempotent events without duplication.
- Duplicate requests must be controlled through idempotency keys.
- Partial transcripts are not durable messages.
- Failed build runs preserve diagnostic events.

### Accessibility

- Keyboard-accessible navigation and canvas controls
- Sufficient text/background contrast
- Visible focus states
- Screen-reader labels for controls and diagram summaries
- Reduced-motion behavior
- Accessible text summaries for architecture components, connections, risks and changes

### Observability

- Correlation IDs across browser, backend, LiveKit job and BuildRun
- Structured application and build events
- WebSocket connection, canvas-operation latency, rejection and replay diagnostics
- Provider latency and error visibility
- No secret values in logs

---

## 18. Delivery phases

### 18.1 Global execution protocol

These rules apply to every phase:

1. Verify the active Git branch and working-tree status.
2. Stop if the branch is unexpected or unrelated changes make the phase unsafe.
3. Read the latest PRD and the previous phase report; do not repeat a full repository audit.
4. Inspect only the files and services relevant to the current phase.
5. Record the pre-change test baseline.
6. Implement the smallest complete vertical slice.
7. Run targeted tests first and the full applicable suite before completion.
8. Inspect `git diff`, `git diff --check` and staged-file boundaries.
9. Report changes, tests, risks and manual verification required.
10. Stop for founder review before commit, push, migration or deployment unless that action was explicitly approved.

### 18.2 Model and usage strategy

| Work type | Recommended model | Reasoning |
|---|---|---|
| Architecture, security, RLS and DeepCode design | GPT-5.6 Sol | High, focused checkpoint only |
| Normal implementation and debugging | GPT-5.6 Terra | Medium |
| Mechanical tests, formatting and renaming | GPT-5.6 Luna | Low or medium |
| Final phase review | GPT-5.6 Sol | High |

Do not use Max or Ultra by default. Do not ask a model to rediscover completed work. Preserve short phase reports so the next run can continue without rereading the entire repository.

---

### Phase A — Secure, verify and publish the existing foundation

#### Objective

Turn the currently working local Soul Web build into a verified, user-isolated and publicly accessible baseline before adding new product capabilities.

#### A0 — Repository and deployment snapshot

- Verify branch, upstream and working-tree status.
- Record the current commit hash without changing history.
- Inventory modified and untracked files.
- Confirm the Railway health endpoint reports the Soul LiveKit URL.
- Confirm the hosted `voice_agent` is running.
- Confirm secrets are absent from tracked files and `mobile/build/web`.
- Record existing backend and Flutter test results.

**Deliverable:** concise baseline report.  
**Stop condition:** unexpected branch, merge conflict, exposed secret or unrelated destructive change.

#### A1 — Review the Supabase isolation migration

- Inspect the migration without applying it.
- Confirm every user-owned table contains or resolves to `user_id`.
- Verify RLS is enabled on all relevant tables.
- Verify SELECT, INSERT, UPDATE and DELETE policies use the authenticated user.
- Verify service-role backend paths still apply explicit ownership filters.
- Check indexes for common `user_id` and parent-resource queries.
- Prepare rollback or corrective SQL before production execution.

**Tests:** migration syntax, local/staging policy tests if available, backend authorization tests.  
**Approval gate:** founder reviews the SQL and target Supabase project before application.

#### A2 — Apply and verify the production migration

- Apply only the approved migration to the verified Soul Supabase project.
- Do not print credentials or service-role keys.
- Confirm RLS and policies after migration.
- Confirm existing records retain the correct owner.
- Identify orphaned records; do not assign them to arbitrary users.

**Tests:** two-account direct database/API isolation checks.  
**Stop condition:** ownership ambiguity, policy failure or unexpected production data change.

#### A3 — Complete two-account end-to-end isolation testing

Using User A and User B:

- Create separate conversations.
- Create separate Build Projects.
- Verify list endpoints show only the current user’s records.
- Attempt cross-user detail, resume, canvas and download access by ID.
- Verify all unauthorized attempts return an appropriate denial without data leakage.
- Sign out and switch accounts in the same browser.
- Confirm caches and UI state reset.
- Confirm a new account starts with empty History and Projects.

**Acceptance:** no cross-account data is visible through UI, API or direct identifier access.

#### A4 — Authenticated voice and existing Build Mode browser test

- Sign in through Flutter Web.
- Request a user-specific LiveKit token.
- Confirm the participant identity derives from the authenticated user.
- Complete one voice turn and interruption test.
- Enter Build Mode and create a prototype project.
- Confirm the project is stored under the authenticated account.
- Confirm the archive download is authorized.

**Acceptance:** voice and the existing controlled build workflow work after the isolation changes.

#### A5 — Soul rebrand pass

- Replace user-visible SaNa/Sana branding with Soul.
- Update titles, descriptions, PWA metadata, icons and accessible labels.
- Preserve internal package/folder names when renaming them would create unnecessary risk.
- Document intentionally deferred internal renames.
- Do not rename cloud resources merely for visual consistency.

**Tests:** Flutter tests, analysis, web build and visual inspection at desktop and narrow widths.

#### A6 — Public Flutter Web deployment

- Select and document the approved static hosting provider.
- Configure SPA redirects.
- Configure microphone permission headers and HTTPS.
- Configure public Supabase values and Railway base URL without secrets.
- Deploy the production web build.
- Test sign-up, sign-in, refresh, deep links, microphone permission and sign-out on the public URL.

**Phase A exit criteria:**

- Production RLS is active and verified.
- Two-account isolation passes.
- Authenticated voice works on the public site.
- Existing Build Mode works without data leakage.
- Visible branding uses Soul.
- Tests and production web build pass.

**Review/commit checkpoint:** one security-focused checkpoint and, if preferred, a separate web-deployment/rebrand checkpoint. Commit and push only after approval.

---

### Phase B — Complete the Projects workspace

#### Objective

Make Projects the reliable, persistent home for every user-owned product, conversation, build and downloadable artifact.

#### B1 — Audit the existing project data path

- Trace project creation from voice/text Build Mode to FastAPI persistence.
- Trace list, detail, status, resume and download requests.
- Identify whether any legacy projects exist only on disk or without ownership metadata.
- Confirm the UI and backend use the same authoritative project source.

**Deliverable:** root-cause report for missing, duplicate or stale projects.

#### B2 — Normalize project and build data

- Finalize project, BuildRun, event and generated-file relationships.
- Add required ownership, status and timestamp indexes.
- Define stable API response models.
- Backfill valid existing projects idempotently.
- Quarantine ambiguous or unsafe legacy records rather than exposing them.

**Tests:** idempotent backfill, ownership, duplicate prevention and status-transition tests.

#### B3 — Project list experience

- Display title, status, current phase, last update and latest result.
- Provide loading, empty, error and retry states.
- Refresh after project creation and status changes.
- Preserve the current authenticated user boundary.

#### B4 — Project detail experience

- Add specification and approved plan.
- Link the authoritative conversation.
- Add architecture/canvas placeholder until Phase C.
- Display BuildRun history and events.
- Display generated-file metadata and test status.
- Add secure Resume and Download actions.

#### B5 — Resume and download verification

- Reopen a project after browser refresh and re-login.
- Resume without creating a duplicate project.
- Authorize every archive generation/download request.
- Reject cross-user and invalid-path downloads.

**Phase B exit criteria:** an authenticated user can create, leave, reopen, resume and download only their own project, with no duplicate or missing list entry.

**Review/commit checkpoint:** Projects data/API changes and UI changes may be separate commits after approval.

---

### Phase C — Persistent live canvas MVP

#### Objective

Let Soul create clear, structured diagrams during a conversation and persist them as part of a project.

#### C1 — Architecture Blueprint contract

- Define and test the provider-neutral `ArchitectureSpec` schema.
- Include stable component, connection, group, annotation, decision and risk IDs.
- Define draft, approved and superseded version behavior.
- Define the allowed canvas operation schema and validation errors.
- Keep visual coordinates/style outside the core architectural meaning where practical.

**Deliverable:** versioned schema, examples and validation tests before renderer work.

#### C2 — Standalone Excalidraw canvas proof

- Add a bounded `canvas/` React/Vite module using the MIT-licensed Excalidraw package.
- Do not add a general microfrontend framework.
- Render one Overview Architecture example from a Blueprint.
- Add nodes and edges progressively through local mock operations.
- Verify zoom, pan, selection, fit, fullscreen and basic responsive behavior.
- Apply clean Figma-inspired Soul styling with low/no roughness.
- Verify reduced-motion and accessible summary behavior.

**Stop condition:** unsupported license, unusable Flutter embedding, unacceptable performance or a requirement for external user accounts.

#### C3 — Embed canvas in the Soul conversation

- Build/deploy the canvas module from the same repository and origin as Flutter Web.
- Embed it through an isolated Flutter web element/iframe.
- Add a typed and origin-validated `postMessage` bridge.
- Implement desktop 35/65 split view with resizing, collapse and fullscreen.
- Implement narrow/mobile `Conversation` and `Canvas` tabs.
- Add `View on canvas` activity cards to conversation history.
- Preserve voice controls while the canvas is visible.

#### C4 — Authenticated storage and APIs

- Implement `architectures`, `architecture_versions`, `canvas_events` and `canvas_snapshots` storage.
- Link each architecture to its owner, conversation and optional project.
- Add authenticated create, read, update, list, version, event and snapshot APIs.
- Enforce RLS and backend ownership checks.
- Add sequence-number and idempotency constraints.
- Store private visibility by default.

#### C5 — Validated WebSocket operations

- Add an authenticated FastAPI WebSocket endpoint scoped to one owned architecture.
- Validate every operation against the allowlist and current version.
- Broadcast accepted operations to the authorized canvas.
- Persist accepted durable operations exactly once.
- Return safe structured rejection events for invalid operations.
- Implement reconnection using latest snapshot plus later events.
- Add rate, payload, graph-size and connection limits.

#### C6 — Voice/text progressive architecture generation

- Extend the Soul planning agent to produce structured Blueprint changes and canvas operations.
- Treat partial transcripts as captions only.
- Convert finalized semantic phrases into small validated operation batches.
- Target visible updates every 0.8-1.5 seconds when feasible.
- Animate new nodes, edges and viewport focus without regenerating unaffected elements.
- Surface Listening, Understanding, Drawing, Review needed and Saved states.
- Never persist an incomplete invalid Blueprint as an approved version.

#### C7 — Manual editing and precedence

- Allow node movement, label editing, connection changes and deletion with confirmation.
- Mark manually controlled visual properties so AI layout does not overwrite them silently.
- Reflect meaningful manual edits back into the Blueprint when applicable.
- Require explicit permission before a full layout reset.

#### C8 — Snapshots, basic replay and exports

- Create periodic snapshots and verify deterministic event replay.
- Implement Architecture Replay with play, pause, 1x and 2x speed.
- Export PNG, Architecture Blueprint JSON and Mermaid.
- Defer timeline scrubbing, branching, side-by-side comparison and restoration UI.

#### C9 — Approval and Canvas-to-Build handoff

- Validate the current Blueprint before approval.
- Create an immutable approved architecture version.
- Display exactly which version and BuildSpec will be sent to DeepCode.
- Bind the approval event and BuildRun to that immutable version.
- Require new approval for execution-relevant changes.
- Viewing, editing or replaying a canvas never executes code.
- Keep read-only public sharing disabled until Phase A isolation/RLS evidence is complete; when enabled, exclude editing, builds, private conversations and file downloads.

**Phase C exit criteria:** in the same conversation, a user can request an Overview Architecture, watch it draw progressively, edit and save it, reopen and replay it, then approve an immutable Blueprint version for Build Mode.

**Tests:** Blueprint/operation validation, malformed graph, WebSocket authentication, ownership, idempotency, snapshot replay, reconnect, manual-edit precedence, version locking, rendering, browser refresh, reduced motion and responsive UI.

**Review/commit checkpoint:** Blueprint contract, standalone canvas, embedding, storage/WebSocket, agent generation and approval handoff are separate reviewable checkpoints.

---

### Phase D — Genuine DeepCode integration

#### Objective

Replace the misleading scaffold-only path with a verified, traceable and controlled DeepCode coding-agent execution.

#### D1 — Runtime discovery

- Verify the installed DeepCode version.
- Inspect official local help for commands and flags.
- Run a harmless disposable-workspace proof.
- Capture sanitized stdout, stderr, exit code and structured output.
- Verify resume/session, cancellation and workspace behavior.
- Document the observed schema; do not infer undocumented fields.

**Stop condition:** no verified noninteractive/structured execution path or unsafe unrestricted workspace behavior.

#### D2 — Adapter contract

- Define provider-neutral request, event, result and error models.
- Keep Build Service independent of DeepCode CLI details.
- Retain the current scaffold generator as an explicitly named optional prototype provider.
- Never silently switch providers.

#### D3 — Safe workspace runner

- Create one controlled root per user/project/BuildRun.
- Canonicalize paths and block traversal/symlink escape.
- Apply execution timeout, cancellation and output-size limits.
- Use an allowlisted environment with no unnecessary credentials.
- Record approval and runtime identity before starting.

#### D4 — Approved execution input

- Assemble a BuildSpec from the specification, acceptance criteria, technical stack, immutable approved Architecture Blueprint version, repository rules and test requirements.
- Show the final plan and workspace target before approval.
- Bind approval and BuildRun to a plan/Blueprint version hash or equivalent immutable reference.
- Reject execution if the plan changed after approval.

#### D5 — Execution and progress

- Start DeepCode only after valid approval.
- Parse and normalize verified runtime events.
- Stream status to Flutter Web.
- Persist events idempotently.
- Record created, modified and deleted file paths without exposing secret contents.
- Support cancellation and mark abnormal termination correctly.

#### D6 — Completion and fallback

- Capture the final file inventory, summary and test recommendations.
- Clearly label the provider used for every BuildRun.
- On runtime failure, persist `failed` or `blocked` with actionable diagnostics.
- Offer Prototype Scaffold only after explicit confirmation.

**Phase D exit criteria:** a verified DeepCode run creates project-specific files inside the controlled workspace, streams traceable events and is visibly distinguishable from prototype scaffolding.

**Tests:** command parsing, fake-process adapter tests, timeout, cancellation, path traversal, approval mismatch, event idempotency, failure and successful disposable-project integration test.

**Review/commit checkpoint:** runtime discovery documentation, adapter, safe runner and UI integration should be reviewed separately. No production execution before security review.

---

### Phase E — Review, validation and completion evidence

#### Objective

Ensure Soul never marks a build complete without recorded validation evidence.

#### E1 — Detect project toolchain

- Determine project language/framework from generated files.
- Select only approved read/build/test commands.
- Do not execute arbitrary commands suggested by generated content without policy validation.

#### E2 — Deterministic validation

- Run applicable formatter check, lint, type check, unit tests and build verification.
- Capture command, sanitized output, duration and exit status.
- Apply time and output limits.

#### E3 — AI review

- Review the approved specification, diff and deterministic results.
- Report findings by severity with file references and suggested remediation.
- Do not report AI review as a substitute for tests.

#### E4 — Remediation loop

- Present findings to the user.
- Require approval before another modifying agent run.
- Rerun failed validation after remediation.
- Preserve previous results for audit history.

#### E5 — Completion decision

- Mark `completed` only when required checks pass or documented waivers are explicitly accepted.
- Show a concise readiness summary in Projects.
- Include validation evidence in project export metadata.

**Phase E exit criteria:** every completed BuildRun has deterministic test evidence, review findings and a traceable completion decision.

**Tests:** toolchain detection, command policy, output redaction, timeout, failed test, waiver and successful completion-state tests.

**Review/commit checkpoint:** deterministic validator before AI review, followed by end-to-end completion workflow.

---

### Phase F — Mobile packaging and advanced agent lifecycle

#### Objective

Expand the proven Soul Web workflow after the MVP is stable.

#### F1 — Mobile readiness

- Audit web-only dependencies.
- Optimize responsive layouts and voice permissions for Android/iOS.
- Add mobile-specific deep links, downloads and background behavior where supported.
- Complete physical-device voice testing.

#### F2 — Collaboration

- Introduce organizations, project membership and explicit roles.
- Replace single-owner assumptions with reviewed membership policies.
- Add invitations, audit events and shared project permissions.

#### F3 — Specialist agents

Add only when product evidence requires them:

- Security
- Accessibility
- Compliance readiness
- Infrastructure/operations
- Performance
- Deployment and monitoring

Each specialist must have a bounded responsibility, inputs, outputs, tests and a user-visible value.

#### F4 — Production sandbox workers

- Replace host-local workspaces with isolated ephemeral workers.
- Apply CPU, memory, network, time and storage controls.
- Store build artifacts outside the worker lifecycle.
- Add concurrency and usage limits.

#### F5 — Advanced architecture intelligence

- Add Data Flow, Sequence, ER/Database, Deployment, Security, AI-Agent and Build-History views using the shared Blueprint.
- Add fuller architecture risk review using selected concepts from the Microsoft Architecture Review Agent.
- Add Swark-style code scanning through Soul's provider-neutral model adapter to infer the actual built architecture.
- Compare approved versus implemented architecture and present differences for user review.
- Add advanced replay timeline scrubbing, restoration, branching and side-by-side comparison only after event storage is proven reliable.

**Phase F exit criteria:** defined per approved mobile, collaboration or specialist-agent release; Phase F is not required for the Soul Web MVP.

---

### 18.3 Required phase completion report

At the end of every subphase, Codex must report:

1. Branch and final Git status
2. Objective completed or blocked
3. Root cause or design decision
4. Files and migrations changed
5. Tests run and exact results
6. Manual verification still required
7. Security or data risks
8. Recommended next subphase
9. Whether a commit/push/deployment approval is needed

The report must not contain credentials, access tokens, API secrets or private configuration values.

---

## 19. MVP acceptance criteria

Soul Web MVP is accepted when:

1. The public web application supports Supabase sign-up, sign-in and sign-out.
2. Two-account tests prove conversation, project, canvas and download isolation.
3. Voice connects to the Soul LiveKit project and the hosted agent responds.
4. Mode changes work inside the same conversation.
5. A user can open the live Overview Architecture canvas inside the active conversation.
6. Voice or text causes validated nodes and connections to appear progressively without full-canvas regeneration.
7. The Architecture Blueprint remains authoritative and can be saved, reopened and exported.
8. Manual edits are preserved and basic Architecture Replay works.
9. Architecture approval creates an immutable version linked to the BuildRun.
10. Build Mode produces a plan but does not execute before approval.
11. An approved build invokes the verified DeepCode runtime with the approved BuildSpec.
12. Progress and final status appear in the web application.
13. Project-specific generated files and test results are stored.
14. Projects lists only the authenticated user’s work.
15. The user can resume and securely download an owned project.
16. Secrets are absent from browser bundles and Git.
17. Automated backend, Flutter and canvas-module tests pass.
18. Visible product branding uses Soul.

---

## 20. Release blockers

The following must be resolved before public demonstration as a production-ready system:

- Production Supabase isolation migration not applied
- Public frontend hosting incomplete
- Full two-account end-to-end test incomplete
- Real DeepCode integration not verified
- Live canvas not implemented
- Architecture Blueprint ownership, event replay and approval version-locking not verified
- Existing uncommitted/unpushed work not reviewed

---

## 21. Implementation rules for coding agents

- Inspect the current repository before proposing changes.
- Preserve working features and Git history.
- Work in small, reviewable checkpoints.
- Do not repeat a complete repository audit for every phase.
- Do not expose or print secrets.
- Do not change branches automatically.
- Do not commit or push without explicit approval.
- Do not rewrite the application simply to adopt a reference repository.
- Do not add Figma/FigJam, GitHub Copilot, Azure OpenAI or another proprietary service as a required canvas/runtime dependency.
- Verify dependency licenses before adoption; keep license notices required by MIT, Apache-2.0 and other approved licenses.
- Treat Microsoft Architecture Review Agent, Swark and GenAI-DrawIO-Creator as references unless a separately reviewed integration is approved.
- Use the lowest-cost suitable model for mechanical tasks and stronger reasoning only for architecture, security and DeepCode integration.
- Report root cause, files changed, tests and remaining risks after each checkpoint.

---

## 22. Open decisions

1. Public Flutter Web hosting provider and production domain
2. Exact installed DeepCode command and structured-output contract
3. Storage strategy for generated project archives at production scale
4. Whether the internal repository/package names should be renamed immediately or after the web MVP stabilizes
5. Initial limits for concurrent builds, workspace size and execution duration
6. Which build-validation checks are required before download
7. Exact snapshot cadence and maximum architecture/event limits after performance measurement
8. Whether read-only public sharing belongs in the first public MVP or the immediately following release after RLS verification
9. Soul product-source license (private source, Apache-2.0 or AGPL) independent of the open-source dependency policy

---

## 23. Founder approval gate

Approval of this PRD authorizes phased implementation but does not authorize:

- Destructive repository operations
- Production database migration without review
- Unreviewed public deployment
- Unrestricted DeepCode access
- Automatic commit or push

Recommended first action after approval:

> Apply and verify the Supabase isolation migration in a controlled checkpoint, then perform a complete two-account browser test before beginning the live canvas or DeepCode work.
