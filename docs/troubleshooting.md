# Troubleshooting

> **Start here when something looks wrong.** Each section: symptom → first fix → deeper doc.

[← Doc index](README.md) · [← README quick fixes](../README.md#troubleshooting)

## Quick fix table

| What you see | Plain English | First command |
|--------------|---------------|---------------|
| “Kernel offline” / socket error | The engine isn’t running | `make restart-agent-server-fast` |
| Errors right after `git pull` | Old binary still running | `make kernel && make restart-agent-server-fast` |
| Patch blocked — “drift” | Files changed while agent worked | Refresh context in Cockpit Drift panel |
| Task waiting forever | Approval needed | Cockpit **Approvals** panel |
| Agent done but task not “completed” | Tests haven’t passed yet | Run verify from Cockpit |
| Not sure install is healthy | Baseline may be broken | `make checkpoint-core` |

---

## Kernel socket

**Symptom:** `socket not active`, `transport_error`, bridge banner “Kernel offline”.

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

**After `git pull` — stale binary:**

```bash
make kernel && make restart-agent-server-fast
```

Paths: socket `~/.dietcode/control.sock` · token `~/.dietcode/session.token` (mode `0600`).

---

## Bridge: invalid session token

**Symptom:** `kernelConnected: false`, `Invalid or missing session token`.

The bridge must send `token` at the **top level** of each kernel request (not inside `params`). Restart the bridge after a kernel restart so it reads the new token file.

```bash
pkill -f "tsx server/bridge.ts"
cd cockpit && npm run bridge
```

---

## Missing RPC method (e.g. `workspace.status`)

**Symptom:** `method_not_found`, `Unhandled file/workspace/search method`.

The running kernel is older than your source tree.

```bash
make kernel restart-agent-server-fast
```

---

## Workspace drift blocks patches

**Symptom:** `workspaceDriftRequired`, checkpoint 2 active, `workspace.drift.detected`.

**What it means:** Someone (or another tool) changed files after the agent read them. DietCode blocks the patch until you refresh or explicitly continue.

```bash
# Via bridge
curl -X POST http://127.0.0.1:9477/api/workspace/refresh-anchor

# Via kernel RPC
python3 scripts/dietcode_agent_client.py rpc workspace.refreshAnchor
```

Or use the Cockpit **Drift** panel → **Refresh context**.  
Deep dive: [workspace-drift.md](workspace-drift.md).

---

## Approval stuck

**Symptom:** Task `awaiting_approval`, pending approval in kernel.

```bash
curl http://127.0.0.1:9477/api/approvals?status=pending
curl -X POST http://127.0.0.1:9477/api/approvals/<id>/resolve \
  -H 'Content-Type: application/json' \
  -d '{"decision":"approved","resolvedBy":"cockpit"}'
```

Approvals expire after 30 minutes. See [approval-lifecycle.md](approval-lifecycle.md).

---

## Task completed before verify

**Symptom:** Agent exited 0 but task not `completed`.

**Expected behavior:** Mutations arm checkpoint 5. The task stays open until verify passes or is waived.

```bash
curl -X POST http://127.0.0.1:9477/api/tasks/<taskId>/run-verify \
  -H 'Content-Type: application/json' \
  -d '{}'
```

Or use the Cockpit verify controls. See [verify-gate.md](verify-gate.md).

---

## Verify command rejected

**Symptom:** `verify.run command must match AgentVerifyCommands prefixes`.

Allowed defaults include `make test`, `npm test`, `./verify.sh`. Custom commands need kernel allowlist or `AgentVerifyCommands` user defaults.

For subproject workspaces, the bridge passes `cwd` relative to kernel root when the task workspace is a subdirectory.

---

## `cockpit-smoke` failures

```bash
make cockpit-smoke 2>&1 | python3 -c "
import sys, json
for line in sys.stdin:
    if line.strip().startswith('{'):
        o=json.loads(line)
        if o.get('type')=='check' and not o.get('ok'):
            print(o)
"
```

Common causes:

- Kernel not restarted after C++ pull
- Port 9477 in use by stale bridge
- Fixture workspace not under kernel root (`build/cockpit-smoke-ws`)

Full gate docs: [testing.md](testing.md)

---

## Docs / contract drift

```bash
make test-docs-code-drift
```

Run after changing Makefile targets, error codes, or agent contracts.

---

## Error code lookup

```bash
rg 'string_code' docs/error-codes.md
```

Every failure envelope should include `string_code`, `recovery_hint`, and `nextRecommendedCommand` when applicable. Catalog: [error-codes.md](error-codes.md).

---

## Still stuck

1. `make checkpoint-core` — reproduces the full baseline on your machine
2. [getting-started.md](getting-started.md) — clean build path from scratch
3. [architecture.md](architecture.md) — which component owns what
4. [checkpoint-model.md](checkpoint-model.md) — which gate is blocking progress
