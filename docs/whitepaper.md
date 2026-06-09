# DietCode governed mutation runtime

**Technical whitepaper for the kernel/coherence-core archive**

Version 1.1 · June 2026 · Baseline **coherence-core-v0.1**  
Philosophy: [philosophy.md](philosophy.md) · Brief: [brief.md](brief.md) · Archive: [ARCHIVE.md](../ARCHIVE.md)

---

## Abstract

Autonomous coding agents introduce a structural problem: **mutation**, **orchestration**, and **operator visibility** are typically fused into a single opaque interface. Operators cannot see which safety precondition failed, whether the workspace changed mid-task, or whether “done” means verified or merely attempted.

DietCode addresses this as a **governed local mutation kernel** for macOS, now preserved as a **kernel/coherence-core archive**. The deliverable is not an application binary for end users. The deliverable is a **reproducible baseline**:

1. Headless `dietcode-kernel` — sole workspace mutation authority
2. Operational coherence enforcement (v0.1) — task-scoped tokens before drift
3. Python harnesses — live tests + deterministic recovery smoke
4. Contract-locked documentation — `make test-docs-code-drift`

Agents integrate through JSON-RPC (`scripts/dietcode_agent_client.py`). They request clearance; they do not write files directly.

Six checkpoints sit between agent intent and task completion. Agent process exit does not imply success.

This document specifies the archive strategy, problem framing, coherence model, architecture, wire contracts, validation matrix, and relationship to frozen adversarial research at [benchmarks/agent_success/WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md).

---

## 1. Archive strategy

### 1.1 What changed

DietCode previously included experimental product surfaces used to prove checkpoint visibility in realistic operator workflows:

| Removed surface | Former role |
|---------------|-------------|
| `cockpit/` | React UI + HTTP task API |
| `legacy_ui/` | AppKit editor shell |
| `agent-bridge/` | TypeScript client workflows |
| `integrations/` | Hermes plugin wiring |
| Editor scaffold | C++ IDE experiment (`src/editor/`, etc.) |

These surfaces demonstrated that humans and agents could **observe** drift, approvals, and verify state during live tasks. Once demonstrated, they became optional for the **kernel claim**.

### 1.2 What was retained

| Retained | Rationale |
|----------|-----------|
| `dietcode-kernel` | Mutation authority — the non-negotiable core |
| Control plane + coherence tokens | Enforcement primitive for v0.1 |
| Python CLI + `dietcode_coherence.py` | Integration without bridge dependency |
| Live tests + recovery fixtures | Falsifiable proof |
| `make validate` | CI-equivalent archive gate |

Detail: [archive-note.md](archive-note.md).

### 1.3 What “coherence-core-v0.1” means

**coherence-core-v0.1** is a frozen tag marking a machine-verifiable baseline:

```bash
make validate
```

| Sub-gate | Proves |
|----------|--------|
| `test-coherence-tokens-fast` | Token issuance on task-scoped reads; `coherence_mismatch` blocks stale writes |
| `coherence-recovery-smoke-fast` | Python recovery: stale block → re-read → retry → verify |
| `test-docs-code-drift` | Docs, Makefile, and `agent_contracts.py` stay aligned |

This is the archive's **release artifact**. Benchmark stress results are research evidence, not substitutes.

---

## 2. Problem statement

### 2.1 Four confounded questions

| # | Question |
|---|----------|
| Q1 | Who is allowed to mutate the workspace? |
| Q2 | Under what preconditions may a mutation proceed? |
| Q3 | How does the operator observe progress and failure? |
| Q4 | When may a task be called *done*? |

When Q1–Q4 collapse into chat, operators develop false confidence.

### 2.2 Control-plane failure modes

| Failure | Symptom | DietCode response |
|---------|---------|-------------------|
| Stale context | Patch from outdated read | Coherence token + `coherence_mismatch` |
| Workspace drift | External edit mid-task | Drift gate + `workspace.refreshAnchor` |
| Uncleared mutation | Agent writes without approval | `approvalRequired` at autonomy 3 |
| Silent success | Agent exits, tests fail | Verify gate blocks completion |
| Authority leakage | Multiple writers | Kernel-only mutation |

These are **runtime** failures, not model failures.

### 2.3 Design goal

> **Bounded autonomy through visible checkpoints** — air-traffic control for AI edits.

---

## 3. Design principles

### 3.1 Single mutation authority

Exactly one component applies patches: `dietcode-kernel`. All other clients are RPC requesters.

### 3.2 Coherence before drift

For governed tasks (`taskId` set), the kernel evaluates **coherence first**:

```text
patch.apply request
  → coherence token valid?     (precise: which anchors changed)
  → drift detected?            (broad: workspace state stale)
  → approval required?
  → apply + receipt
```

This ordering prevents agents from receiving only a broad drift signal when the fix is a targeted re-read.

### 3.3 Checkpoints as gates

Each capability maps to one of six questions (§4). Non-gate features belong in transport hygiene or observability.

### 3.4 Legible failure

Errors include `string_code`, `recovery_hint`, `nextRecommendedCommand` ([error-codes.md](error-codes.md)).

### 3.5 Completion is a system state

| State | Meaning |
|-------|---------|
| Agent exited | Process ended — **not** completion |
| `verification_required` | Mutation occurred; verify pending |
| `verified` | Verify passed |
| `completed` | Checkpoint 6 cleared |

### 3.6 Local-first trust boundary

macOS process + Unix socket (`~/.dietcode/control.sock`) + local workspace. No cloud kernel required.

### 3.7 Archive provability

Claims must be executable:

```bash
make validate
```

---

## 4. Checkpoint model

| # | Name | Question | Primary enforcement |
|---|------|----------|---------------------|
| 1 | Context | Did the agent read valid state? | Hash anchors; coherence tokens |
| 2 | Drift | Did the workspace change underneath it? | `driftDetected` blocks Edit/Destructive |
| 3 | Approval | Is this mutation allowed? | `approvalRequired` → `approval.resolve` |
| 4 | Mutation | Did the patch apply cleanly? | `patch.validate` → `patch.apply` |
| 5 | Verification | Did the result pass? | `verify.run` |
| 6 | Completion | Can this task be called done? | Verify state + harness semantics |

```text
read (1) → drift (2) → approval (3) → patch (4) → verify (5) → completed (6)
```

Noise bucket (not gates): kernel reconnect, session reload, log tail, benchmark journal. See [checkpoint-model.md](checkpoint-model.md).

---

## 5. Operational coherence (v0.1)

### 5.1 Token issuance

When `taskId` is set, these reads issue coherence payloads:

- `file.read`
- `file.readBatch`
- `file.readRange`
- `file.readAround`
- `file.stat`
- `workspace.status`

Response keys: `tokenId`, `workspaceRevision`, `verifyRevision`, `anchors` (content hashes per path).

### 5.2 Mutation binding

`patch.apply` / `patch.applyBatch` with `taskId` require:

```json
{
  "coherenceTokenId": "coh_123",
  "expectedWorkspaceRevision": 41
}
```

### 5.3 Stale handling

```json
{
  "string_code": "coherence_mismatch",
  "changedPaths": ["src/foo.ts"],
  "requiredAction": "refresh_context"
}
```

Python recovery: `scripts/dietcode_coherence.py` — one automatic retry after re-read; then `coherence.operator_required`.

Smoke: `scripts/coherence_recovery_smoke.py`.

Full spec: [coherence-tokens.md](coherence-tokens.md).

---

## 6. System architecture

```text
┌─────────────────────────────────────────────────────────┐
│  Agents / harnesses / CI (Python)                       │
│  dietcode_agent_client.py · dietcode_coherence.py       │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON lines + session.token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel (C++/ObjC++)                           │
│  MacControlServer                                       │
│  ├─ MacControlCoherenceTokens.mm                        │
│  ├─ MacControlApprovalService.mm                        │
│  ├─ MacControlWorkspaceState.mm (drift)                 │
│  └─ MacControlPatchService.mm                           │
│  WorkspaceSession · recovery store                      │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

No in-tree HTTP server. No TypeScript bridge. Integration is socket RPC.

Detail: [architecture.md](architecture.md) · [file-structure.md](file-structure.md).

### 6.1 Build and performance

Kernel compiles incrementally to `build/obj/` (~1s typical rebuild). `coherence-core-v0.1` builds once per validate run, then uses fast test targets.

---

## 7. Wire contracts

### 7.1 Request envelope

```json
{
  "id": "uuid",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": {},
  "token": "<session.token>"
}
```

Token at top level — not inside `params`. Catalog: [kernel-rpc.md](kernel-rpc.md).

### 7.2 Autonomy

Default level **3 (supervised)**. Destructive RPCs queue `approvalRequired` until `approval.resolve`.

### 7.3 Agent-safe tooling

Deterministic search/patch surfaces exposed via `tool.registry` / `tool.capabilities`. Semantic and ranked search quarantined (`semantic_disabled`, `ranked_search_disabled`).

Contracts: [agent-tooling.md](agent-tooling.md) · Invariants: [runtime-invariants.md](runtime-invariants.md).

---

## 8. Recovery and session semantics

Bounded persistence under `~/.dietcode/session/`:

| File | Role |
|------|------|
| `pending_approvals.json` | Kernel approval cache |
| `recent_events.ndjson` | Rolling event window |
| `recent_diffs.json` | Lightweight diff previews |

Kernel restart: `make restart-agent-server-fast` + `--wait-ready`. No silent auto-resume into drift or verify failure.

Coherence recovery is harness-driven (`dietcode_coherence.py`), not bridge-driven.

Detail: [session-recovery.md](session-recovery.md).

---

## 9. Verification routing

After `workspace.mutated`, checkpoint 5 arms. `dietcode_verification_authority.py` resolves:

1. `./verify.sh`
2. `make test`
3. `npm test`

```bash
python3 scripts/dietcode_agent_client.py rpc verify.run \
  --params '{"command":"./verify.sh","taskId":"task_1"}'
```

Detail: [verify-gate.md](verify-gate.md).

---

## 10. Validation matrix

| Command | When to run | Scope |
|---------|-------------|-------|
| `make validate` | CI, post-change, “is archive healthy?” | Coherence + docs drift |
| `make coherence-core-v0.1` | Kernel/coherence changes | Baseline only |
| `make test-coherence-tokens` | After C++ pull | Rebuild + live token tests |
| `make verify-agent-runtime-full` | RPC contract changes | Broader harness ladder |
| `benchmarks/agent_success/` | Research only | Frozen — bridge required to re-run |

GitHub Actions: `.github/workflows/coherence-core.yml` → `make validate` on macOS.

Detail: [testing.md](testing.md).

---

## 11. Comparison to common patterns

| Pattern | Limitation | Archive approach |
|---------|------------|------------------|
| Chat-native IDE plugin | Unclear mutation authority | Kernel-only writes |
| Agent exits → done | Verify may not run | Verify gate |
| Reactive file watchers | Not gated | Drift gate before patch |
| Cloud agent sandbox | Remote trust boundary | Local socket + approvals |
| Monolithic product repo | Zombie surfaces | Explicit archive + validate gate |
| Bridge-dependent tests | Break when bridge removed | Python harnesses gate baseline |

---

## 12. Threat and safety framing

| Risk | Mitigation |
|------|------------|
| Unauthorized write | Single kernel authority |
| Stale patch | Coherence + drift + `expectBeforeHash` |
| Symlink escape | Shell/search policies ([runtime-invariants.md](runtime-invariants.md)) |
| Unverified ship | Verify gate |
| Token leakage | `0600` socket dir |
| Narrative drift | `test-docs-code-drift` in validate |

DietCode does not replace code review or org security policy. It makes **agent-mediated mutation** auditable and gate-enforced on one machine.

---

## 13. Limitations and non-goals

| Limitation | Notes |
|------------|-------|
| macOS only | Control plane targets macOS at this baseline |
| No in-tree UI | Cockpit/editor archived |
| No in-tree bridge | TypeScript client removed; Python integration path |
| Not fully autonomous | Bounded by design |
| Not cloud-hosted | Local socket model |
| Benchmarks not gated | Research corpus preserved separately |

---

## 14. Conclusion

DietCode reframes agentic coding as **governed mutation**: one authority, coherence tokens before drift, six checkpoints, legible failure, completion tied to verification.

The **kernel/coherence-core archive** exists so these claims remain **executable** after product surfaces are removed. Run `make validate` on your machine. Tag **coherence-core-v0.1** when green.

The tower remains. The terminal was never the point.

---

## References

| Document | Content |
|----------|---------|
| [philosophy.md](philosophy.md) | Values and archive honesty |
| [brief.md](brief.md) | Executive companion |
| [checkpoint-model.md](checkpoint-model.md) | Gate specification |
| [coherence-tokens.md](coherence-tokens.md) | Coherence v0.1 spec |
| [kernel-rpc.md](kernel-rpc.md) | RPC reference |
| [testing.md](testing.md) | Validation ladder |
| [archive-note.md](archive-note.md) | Removed surfaces |
| [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) | Parallel research track |
