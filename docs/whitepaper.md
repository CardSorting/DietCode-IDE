# DietCode Governed Mutation Runtime

**A whitepaper on local control-plane architecture for supervised agent code mutation**

Version 1.0 · June 2026 · Baseline `coherence-core-v0.1`  
Philosophy: [philosophy.md](philosophy.md) · Brief: [brief.md](brief.md)

---

## Abstract

Autonomous coding agents introduce a structural problem: **mutation**, **orchestration**, and **operator visibility** are typically fused into a single opaque interface. Operators cannot see which safety precondition failed, whether the workspace changed mid-task, or whether “done” means verified or merely attempted.

DietCode is a **governed local mutation kernel** for macOS. A headless C++ process (`dietcode-kernel`) holds sole workspace mutation authority. Agents and harnesses integrate through JSON-RPC (`scripts/dietcode_agent_client.py`) — they request clearance; they do not write files directly. Operational coherence is enforced via task-scoped coherence tokens before drift, approval, and verify gates.

The runtime enforces **six checkpoints** (context, drift, approval, mutation, verification, completion) between agent intent and task completion. Agent process exit does not imply success. Tasks reach `completed` only when verification passes or is explicitly waived.

This document specifies the problem framing, design principles, checkpoint model, system architecture, wire contracts, recovery semantics, release baseline, and relationship to parallel reliability evaluation. It is the product/runtime whitepaper — distinct from the adversarial benchmark whitepaper at [benchmarks/agent_success/WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md).

---

## 1. Problem statement

### 1.1 Four confounded questions

Most “AI IDE” products answer these implicitly and conflate them in UI:

| # | Question |
|---|----------|
| Q1 | Who is allowed to mutate the workspace? |
| Q2 | Under what preconditions may a mutation proceed? |
| Q3 | How does the operator observe progress and failure? |
| Q4 | When may a task be called *done*? |

When Q1–Q4 collapse into chat, operators develop false confidence: fluent prose masks stale patches, drift collisions, unverified edits, and silent disconnects.

### 1.2 Failure modes in the wild

Predictable agent-runtime failures include:

- **Stale context** — patch based on files that changed after read
- **Wrong-file mutation** — correct pattern applied to decoy or sibling path
- **Silent success** — agent exits 0 while tests fail or verify never ran
- **Authority leakage** — UI or plugin writes files outside a single enforcement point
- **Unbounded session** — restart loses task state; operator cannot resume safely

DietCode addresses these as **control-plane** failures, not model failures.

### 1.3 Design goal

> Provide **bounded autonomy through visible checkpoints** — air-traffic control for AI edits.

---

## 2. Design principles

### 2.1 Single mutation authority

Exactly one component applies patches: `dietcode-kernel`. Agents and harnesses propose operations via RPC; the kernel enforces coherence, permissions, drift, approvals, and receipts.

### 2.2 Checkpoints as gates, not features

Each governed capability maps to one of six questions (see §3). Features that do not answer a checkpoint question belong in transport hygiene, recovery, or observability — not the gate set.

### 2.3 Legible failure

Every block should surface: which gate fired, which files are affected, and the next operator or agent action. Error envelopes include `string_code`, `recovery_hint`, and `nextRecommendedCommand` where applicable ([error-codes.md](error-codes.md)).

### 2.4 Completion is a system state

| State | Meaning |
|-------|---------|
| Agent exited | Process ended — **not** completion |
| `verification_required` | Mutation occurred; verify not yet run |
| `verified` | Verify passed |
| `verification_waived` | Operator override at checkpoint 5 |
| `completed` | Checkpoint 6 cleared |

### 2.5 Local-first trust boundary

Default deployment: macOS process + local Unix socket (`~/.dietcode/control.sock`) + local workspace. No cloud kernel required for the checkpoint loop.

### 2.6 Frozen baseline provability

Coherence-layer changes must pass `make coherence-core-v0.1` before release. Tag: `coherence-core-v0.1`.

---

## 3. Checkpoint model

A checkpoint is a **single question** the control plane must answer before proceed or done.

| # | Name | Question | Primary enforcement |
|---|------|----------|---------------------|
| 1 | Context | Did the agent read valid state? | Hash anchors; stale reads surface at 2 or 4 |
| 2 | Drift | Did the workspace change underneath it? | `driftDetected` blocks Edit/Destructive RPCs |
| 3 | Approval | Is this mutation allowed? | `approvalRequired` → `approval.resolve` |
| 4 | Mutation | Did the patch apply cleanly? | `patch.validate` → `patch.apply` + receipt |
| 5 | Verification | Did the result pass? | `verify.run`; arms on `workspace.mutated` |
| 6 | Completion | Can this task be called done? | Governed task registry + verify state |

```text
prompt → read (1) → drift (2) → approval (3) → patch (4) → verify (5) → completed (6)
```

### 3.1 Noise bucket (non-checkpoints)

These support the loop but are **not** gates: kernel reconnect, bridge reload, SSE staleness, session export, log tail, chat entry, timeline audit, benchmark journal. See [checkpoint-model.md](checkpoint-model.md).

### 3.2 Operator overrides

| Override | Checkpoint | Semantics |
|----------|------------|-----------|
| Refresh context | 2 | Re-anchor reads after drift |
| Continue anyway | 2 | Explicit accept of drift risk |
| Approve / reject | 3 | Human clearance |
| Waive verify | 5 | Explicit accept of unverified completion |
| Recovery restore | Noise | Bounded session reload — requires intent |

Waive does not bypass drift or approval.

---

## 4. System architecture

```text
┌─────────────────────────────────────────────────────────┐
│  Agents / harnesses (Python CLI, scripts, CI)           │
│  scripts/dietcode_agent_client.py · dietcode_coherence  │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON lines + session token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel (C++/ObjC++)                           │
│  MacControlServer · coherence tokens · WorkspaceSession │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

Experimental cockpit, HTTP bridge, and TypeScript agent-bridge surfaces were archived after proving the model. See [archive-note.md](archive-note.md).

Detail: [architecture.md](architecture.md).

### 4.1 Component responsibilities

| Component | Owns |
|-----------|------|
| Kernel | File mutation, coherence tokens, patch apply, verify execution, drift anchoring, approval queue |
| Python CLI | RPC transport, harness orchestration, coherence recovery helpers |

### 4.2 Governed agent path

```text
file.read (taskId) → coherence token (1)
  → patch.apply → approval if supervised (2–3)
  → workspace.mutated (4) → verify.run (5)
  → harness marks completed (6)
```

Recovery smoke: `scripts/coherence_recovery_smoke.py`. See [coherence-tokens.md](coherence-tokens.md).

---

## 5. Wire contracts

### 5.1 Kernel RPC

Single-line JSON requests on Unix socket:

```json
{
  "id": "uuid",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": { },
  "token": "<session.token>"
}
```

Responses: `{ "id", "ok", "result" }` or structured `error` with `string_code`. Token at **top level** — not nested in `params`.

Catalog: [kernel-rpc.md](kernel-rpc.md).

### 5.2 Bridge HTTP

| Endpoint | Role |
|----------|------|
| `POST /api/tasks` | Submit governed task |
| `GET /api/tasks/:id/checkpoints` | Checkpoint pipeline snapshot |
| `GET /api/checkpoints` | Active task checkpoints |
| `POST /api/tasks/:id/run-verify` | Arm / run checkpoint 5 |
| `POST /api/approvals/:id/resolve` | Clear checkpoint 3 |

Events stream via SSE; session ring in `~/.dietcode/session/`.

### 5.3 Autonomy default

Autonomy level **3 (supervised)**. Destructive RPCs queue `approvalRequired` until resolved in Cockpit or via RPC.

---

## 6. Recovery and session semantics

Bridge persists:

- `active_tasks.json`
- `recent_events.ndjson`
- `recent_diffs.json`
- `pending_approvals.json`

On bridge restart, `bootstrapSessionRecovery` reloads bounded state. Tasks may show `disconnected` until operator restores — no silent auto-resume into drift or verify failure.

Detail: [session-recovery.md](session-recovery.md).

---

## 7. Verification routing

After mutation, `workspace.mutated` arms checkpoint 5. Harnesses resolve verify command via `dietcode_verification_authority.py`:

1. `./verify.sh`
2. `make test`
3. `npm test`

Subproject workspaces pass `cwd` relative to kernel root in `verify.run`.

Detail: [verify-gate.md](verify-gate.md).

---

## 8. Release baseline and evidence

### 8.1 coherence-core gate

```bash
make coherence-core-v0.1
```

| Step | Proves |
|------|--------|
| `test-coherence-tokens` | Kernel coherence issuance + enforcement |
| `coherence-recovery-smoke-fast` | Stale block → refresh → retry → verify |

Fixtures: `scripts/fixtures/coherence_recovery/`. Detail: [testing.md](testing.md).

### 8.2 Parallel reliability track

Adversarial benchmarks (`benchmarks/agent_success/`) evaluate runtime contracts under trap-heavy fixtures. They produce mutation traces and release gates for research — **not** a substitute for `coherence-core-v0.1`. See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md).

---

## 9. Comparison to common patterns

| Pattern | Limitation | DietCode approach |
|---------|------------|-------------------|
| Chat-native IDE plugin | Mutation authority unclear | Kernel-only writes |
| Agent exits → PR opened | Verify may not have run | Verify gate blocks completion |
| File watcher heuristics | Reactive, not gated | Drift gate before patch |
| Cloud agent sandbox | Remote trust boundary | Local socket + operator approvals |
| Unbounded conversation | No completion semantics | Governed tasks with checkpoint 6 |

---

## 10. Threat and safety framing

| Risk | Mitigation |
|------|------------|
| Unauthorized write | Single kernel authority; supervised approvals |
| Stale patch | Drift detection + hash validation |
| Symlink escape | Shell and search policies ([runtime-invariants.md](runtime-invariants.md)) |
| Silent hang | Disconnect visibility; approval expiry |
| Unverified ship | Verify gate; waive requires explicit operator action |
| Token leakage | `0600` socket dir; token at RPC top level |

DietCode does not replace code review or org-wide security policy. It makes **agent-mediated mutation** auditable and gate-enforced on one machine.

---

## 11. Limitations and non-goals

- **macOS only** for the kernel control plane at this baseline
- **Not** a general-purpose IDE — UI surfaces were archived
- **Not** model-specific — any agent client may use kernel RPC
- **Not** fully autonomous coding — bounded autonomy by design
- **Not** cloud-hosted multi-tenant control plane in v0.1

---

## 12. Conclusion

DietCode reframes agentic coding as **governed mutation**: one authority, coherence tokens, six checkpoints, legible failure, and completion semantics tied to verification.

The frozen baseline `coherence-core-v0.1` exists so that claims about operational coherence remain **executable**, not aspirational. Run the gate, enforce the tokens, and call a task done only when verify clears.

---

## References

| Document | Content |
|----------|---------|
| [philosophy.md](philosophy.md) | Values and operational worldview |
| [brief.md](brief.md) | Executive companion |
| [checkpoint-model.md](checkpoint-model.md) | Gate specification + feature audit |
| [architecture.md](architecture.md) | Implementation map |
| [coherence-tokens.md](coherence-tokens.md) | Coherence token model |
| [kernel-rpc.md](kernel-rpc.md) | RPC reference |
| [archive-note.md](archive-note.md) | Removed experimental surfaces |
| [benchmarks/agent_success/WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md) | Adversarial evaluation instrument |
