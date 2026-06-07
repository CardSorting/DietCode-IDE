# Agent Integration Cookbook: Practical Automation Recipes

This cookbook provides hands-on examples of orchestrating DietCode's RPC surface to build powerful autonomous agents and developer tools.

## 🥣 Recipe 1: The "Self-Healing" Loop

Goal: Identify a compiler error, find the relevant symbol, apply a suggested fix, and verify with a build.

### Step 1: List current diagnostics
```python
# Call diagnostics.list to get all active errors
errors = client.call("diagnostics.list")
target = [e for e in errors if e["severity"] == "error"][0]
```

### Step 2: Find the symbol definition
```python
# Use symbols.references to find where the problematic symbol is defined
symbol = target["message"].split("'")[1] # Extract symbol name from error msg
refs = client.call("symbols.references", {"symbol": symbol})
definition = [r for r in refs if r["score"] > 1.5][0]
```

### Step 3: Apply a patch
```python
# Generate a unified diff and apply it via patch.apply
patch = f"""--- {definition['path']}
+++ {definition['path']}
@@ -10,1 +10,1 @@
- void problematic_func() {{
+ void corrected_func() {{
"""
client.call("patch.apply", {"path": definition["path"], "patch": patch})
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
# Define a Combo plan
plan = {
    "schemaVersion": "1.6.2",
    "goal": "Refactor ClassName to NewClassName",
    "steps": [
        {
            "id": "step1",
            "chip": "file.write",
            "params": {"path": "src/OldClass.hpp", "content": "...new content..."}
        },
        {
            "id": "step2",
            "chip": "file.write",
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

## 💡 Best Practices for Agent Developers
- **Use Paging**: For large workspace scans, always use `resultOffset` and `maxResults`.
- **Check Dirty Buffers**: Use `buffers.dirty` before applying patches to avoid conflicting with unsaved user changes.
- **Listen for Events on a Dedicated Socket**: Use `event.subscribe` to avoid polling. The Python helper can skip interleaved `event.emitted` frames while waiting for a matching response id, but long-running listeners should still use a separate connection from synchronous request/response RPC calls.
- **Handle Headless Fallbacks**: In headless mode, UI-adjacent methods can return `headless: true` with stable non-UI results. Treat those as successful capability probes rather than editor navigation.
