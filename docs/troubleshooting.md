# Troubleshooting

> **Start here when something looks wrong.**

[← Doc index](README.md) · [← README](../README.md#troubleshooting)

---

## Quick fix table

| What you see | Plain English | First command |
|--------------|---------------|---------------|
| Kernel offline / socket error | Engine not running | `make restart-agent-server-fast` |
| Errors after `git pull` | Stale binary | `make kernel && make restart-agent-server-fast` |
| Patch blocked — coherence | Stale agent context | Re-read with `taskId` — [coherence-tokens.md](coherence-tokens.md) |
| Patch blocked — drift | Files changed mid-task | `workspace.refreshAnchor` |
| Approval pending | Needs clearance | `approval.resolve` via RPC |
| Agent done, verify not passed | Tests not run | `verify.run` |
| Install health unknown | Baseline may be broken | `make validate` |

---

## Kernel socket

**Symptom:** `socket not active`, `transport_error`.

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

**After `git pull`:**

```bash
make kernel && make restart-agent-server-fast
```

Paths: `~/.dietcode/control.sock` · `~/.dietcode/session.token` (mode `0600`).

---

## Invalid session token

**Symptom:** `Invalid or missing session token`.

Send `token` at the **top level** of each RPC request. Restart kernel after rotation:

```bash
make restart-agent-server-fast
```

---

## Missing RPC method

**Symptom:** `method_not_found`.

Running kernel is older than source tree:

```bash
make kernel && make restart-agent-server-fast
```

---

## Coherence mismatch

**Symptom:** `coherence_mismatch`, `anchored_file_changed`.

The agent's coherence token no longer matches kernel revision or anchored content.

```bash
python3 scripts/dietcode_agent_client.py rpc file.read \
  --params '{"path":"src/foo.ts","taskId":"task_1"}'
```

Regenerate patch with fresh `coherenceTokenId` + `expectedWorkspaceRevision`.

See [coherence-tokens.md](coherence-tokens.md) and `scripts/dietcode_coherence.py`.

---

## Workspace drift

**Symptom:** `workspaceDriftRequired`, `workspace.drift.detected`.

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.refreshAnchor
```

Or supervised override via `workspace.continueAnyway`. See [workspace-drift.md](workspace-drift.md).

---

## Approval stuck

```bash
python3 scripts/dietcode_agent_client.py rpc approval.list
python3 scripts/dietcode_agent_client.py rpc approval.resolve \
  --params '{"approvalId":"appr_1","decision":"approved","resolvedBy":"operator"}'
```

Approvals expire after 30 minutes. [approval-lifecycle.md](approval-lifecycle.md).

---

## Verify not passed

```bash
python3 scripts/dietcode_agent_client.py rpc verify.run \
  --params '{"command":"make test"}'
```

[verify-gate.md](verify-gate.md).

---

## Verify command rejected

**Symptom:** `verify.run command must match AgentVerifyCommands prefixes`.

Defaults: `make test`, `make kernel`, `npm test`, `./verify.sh`. Customize via `AgentVerifyCommands` user defaults on macOS.

---

## Coherence test failures

```bash
make test-coherence-tokens
```

Common causes:

- Kernel not restarted after C++ pull
- Stale process holding socket

Full gate: [testing.md](testing.md) → `make validate`

---

## Docs / contract drift

```bash
make test-docs-code-drift
```

Run after changing Makefile targets, error codes, or `agent_contracts.py`.

---

## Error code lookup

```bash
rg 'coherence_mismatch' docs/error-codes.md
```

Every failure envelope should include `string_code`, `recovery_hint`, and `nextRecommendedCommand` when applicable.

---

## Still stuck

1. `make validate` — full archive health check
2. `make coherence-core-v0.1` — coherence baseline only
3. [getting-started.md](getting-started.md) — clean build path
4. [checkpoint-model.md](checkpoint-model.md) — which gate is blocking
