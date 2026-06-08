# DietCode Governed Mutation Runtime

**A whitepaper on local control-plane architecture for supervised agent code mutation**

Version 1.0 · June 2026 · Baseline `checkpoint-core-v0.1`  
Philosophy: [philosophy.md](philosophy.md) · Brief: [brief.md](brief.md)

---

## Abstract

Autonomous coding agents introduce a structural problem: **mutation**, **orchestration**, and **operator visibility** are typically fused into a single opaque interface. Operators cannot see which safety precondition failed, whether the workspace changed mid-task, or whether “done” means verified or merely attempted.

DietCode is a **governed local mutation runtime** for macOS. A headless C++ kernel holds sole workspace mutation authority. A TypeScript bridge orchestrates bounded tasks with session recovery. A React Cockpit provides checkpoint-aligned supervision. External agents integrate through a TypeScript Agent Bridge or JSON-RPC CLI — they request clearance; they do not write files directly.

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

Exactly one component applies patches: `dietcode-kernel`. The Cockpit, bridge, and agents propose operations; the kernel enforces permissions, drift, approvals, and receipts.

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

Control-loop changes must pass `make checkpoint-core` before release. Tag: `checkpoint-core-v0.1`.

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
│  Cockpit (Vite + React) — :5173 dev UI                  │
│  CheckpointRail · Drift · Approval · Verify · Timeline  │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTP + SSE
┌───────────────────────▼─────────────────────────────────┐
│  Bridge (cockpit/server/) — :9477                       │
│  taskRegistry · sessionStore · checkpoints · verifyGate   │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON lines + session token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel (C++/ObjC++)                           │
│  MacControlServer · WorkspaceSession                    │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

**Agent Bridge** (`agent-bridge/`) provides TypeScript workflows (`safePatchFile`, `awaitApproval`, `awaitWorkspaceDrift`) for Hermes, scripts, and CI. Path: agent → bridge → kernel RPC.

Detail: [architecture.md](architecture.md).

### 4.1 Component responsibilities

| Component | Owns |
|-----------|------|
| Kernel | File mutation, patch apply, verify execution, drift anchoring, approval queue |
| Bridge | Governed tasks, SSE events, session persistence, checkpoint snapshots |
| Cockpit | Steering UI, approval/drift/verify panels, infrastructure banners |
| Agent bridge | Workflow API, error enrichment, packaging for external agents |

### 4.2 Governed task path

```text
POST /api/tasks → taskRunner spawns script → agent reads (1)
  → patch.apply → approval if supervised (2–3)
  → workspace.mutated (4) → verification_required (5)
  → run-verify → completed (6)
```

Modes: `supervised`, `trusted`, `smoke` (deterministic harness). See [governed-tasks.md](governed-tasks.md).

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

After mutation, `workspace.mutated` arms checkpoint 5. Bridge resolves verify command via:

1. `./verify.sh`
2. `make test`
3. `npm test`

Resolver: `cockpit/server/verifyCommandResolver.ts`. Subproject workspaces pass `cwd` relative to kernel root.

Detail: [verify-gate.md](verify-gate.md).

---

## 8. Release baseline and evidence

### 8.1 checkpoint-core gate

```bash
make checkpoint-core
```

| Step | Proves |
|------|--------|
| `make kernel` | Kernel compiles |
| `agent-bridge-fast` | Bridge package builds |
| `make cockpit` | UI + server types build |
| `make cockpit-smoke` | 53-check vertical slice |
| `test-checkpoint-core-unit` | Resolver, session, checkpoint unit tests |
| `test-docs-code-drift` | Docs ↔ contracts alignment |

### 8.2 Vertical slice fixtures

`scripts/fixtures/cockpit_smoke/`:

| Fixture | Verify |
|---------|--------|
| `npm-test/` | `npm test` |
| `make-test/` | `make test` |
| `verify-sh/` | `./verify.sh` |

Per fixture: task submit → drift → approval → mutation → verify → `completed` after verified; session survives bridge reload.

Orchestrator: `scripts/cockpit_vertical_slice.py`.

Detail: [testing.md](testing.md).

### 8.3 Parallel reliability track

Adversarial benchmarks (`benchmarks/agent_success/`) evaluate runtime contracts under trap-heavy fixtures. They produce mutation traces and release gates for research — **not** a substitute for `checkpoint-core`. See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md).

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
- **Not** a general-purpose IDE — `legacy_ui/` is optional compatibility
- **Not** model-specific — Hermes is optional integration
- **Not** fully autonomous coding — bounded autonomy by design
- **Not** cloud-hosted multi-tenant control plane in v0.1

---

## 12. Conclusion

DietCode reframes agentic coding as **governed mutation**: one authority, six checkpoints, legible failure, and completion semantics tied to verification. The architecture is intentionally separable — kernel, bridge, cockpit, agent bridge — so that each layer answers one class of operational question.

The frozen baseline `checkpoint-core-v0.1` exists so that claims about the control loop remain **executable**, not aspirational. Run the gate, watch the checkpoints, and call a task done only when the tower clears it.

---

## References

| Document | Content |
|----------|---------|
| [philosophy.md](philosophy.md) | Values and operational worldview |
| [brief.md](brief.md) | Executive companion |
| [checkpoint-model.md](checkpoint-model.md) | Gate specification + feature audit |
| [architecture.md](architecture.md) | Implementation map |
| [governed-tasks.md](governed-tasks.md) | Task API |
| [agent-bridge.md](agent-bridge.md) | External agent integration |
| [benchmarks/agent_success/WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md) | Adversarial evaluation instrument |
