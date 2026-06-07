# Headless Agent Control

DietCode exposes a high-fidelity local Unix socket control surface designed for deep integration with automation tools and AI agents.

**Socket Path:** `~/.dietcode/control.sock`
**Protocol:** Newline-delimited JSON-RPC (2.0-style)
**Authentication:** Requires a session token from `~/.dietcode/session.token`

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

### Workspace & Search
- `workspace.getRoot`: Get the absolute path of the opened workspace.
- `workspace.openFolder`: Change the active workspace.
- `workspace.findFiles`: Discover files using glob patterns (e.g., `src/**/*.hpp`).
- `workspace.listFiles`: Recursively list files in the workspace.
- `workspace.openFile`: Open a file in the editor.
- `workspace.grep`: Perform a high-speed literal substring scan across the workspace. Now includes absolute file offsets and lengths for match spans.
- `search.text`: Advanced text search with context and offsets.
- `search.files`: Find files by name/glob.
- `search.todo`: Scan for TODO/FIXME comments.
- `search.semantic`: In-memory semantic search (when indexed).

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
- `analysis.workspaceSummary`: Statistical overview of the workspace (languages, file counts).
- `symbols.document`: Extract a flat list of symbols (classes, functions, etc.) for a file. Now includes `offset` and `endOffset`.
- `symbols.hierarchy`: Extract a nested tree of symbols for a file, providing structural context.
- `symbols.references`: Find all usages of a specific symbol.
- `symbols.atCursor`: Identify the symbol under the editor cursor.

### Diff & Patch (Agent Optimized)
- `diff.chunk`: Read large diffs in chunks to avoid frame limits.
- `diff.hunks`: Get structured unified diff hunks with old/new line mapping.
- `patch.validate`: Dry-run a patch to check for conflicts or syntax dangers.
- `patch.apply`: Execute a patch with optional confirmation logic.
- `patch.applyBatch`: Apply multiple patches across multiple files atomically.

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

### Events (Duplex)
- `event.subscribe`: Listen for real-time notifications (e.g., `DocumentSaved`, `ActivityChanged`).
- `event.unsubscribe`: Stop listening for events.

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

See [Technical Architecture](technical-architecture.md) for details on how the Control Server is implemented within the macOS layer.
