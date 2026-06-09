# DietCode in brief

**Executive companion to the kernel/coherence-core archive.**

[Philosophy →](philosophy.md) · [Whitepaper →](whitepaper.md) · [README →](../README.md) · [ARCHIVE →](../ARCHIVE.md)

---

## One sentence

**DietCode is a frozen macOS archive** that proves operational coherence across agent read, patch, approval, and verify — through `dietcode-kernel` and runnable harnesses, not through a product UI.

---

## What you get

This repository does not ship an application. It ships a **reproducible claim**:

> On a local Mac, a headless kernel can enforce task-scoped coherence tokens, block stale mutations, sequence approvals, and require verification before completion — and you can prove it with one command.

```bash
make validate
```

Tag when green: **coherence-core-v0.1**.

| Deliverable | Path |
|-------------|------|
| Mutation kernel | `build/dietcode-kernel` |
| Coherence enforcement | `MacControlCoherenceTokens.mm` + live tests |
| Recovery proof | `scripts/coherence_recovery_smoke.py` |
| Integration surface | `scripts/dietcode_agent_client.py` |
| Contract lock | `make test-docs-code-drift` |

---

## Why an archive, not a product

DietCode began as a governed-mutation experiment with multiple surfaces — AppKit editor, React cockpit, TypeScript agent-bridge, Hermes integrations. Those surfaces helped prove that operators could **see** checkpoint state during realistic workflows.

The experiment succeeded at its core claim: **operational coherence works** when one authority enforces tokens, drift layering, approvals, and verify gates. The product shells did not need to remain in-tree to preserve that proof.

The archive strategy keeps what is **executable and falsifiable**:

- Kernel + control plane
- Coherence v0.1 implementation
- Python harnesses and fixtures
- Documentation locked to code

Everything else is documented as removed or frozen research. See [archive-note.md](archive-note.md).

---

## The problem

When agents edit code, operators usually cannot tell:

- whether reads were current or stale;
- whether the repo changed mid-task;
- whether the approved patch is what landed;
- whether tests ran;
- whether “done” means **verified** or merely **stopped**.

DietCode answers these as **checkpoints** on a single mutation authority — inspectable via RPC and harness NDJSON, not inferred from chat tone.

---

## The core mechanism: operational coherence

**Coherence** is the v0.1 primitive beneath drift. Drift asks: *did something change?* Coherence asks: *is this task still mutating from what it actually read?*

| Layer | Question | Typical block |
|-------|----------|---------------|
| Coherence | Is task context still valid? | `coherence_mismatch` |
| Drift | Did the workspace change broadly? | `workspaceDriftRequired` |
| Approval | Is this mutation cleared? | `approvalRequired` |
| Verify | Did the result pass? | `verify.failed` |

Task-scoped reads (`file.read`, `file.readBatch`, … with `taskId`) issue tokens. Mutations must carry `coherenceTokenId` + `expectedWorkspaceRevision`.

Detail: [coherence-tokens.md](coherence-tokens.md)

---

## The six checkpoints

| # | Question |
|---|----------|
| 1 | Did the agent read valid state? |
| 2 | Did the workspace change underneath it? |
| 3 | Is this mutation allowed? |
| 4 | Did the patch apply cleanly? |
| 5 | Did the result pass? |
| 6 | Can this task be called done? |

**Rule:** Agent exit ≠ done. Completion requires verify pass or explicit waive.

```text
agent or script → dietcode_agent_client.py → dietcode-kernel → your project
```

---

## What it is not

| Not this | Because |
|----------|---------|
| IDE / web UI | UI surfaces removed; kernel is the artifact |
| Chat product | No in-tree conversational layer |
| Cloud platform | Local socket + local verify commands |
| Benchmark suite | `benchmarks/` is frozen research, not the gate |
| “Done” on model stop | Completion is a kernel/harness state |

---

## Who it is for

| Reader | Value |
|--------|-------|
| **Researcher** | Runnable governed-mutation model with frozen baseline |
| **Agent author** | Kernel RPC + `dietcode_coherence.py` recovery patterns |
| **Maintainer** | `make validate` + tag **coherence-core-v0.1** |
| **Skeptic** | Falsifiable tests — claims fail loudly, not quietly |

---

## Proof hierarchy

| Command | Scope |
|---------|-------|
| `make validate` | **Primary** — coherence baseline + docs drift (CI) |
| `make coherence-core-v0.1` | Coherence tokens + recovery smoke only |
| `make verify-agent-runtime-full` | Optional broader RPC ladder |
| `benchmarks/agent_success/` | Frozen adversarial research — not gated |

---

## Daily use

```bash
make kernel && make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

After changes to kernel C++ or contracts:

```bash
make validate
```

---

## How failure looks (by design)

| Situation | You see |
|-----------|---------|
| Stale agent context | `coherence_mismatch` — re-read with `taskId` |
| Files changed mid-task | Drift gate blocks patch |
| Approval pending | `approvalRequired` until resolved |
| Tests fail | Verify gate blocks completion |

Legible failure is a feature, not a bug. See [philosophy.md](philosophy.md).

---

## Read next

| Time | Document |
|------|----------|
| **5 min** | You are here |
| **10 min** | [getting-started.md](getting-started.md) |
| **15 min** | [coherence-tokens.md](coherence-tokens.md) · [checkpoint-model.md](checkpoint-model.md) |
| **20 min** | [philosophy.md](philosophy.md) |
| **45 min** | [whitepaper.md](whitepaper.md) |

---

## Summary

> Agents will edit code. You still own the consequences. This archive preserves the kernel and harnesses that sequence those edits through one authority, coherence tokens, six checkpoints, and honest completion. It does not ask you to trust a demo — it asks you to run `make validate`.
