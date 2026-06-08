# Headless Agent Control

DietCode exposes a high-fidelity local Unix socket control surface designed for deep integration with automation tools and AI agents.

**Socket Path:** `~/.dietcode/control.sock`
**Protocol:** Newline-delimited JSON-RPC (2.0-style)
**Authentication:** Requires a session token from `~/.dietcode/session.token`

**Audit record:** Passes I–VI hardened this surface into a deterministic local transaction kernel. See [Agent Runtime Audit](agent-runtime-audit.md) for the full change log, contracts, and verification ladder.

```bash
make restart-agent-server   # after C++ changes
make verify-agent-runtime-full
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
```

---

## 🏗️ The "Chip & Combo" Runtime

DietCode features a deterministic execution runtime where individual operations are called **Chips**. Multiple chips can be orchestrated into a **Combo** (a stateful transaction or script).

- **Chips:** Atomic, reusable operations with metadata (idempotency, side-effects, rollback support).
- **Combos:** Sequential or branched execution of chips with built-in validation and recovery.

### Chip Registry Methods
- `chip.list`: List all registered atomic operations.
- `chip.describe`: Get detailed metadata for a specific chip (params, returns, risk level).

### Combo Management
- `combo.validate`: Check if a sequence of chips is valid before execution.
- `combo.run`: Execute a combo and return the results.
- `combo.status`: Check the progress of a running combo.
- `combo.cancel`: Halt an active combo.
- `combo.rollback`: Revert the side-effects of a completed combo (requires chip rollback support).

---

## 🛠️ RPC Method Reference

### Core & Discovery
- `rpc.ping`: Health check. Returns `pong: true`.
- `rpc.version`: Returns app, protocol, and schema versions.
- `rpc.methods`: Returns a list of all available RPC method names.
- `rpc.describe`: Returns a detailed schema for one or all methods.
- `system.info`: Returns OS version, architecture, CPU count, and memory info.

### Workspace & Search (agent-safe)

- `workspace.getRoot`: Get the absolute path of the opened workspace.
- `workspace.openFolder`: Change the active workspace.
- `workspace.findFiles`: Discover files using glob patterns (e.g., `src/**/*.hpp`).
- `workspace.listFiles`: Recursively list files in the workspace.
- `workspace.openFile`: Open a file in the editor. In headless mode, this validates the file, updates recent-file state, and returns `{ "opened": true, "headless": true }` without touching UI-only editor views.
- `workspace.grep`: Literal substring scan (`searchMode: literal_substring`). Editor buffer preferred; **disk fallback** when headless. Sorted `path_line_column` results; scan accounting (`filesRead`, `filesSkippedSymlink`, …).
- `workspace.revision`: Monotonic `revisionId`, `changedFiles`, `lastMutationReceipt` (Pass III).
- `workspace.snapshot`: Point-in-time `fileHashes`; modes `mutated_only` | `tracked_files` | `explicit_paths`. Partial-success fields when truncated.
- `workspace.searchStart` / `workspace.searchNext` / `workspace.searchCancel`: Incremental search session (paged).
- `search.literal`: Agent-safe literal substring search (`rankingPolicy: none`).
- `search.tokens`: Conjunctive literal token match (`matchReason: all_tokens_literal`).
- `search.paths`: Alias of `search.files` (`deterministic_path_match`, no score).
- `search.files`: Deterministic path match (`matchReason`: `basename_exact` | `path_substring`, `sortOrder: match_reason_path`).
- `search.text` / `search.todo`: Same accounting model as grep; context lines on `search.text`.
- `search.references`: Exact symbol references (`symbol_exact`, sorted `path_line_column`).
- `search.semantic`: **Quarantined** — returns `semantic_disabled` (4008) unless `allowExperimental: true`. Use `search.literal` or `search.tokens`.
- `tool.registry` / `tool.capabilities`: Agent-safe method catalog (`agentSafe`, `deterministic`, `deprecated`, `replacementMethod`, `internalNamespaces`).

### File & Editor Operations
- `file.read`: Read entire file content.
- `file.readBatch`: Read multiple files in a single call (reduced round-trips).
- `file.readRange`: Read specific line ranges.
- `file.stat`: Get metadata (size, line count, status) for a file.
- `file.statBatch`: Get metadata for multiple files in a single call.
- `file.write`: Overwrite file content.
- `file.create`: Create a new file with content.
- `editor.getActiveFile`: Get the path of the currently focused tab.
- `editor.getOpenFiles`: Get a list of all files currently open in tabs.
- `editor.insertText`: Insert text at the current cursor position.
- `editor.replaceRange`: Replace a specific character range in a file.
- `editor.applyPatch`: Apply a unified diff patch to a file with validation.
- `editor.saveFile`: Trigger a save operation.
- `editor.goto`: Navigate to a specific line/column.

### Advanced Analysis & Symbols

**Internal namespaces** (`analysis.*`, `language.*`) are **not** in `tool.registry`. Use agent-safe search surfaces for automation.

- `analysis.workspaceSummary`: Statistical overview of the workspace (languages, file counts).
- `analysis.searchRanked`: **Quarantined** — returns `ranked_search_disabled` (4008). Use `workspace.grep` or `search.literal`.
- `symbols.document`: Extract a flat list of symbols (classes, functions, etc.) for a file. Includes `offset` and `endOffset`.
- `symbols.hierarchy`: Extract a nested tree of symbols for a file.
- `symbols.references`: Find all usages of a specific symbol (deterministic; no score ranking).
- `symbols.atCursor`: Identify the symbol under the editor cursor.

### Diff & Patch (agent transaction kernel)

Recommended flow: `patch.validate` → read `beforeContentHash` → `patch.apply` with `expectBeforeHash` → check `mutationReceipt` → `workspace.revision`.

- `diff.chunk`: Read large diffs in chunks to avoid frame limits.
- `diff.hunks` / `patch.hunks`: Structured unified diff hunks (`literal_unified_diff_hunks`). Partial-success when paginated.
- `patch.validate`: Dry-run; returns `beforeContentHash`, `patchFingerprint`, `requiresConfirmation`.
- `patch.apply`: Applies with `expectBeforeHash` stale guard → `stale_content` (4004) on drift. Emits `mutationReceipt` on success. Rejects symlink targets → `symlink_target`.
- `patch.applyBatch`: Atomic multi-file apply with `batchMutationReceipt` and rollback on any failure.
- `operation.status`: Lookup completed mutation by `idempotencyKey` (safe retry after timeout).

### Git Integration
- `git.status`: Get staged, modified, and untracked file lists.
- `git.diff`: Get raw git diff text.
- `git.stage` / `git.unstage`: Manage the staging area.
- `git.commit`: Create a commit with a message.

### Terminal & Execution
- `terminal.run`: Execute a shell command in the integrated terminal.
- `terminal.getOutput`: Capture current terminal scrollback.
- `terminal.status`: Check if a process is still running.

### Stateful Task Runtime
- `task.start`: Initialize a high-level goal with a budget and verification steps.
- `task.step`: Execute a single step in a multi-turn task.
- `task.runLoop`: Autonomously run steps until a goal is met or budget exceeded.

### Diagnostics & Repair
- `diagnostics.list`: Get all current compiler/linter errors and warnings.
- `diagnostics.cluster`: Group diagnostics by cause or file.
- `repair.fromCompilerErrors`: Suggest or apply fixes based on diagnostic evidence.

### Language Features
- `language.hover`: Return hover text for a file location. In headless mode, this returns a stable empty hover with `headless: true` when no UI/LSP editor session is active.
- `language.completions`: Return completions for a file location. In headless mode, this returns an empty list with `headless: true` instead of failing.
- `language.definition`: Return the definition location for a file location. In headless mode, this returns `location: null`, `heuristic: true`, and `headless: true` when UI-backed LSP state is unavailable.

### Events (Duplex)
- `event.subscribe`: Listen for real-time notifications (e.g., `DocumentSaved`, `ActivityChanged`). `types` must be a non-empty string array.
- `event.unsubscribe`: Stop listening for events. `types` must be a non-empty string array.

Use a dedicated socket connection for long-running event subscriptions. Event notifications are delivered on the subscribed connection and can interleave with ordinary JSON-RPC responses; the bundled Python helper filters notification frames while waiting for a matching response id, but independent readers should not share one socket.

---

## Partial success and recovery (Pass VI)

Success payloads on read/search/patch surfaces may include:

| Field | Meaning |
|-------|---------|
| `complete` | `false` when truncated, paginated, or scan-limited |
| `partial` | `true` when warnings, skips, or disk fallback occurred |
| `warnings` | Stable tokens (`results_truncated`, `requires_confirmation`, …) |
| `fallbackUsed` | Disk read fallback was used |
| `recoveryHint` | Next safe action when incomplete |
| `nextRecommendedCommand` | RPC method to call next |

Error envelopes add `recovery_hint` and `nextRecommendedCommand`. See [Error Codes](error-codes.md).

Enriched surfaces: `workspace.grep`, `search.*`, `patch.validate`, `patch.apply`, `patch.applyBatch`, `workspace.snapshot`, `diff.hunks`, `patch.hunks`.

---

## Headless Ergonomics Notes

Recent agent ergonomics work tightened the behavior of the headless control surface:

- Socket startup probes preserve the underlying failure reason (`not_found`, `connection_refused`, `timeout`, `permission_denied`, or another OS error) instead of reporting every failed probe as an inactive socket.
- The Python client no longer unlinks an existing current-user socket during startup recovery. A stale or refused socket is diagnosed and the native `--ensure-socket` path is used to start a fresh server.
- Headless-safe UI-adjacent RPCs return explicit headless results rather than terminating the headless process.
- Incremental workspace search and batch file read/stat methods are advertised in `rpc.methods` / `rpc.describe` and are treated as read-only agent methods.
- Symlinks are never followed during search (`symlinkPolicy: skip_never_follow`); patch targets through symlinks are rejected.
- After C++ control-server changes, run `make restart-agent-server` before live harnesses — stale binaries cause false failures.

---

## 🐍 Python SDK Usage

The `scripts/dietcode_agent_client.py` provides a robust wrapper for these methods.

```python
from dietcode_agent_client import DietCodeAgentClient

with DietCodeAgentClient() as client:
    # High-level workspace search
    results = client.call("workspace.grep", {"query": "TODO"})
    
    # Structured diff reading
    hunks = client.call("diff.hunks", {"source": "unstaged", "includeLines": True})
    
    # Terminal execution
    client.call("terminal.run", {"command": "make test"})
```

For event-driven tools, keep the event stream separate:

```python
with DietCodeAgentClient() as rpc, DietCodeAgentClient() as events:
    with events.event_subscription(["terminal.output"]):
        rpc.call("terminal.run", {"command": "make test"})
        frame = events.read_frame(request_timeout=5.0)
        print(frame["params"]["detail"])
```

For command-line listeners, use `--listen --listen-type terminal.output`. Repeat `--listen-type` to subscribe to multiple event types, and use `--listen-max-events N` or `--listen-idle-timeout SECONDS` for bounded automation. Event frames are written to stdout, while listener status text is written to stderr unless `--quiet` is set.

For CI or agent scripts, add `--error-json` to receive JSON-RPC-style error envelopes on stderr instead of plain text failures. With `--error-json`, failures are emitted even when `--quiet` suppresses informational stderr.

See [Error Codes](error-codes.md) for the full `string_code` catalog and grep anchors. Environment variables and config precedence: [Agent Environment](agent-environment.md).

---

## CLI shortcuts (grep / diff / patch)

Run from the repo root. All examples use compact JSON on stdout.

```bash
# Preflight (offline-safe except --wait-ready)
python3 scripts/dietcode_agent_client.py --self-test --compact
python3 scripts/dietcode_agent_client.py --status --compact
python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json

# Literal workspace grep (paged)
python3 scripts/dietcode_agent_client.py --grep executeMethod --max-results 5 --compact
python3 scripts/dietcode_agent_client.py --grep TODO --include '*.py' --result-offset 10 --compact

# Unified diff hunks with literal line evidence
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --include-lines --compact
python3 scripts/dietcode_agent_client.py --diff-source file --path src/main.mm --diff-hunks --max-hunks 3 --compact

# Patch dry-run from stdin
git diff -- path/to/file | python3 scripts/dietcode_agent_client.py --patch-stdin --path path/to/file --compact

# Batch NDJSON (one envelope per line; exit 1 if any ok:false)
printf '%s\n' '{"id":"1","method":"rpc.ping","params":{}}' \
  | python3 scripts/dietcode_agent_client.py --batch-stdin --compact

# Invalid params: full envelope + non-zero exit with --raw-response
python3 scripts/dietcode_agent_client.py --raw-response --compact event.subscribe '{}'; echo exit=$?
```

### Config file

```bash
python3 scripts/dietcode_agent_client.py \
  --config docs/headless-agent-config.example.json \
  --emit-config --compact
export DIETCODE_AGENT_CONFIG=docs/headless-agent-config.example.json
```

### Verification ladder

```bash
make app && make restart-agent-server
make agent-self-test && make test-docs-code-drift
make agent-ready && make agent-status && make agent-ping
make verify-agent-runtime
make verify-agent-runtime-full
make control-smoke | rg '"type":"(check|summary)"'
make agent-integration | rg '"type":"summary"'
```

Integration scripts resolve the workspace from `DIETCODE_TEST_WORKSPACE`, then the repo root, then `workspace.getRoot`.

See [Agent Runtime Audit](agent-runtime-audit.md), [Agent Tooling](agent-tooling.md), and [Build & Test System](build-and-test-system.md) for per-pass targets.

---

## CLI flag reference

| Flag | Purpose |
|------|---------|
| `--grep QUERY` | `workspace.grep` literal substring scan |
| `--grep-format rg` | ripgrep-style `path:line:column:preview` lines (exit 1 when no matches) |
| `--search-literal QUERY` | Agent-safe `search.literal` alias (Pass V) |
| `--search-semantic QUERY` | **Deprecated** — stderr warning; use `--search-literal` |
| `--expect-before-hash HASH` | Pass `expectBeforeHash` to `patch.apply` (Pass II) |
| `--diff-summary` | Compact `diff_summary` JSON with `--diff-hunks` |
| `--patch-summary` | Compact `patch_validation_summary` JSON for patch.validate/preview |
| `--search-text QUERY` | `search.text` with optional `--before` / `--after` |
| `--diff-source` + `--diff-hunks` | Structured unified diff hunks |
| `--patch-stdin` / `--patch-file` | Route to `patch.validate` or `patch.hunks` |
| `--dry-run` / `--no-dry-run` | Set `dryRun` on supported mutations |
| `--raw-response` | Print full envelope; exit 1 when `ok:false` |
| `--compact` / `--json` | Single-line sorted JSON |
| `--error-json` | JSON error envelopes on stderr |
| `--verbose` | Diagnostic stderr (overrides `--quiet`) |
| `--batch-stdin` / `--batch-file` | NDJSON multi-call mode |
| `--listen` + `--listen-type` | Bounded event stream on stdout |
| `--self-test` | Offline client checks (no socket) |

See [Technical Architecture](technical-architecture.md) for details on how the Control Server is implemented within the macOS layer.
