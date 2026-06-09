# DietCode in Brief

**A five-minute companion to the philosophy and whitepaper.**

[Philosophy →](philosophy.md) · [Whitepaper →](whitepaper.md) · [README →](../README.md)

---

## One sentence

**DietCode is a local kernel experiment** for preserving operational coherence across agent read, diff, patch, approval, and verification surfaces.

---

## The problem

When agents edit your code, you usually cannot tell:

- whether the agent read current files or stale ones;
- whether someone else changed the repo mid-task;
- whether you approved the exact patch that landed;
- whether tests passed — or ran at all;
- whether “finished” means **verified** or merely **stopped talking**.

DietCode surfaces these as **checkpoints** enforced by `dietcode-kernel`.

---

## The answer

| Idea | What it means |
|------|---------------|
| **One mutation authority** | Only `dietcode-kernel` writes files. Agents request clearance via RPC. |
| **Coherence tokens** | Task-scoped reads bind context to kernel revision before drift/approval |
| **Six checkpoints** | Context → Drift → Approval → Mutation → Verify → Completion |
| **Legible failure** | `coherence_mismatch`, drift block, verify failure — not smoothed away |
| **Local-first** | Runs on your Mac; your tests decide if the edit worked |

```text
agent or script → dietcode_agent_client.py → dietcode-kernel → your project
```

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

**Rule:** Agent exit ≠ done. Completion requires verify to pass or be explicitly waived.

---

## What it is not

- Not an IDE or web UI
- Not a chat window that silently edits files
- Not “done” when the model stops

Experimental cockpit, legacy AppKit UI, and agent-bridge surfaces were removed. See [archive-note.md](archive-note.md).

---

## Who it is for

| You | DietCode helps you |
|-----|-------------------|
| **Researcher** | Study governed mutation and coherence enforcement |
| **Agent author** | Integrate via kernel RPC, not raw file hacks |
| **Maintainer** | Freeze a reproducible coherence baseline |

---

## Proof it works

```bash
make coherence-core-v0.1
```

Frozen baseline **coherence-core-v0.1**: live coherence token tests + deterministic recovery smoke.

Daily dev:

```bash
make kernel && make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

---

## How failure looks (by design)

| Situation | You see |
|-----------|---------|
| Stale agent context | `coherence_mismatch` — re-read with `taskId` |
| Files changed mid-task | Drift gate blocks patch |
| Approval pending | `approvalRequired` until resolved |
| Tests fail | Verify gate blocks completion |

DietCode never implies an agent is safe when it is not.

---

## Optional extras

- **Adversarial benchmarks** — [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) (research track, separate from coherence-core)

---

## Read next

| Time | Document |
|------|----------|
| **5 min** | You are here |
| **20 min** | [philosophy.md](philosophy.md) — why governed mutation |
| **45 min** | [whitepaper.md](whitepaper.md) — architecture and contracts |
| **Reference** | [coherence-tokens.md](coherence-tokens.md) · [checkpoint-model.md](checkpoint-model.md) |
| **Hands-on** | [getting-started.md](getting-started.md) — build and run |

---

## Summary

> Agents will edit code. You still own the consequences. DietCode sequences those edits through a local kernel — one authority, coherence tokens, six checkpoints, honest completion. Bounded autonomy, not blind trust.
