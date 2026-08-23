# DeepCode Runtime Discovery

**Date:** 2026-08-23
**DeepCode version:** 2.0.0
**Discovery workspace:** `$TEMP/deepcode_proof3` (deleted after capture)

## 1. CLI Entry Points

| Command | Description |
|---|---|
| `deepcode exec <task>` | One-shot headless coding turn (primary Soul path) |
| `deepcode loop <goal>` | Durable goal, supports `--resume` |
| `deepcode` (no args) | Interactive TUI — not usable from FastAPI subprocess |
| `deepcode mcp` | MCP server over stdio |

## 2. `deepcode exec` Flags

| Flag | Value | Notes |
|---|---|---|
| `prompt` | positional string | The coding task |
| `--workspace / -w` | path | Workspace directory |
| `--json` | flag | Emit NDJSON events to stdout |
| `--access` | `ask | read-only | full-access` | `full-access` disables interactive approvals |
| `--trust` | flag | Trust workspace path (remembered between runs) |
| `--connection / -c` | provider name | LLM provider |
| `--model / -m` | model id | Override model |
| `--max-iterations` | integer | Sampling limit |
| `--resume` | session id | Resume existing session |

## 3. NDJSON Event Schema (Observed)

Each line: `{"id": "<seq>", "msg": {"type": "<event_type>", ...}}`

### Event types observed
| type | Key fields |
|---|---|
| `turn_started` | `skill_invocations` |
| `model_usage_recorded` | `response_ordinal`, `usage.prompt_tokens`, `usage.completion_tokens` |
| `tool_started` | `call_id`, `name`, `detail`, `activity.kind`, `activity.subject` |
| `tool_completed` | `call_id`, `name`, `is_error`, `result_preview` |
| `agent_message` | `text` |
| `task_complete` | `final_text`, `stop_reason` (`"completed"` or `"error"`) |
| `error` | `message` |

## 4. Exit Codes

| Code | Meaning |
|---|---|
| `0` | Successful execution |
| `1` | Failure (auth error, trust missing, runtime error) |

## 5. Workspace Behavior

- First use of a workspace path requires `--trust` flag.
- Trust is remembered for that canonical path.
- Files written directly into the workspace directory.
- No automatic cleanup; Soul manages workspace lifecycle.

## 6. Session Management

- Each `exec` run creates a session: ID printed to stderr as `session=<id>`.
- Sessions can be resumed: `deepcode exec --resume <session-id>`
- Non-interactive deletion: `deepcode session delete <id> --yes`

## 7. Providers Verified on This Machine

| Name | Type | Status |
|---|---|---|
| `openrouter` | OpenRouter | ready |
| `personal-openrouter` | OpenRouter | ready |
| `anthropic` | Anthropic | ready |
| `ollama` | Ollama | ready |

**Railway note:** Railway container needs `DEEPCODE_CONNECTION` env var pointing to a
configured provider. Recommend baking provider config into the Docker image or
running `deepcode provider` at container startup with a Railway secret.

## 8. Soul Integration Command

```bash
deepcode exec \
  --workspace <workspace_path> \
  --json \
  --access full-access \
  --trust \
  --connection <DEEPCODE_CONNECTION> \
  "<prompt>"
```

## 9. Stop Conditions Cleared

- [x] Non-interactive execution path verified
- [x] Structured NDJSON output confirmed
- [x] File generation verified (28-byte hello.py written correctly)
- [x] Session resume path exists
- [x] Non-interactive session deletion confirmed
- [x] Exit code 0 on success, 1 on failure
