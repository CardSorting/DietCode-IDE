# Troubleshooting

> **Start here when something looks wrong.** Each section: symptom → first fix → deeper doc.

[← Doc index](README.md) · [← README quick fixes](../README.md#troubleshooting)

## Quick fix table

| What you see | Plain English | First command |
|--------------|---------------|---------------|
| “Kernel offline” / socket error | The engine isn’t running | `make restart-agent-server-fast` |
| Errors right after `git pull` | Old binary still running | `make kernel && make restart-agent-server-fast` |
| Patch blocked — coherence | Agent context stale | Re-read with `taskId` — [coherence-tokens.md](coherence-tokens.md) |
| Patch blocked — “drift” | Files changed while agent worked | `workspace.refreshAnchor` |
| Approval pending | Mutation needs clearance | `approval.resolve` via RPC |
| Agent done but verify not passed | Tests haven’t passed yet | `verify.run` |
| Not sure install is healthy | Baseline may be broken | `make coherence-core-v0.1` |

---

## Kernel socket

**Symptom:** `socket not active`, `transport_error`.

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

## Invalid session token

**Symptom:** `Invalid or missing session token`.

Each kernel request must send `token` at the **top level** (not inside `params`). Restart the kernel after token rotation:

```bash
make restart-agent-server-fast
```

---

## Missing RPC method (e.g. `workspace.status`)

**Symptom:** `method_not_found`, `Unhandled file/workspace/search method`.

The running kernel is older than your source tree.

```bash
make kernel restart-agent-server-fast
```

---

## Coherence mismatch

**Symptom:** `coherence_mismatch`, `anchored_file_changed`.

**What it means:** The agent’s coherence token no longer matches kernel revision or anchored file content.

```bash
python3 scripts/dietcode_agent_client.py rpc file.read \
  --params '{"path":"src/foo.ts","taskId":"task_1"}'
# Regenerate patch with fresh coherenceTokenId + expectedWorkspaceRevision
```

See [coherence-tokens.md](coherence-tokens.md) and `scripts/dietcode_coherence.py`.

---

## Workspace drift blocks patches

**Symptom:** `workspaceDriftRequired`, checkpoint 2 active, `workspace.drift.detected`.

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.refreshAnchor
```

Or `workspace.continueAnyway` for supervised override.  
Deep dive: [workspace-drift.md](workspace-drift.md).

---

## Approval stuck

**Symptom:** `approvalRequired`, pending approval in kernel.

```bash
python3 scripts/dietcode_agent_client.py rpc approval.list
python3 scripts/dietcode_agent_client.py rpc approval.resolve \
  --params '{"approvalId":"appr_1","decision":"approved","resolvedBy":"operator"}'
```

Approvals expire after 30 minutes. See [approval-lifecycle.md](approval-lifecycle.md).

---

## Verify not passed

**Symptom:** Mutation applied but verify gate still active.

```bash
python3 scripts/dietcode_agent_client.py rpc verify.run \
  --params '{"command":"make test"}'
```

See [verify-gate.md](verify-gate.md).

---

## Verify command rejected

**Symptom:** `verify.run command must match AgentVerifyCommands prefixes`.

Allowed defaults include `make test`, `npm test`, `./verify.sh`. Custom commands need kernel allowlist or `AgentVerifyCommands` user defaults.

---

## Coherence test failures

```bash
make test-coherence-tokens 2>&1 | python3 -c "
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
- Socket owned by stale process

Full gate: [testing.md](testing.md)

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

1. `make coherence-core-v0.1` — reproduces the coherence baseline on your machine
2. [getting-started.md](getting-started.md) — clean build path from scratch
3. [architecture.md](architecture.md) — which component owns what
4. [checkpoint-model.md](checkpoint-model.md) — which gate is blocking progress
