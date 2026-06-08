# Legacy Native UI

The original DietCode AppKit editor shell lives here. It is **not** part of the active product surface.

DietCode is now a headless local agent-control kernel (`dietcode-kernel`) with a separate web cockpit. The native UI remains only for optional editor integration and backward compatibility.

```text
agent / user
    ↓
cockpit UI          ← active product surface
    ↓
local bridge API
    ↓
dietcode-kernel     ← sole workspace mutation authority
    ↓
workspace
```

**Hard rule:** The cockpit (and any UI) never edits files directly. Only the kernel mutates the workspace.

## Build

```bash
make legacy-app    # builds DietCode.app with this UI
make kernel        # builds dietcode-kernel (headless, default)
```

## Contents

| Path | Role |
|------|------|
| `macos/ui/` | AppKit shell — MacWindow, menus, editor views, terminal |
| `macos/MacAgentSidebar.*` | Native agent chat sidebar |
| `macos/main.mm` | Legacy app entry (`DietCode.app`) |
