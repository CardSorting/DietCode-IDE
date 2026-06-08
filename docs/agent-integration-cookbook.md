# Agent Integration Cookbook: Practical Automation Recipes

This cookbook provides hands-on examples of orchestrating DietCode's RPC surface to build powerful autonomous agents and developer tools.

Run scripts from the repo root so `scripts/` is on the import path:

```bash
python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json
python3 scripts/control_smoke_test.py --compact
```

CLI grep/diff/patch shortcuts and the verification ladder live in [Headless Agent Control](headless-agent-control.md). Stable error codes: [Error Codes](error-codes.md). Full audit record: [Agent Runtime Audit](agent-runtime-audit.md).

**New agent integrations** should use the bundled [Agent Bridge](agent-bridge.md) (`DietCodeBridgeClient` / `dietcode-agent-client`) instead of raw RPC. See [Integration Guide](agent-bridge-integration-guide.md).

**Agent-safe surfaces:** prefer `search.literal`, `workspace.grep`, `search.references` — not `search.semantic` or score-ranked results.

## 🌉 Bridge recipe: Safe patch (TypeScript)

Preferred path for external agents:

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({ startApp: false });
await bridge.connect();

const outcome = await bridge.safePatchFile('src/foo.ts', unifiedDiff, {
  idempotencyKey: 'my-agent:foo:v1',
});

if (outcome.applied) {
  console.log(outcome.mutationReceipt, outcome.revisionAfter);
} else if (outcome.stale) {
  console.log('revalidate:', outcome.recoveryHint);
}

await bridge.close();
```

CLI equivalent:

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client patch safe-file src/foo.ts /tmp/foo.patch
```

## 🥣 Recipe 1: The "Self-Healing" Loop

Goal: Identify a compiler error, find the relevant symbol, apply a suggested fix, and verify with a build.

### Step 1: List current diagnostics
```python
from dietcode_agent_client import DietCodeAgentClient

with DietCodeAgentClient() as client:
    payload = client.call("diagnostics.list")
    errors = payload.get("diagnostics", [])
    target = next(e for e in errors if e.get("severity") == "error")
```

### Step 2: Find the symbol definition
```python
# Deterministic symbol lookup (no score ranking)
symbol = target["message"].split("'")[1]  # Extract symbol name from error msg
refs = client.call("search.references", {"symbol": symbol, "maxResults": 20})
results = refs.get("results", [])
definition = results[0]  # sorted path_line_column — first row is stable
```

### Step 3: Validate and apply a patch
```python
patch = f"""--- {definition['path']}
+++ {definition['path']}
@@ -10,1 +10,1 @@
- void problematic_func() {{
+ void corrected_func() {{
"""
validation = client.call("patch.validate", {"path": definition["path"], "patch": patch})
assert validation["ok"], validation.get("rejectedReason")
client.call("patch.apply", {
    "path": definition["path"],
    "patch": patch,
    "expectBeforeHash": validation["beforeContentHash"],
})
```

### Step 4: Verify the fix
```python
# Trigger a build and check the status
client.call("terminal.run", {"command": "make app"})
status = client.call("terminal.status")
```

---

## 🥣 Recipe 2: Workspace-Wide "TODO" Reporter

Goal: Scan the entire project for TODO comments and group them by file.

```python
# Use search.todo to get all results across the workspace
todos = client.call("search.todo", {"maxResults": 100})

# Group results by path in Python
from collections import defaultdict
report = defaultdict(list)
for item in todos["results"]:
    report[item["path"]].append(item["preview"])

for path, items in report.items():
    print(f"{path}: {len(items)} items")
```

---

## 🥣 Recipe 3: Remote "Follow-Me" Presentation

Goal: Synchronize another person's (or agent's) view to exactly where you are looking in the IDE.

```python
# Step A: Capture current state (on the 'leader' machine)
state = client.call("session.info")
# { "activeFile": "/src/main.mm", "workspace": "/Users/dev/DietCode" }

selection = client.call("editor.getSelection")
# { "start": 120, "end": 125 }

# Step B: Synchronize the 'follower' machine
client.call("workspace.openFile", {"path": state["activeFile"]})
client.call("editor.setSelection", {"start": selection["start"], "end": selection["end"]})
```

---

## 🥣 Recipe 4: Bulk Refactor with "Combos"

Goal: Perform a multi-file replacement atomically with a rollback safety net.

```python
# Define a Combo plan (chips use @version suffixes; see deterministic-combo-runtime-spec.md)
plan = {
    "schemaVersion": "1.6.2",
    "goal": "Refactor ClassName to NewClassName",
    "steps": [
        {
            "id": "step1",
            "chip": "file.write@1",
            "params": {"path": "src/OldClass.hpp", "content": "...new content..."}
        },
        {
            "id": "step2",
            "chip": "file.write@1",
            "params": {"path": "src/main.cpp", "content": "...updated main..."}
        }
    ],
    "budget": {"maxFilesTouched": 5}
}

# Run the combo transactionally
result = client.call("combo.run", {"combo": plan})

if result["status"] == "complete":
    print("Refactor successful!")
else:
    print(f"Refactor failed. Rollback triggered: {result['errors']}")
```

---

## 🥣 Recipe 5: Find-and-Patch Workflow (smoke test A)

Goal: Locate a symbol with deterministic search, validate, and apply with mutation receipt.

```python
from dietcode_agent_client import DietCodeAgentClient

with DietCodeAgentClient() as client:
    hits = client.call("search.literal", {
        "query": "CONTRACT:",
        "include": ["scripts/*.py"],
        "maxResults": 5,
    })
    assert hits.get("complete", True), hits.get("warnings", [])
    path = hits["results"][0]["path"]

    stat = client.call("file.stat", {"path": path})
    patch = "..."  # unified diff for path
    validation = client.call("patch.validate", {"path": path, "patch": patch})
    client.call("patch.apply", {
        "path": path,
        "patch": patch,
        "expectBeforeHash": validation["beforeContentHash"],
    })
    rev = client.call("workspace.revision")
    assert rev["revisionId"] >= 0
```

---

## 🥣 Recipe 6: Stale-Content Recovery (smoke test B)

Goal: Handle `stale_content` when the file changes between validate and apply.

```python
validation = client.call("patch.validate", {"path": path, "patch": patch})
# ... external process mutates file ...
try:
    client.call("patch.apply", {
        "path": path,
        "patch": patch,
        "expectBeforeHash": validation["beforeContentHash"],
    })
except Exception as e:
    # envelope: stale_content (4004), nextRecommendedCommand: patch.validate
    validation = client.call("patch.validate", {"path": path, "patch": corrected_patch})
    client.call("patch.apply", {
        "path": path,
        "patch": corrected_patch,
        "expectBeforeHash": validation["beforeContentHash"],
    })
```

---

## 🥣 Recipe 7: Deprecated Surface Recovery (smoke test D)

Goal: Migrate from quarantined `search.semantic` to agent-safe retrieval.

```python
try:
    client.call("search.semantic", {"query": "foo"})
except Exception:
    pass  # semantic_disabled (4008)

hits = client.call("search.literal", {"query": "foo", "maxResults": 10})
caps = client.call("tool.capabilities")
assert caps.get("semanticSearchDisabled") is True
```

---

## 💡 Best Practices for Agent Developers
- **Prefer CLI for inspection**: Use `--grep`, `--search-literal`, `--diff-hunks`, and `--raw-response` before writing Python wrappers. Exit codes reflect `ok:false` when `--raw-response` is set.
- **Validate before mutate**: Always `patch.validate` → `expectBeforeHash` → `patch.apply`. Check `mutationReceipt` and `workspace.revision` after success.
- **Respect partial success**: When `complete: false` or `partial: true`, follow `nextRecommendedCommand` — do not assume full scan coverage.
- **Avoid quarantined search**: Do not use `search.semantic` or `analysis.searchRanked` in agent loops; use `search.literal` / `workspace.grep`.
- **Use Paging**: For large workspace scans, always use `resultOffset` and `maxResults`.
- **Check Dirty Buffers**: Use `buffers.dirty` before applying patches to avoid conflicting with unsaved user changes.
- **Prefer Structured CLI Failures**: Add `--error-json` when invoking `scripts/dietcode_agent_client.py` from automation. Successful responses stay on stdout; JSON error envelopes are written to stderr.
- **Listen for Events on a Dedicated Socket**: Use `DietCodeAgentClient.event_subscription(...)`, `iter_events(...)`, or `event.subscribe` to avoid polling. The Python helper can skip interleaved `event.emitted` frames while waiting for a matching response id, and event iterators drain the same shared socket buffer as request/response calls. Long-running listeners should still use a separate connection from synchronous request/response RPC calls.
- **Filter CLI Event Streams**: Use `python3 scripts/dietcode_agent_client.py --listen --listen-type terminal.output` when you only need specific events. Repeat `--listen-type` for multiple subscriptions, and add `--listen-max-events N` or `--listen-idle-timeout SECONDS` for bounded automation. Event frames stay on stdout; listener status text goes to stderr unless `--quiet` is set.
- **End Event Lifecycles Cleanly**: Call `event.unsubscribe` before a long-running listener exits. The helper scopes temporary socket timeouts per call, so short listener polls do not leak into later RPC calls on the same socket.
- **Handle Headless Fallbacks**: In headless mode, UI-adjacent methods can return `headless: true` with stable non-UI results. Treat those as successful capability probes rather than editor navigation.
