# DietCode in brief

**A five-minute companion to the kernel/coherence-core archive.**

[Philosophy →](philosophy.md) · [Whitepaper →](whitepaper.md) · [README →](../README.md)

---

## One sentence

**DietCode is a local kernel/coherence-core archive** that preserves operational coherence across agent read, diff, patch, approval, and verification — enforced by `dietcode-kernel`, not by chat UI.

---

## The problem

When agents edit code, operators usually cannot tell:

- whether reads were current or stale;
- whether the repo changed mid-task;
- whether the approved patch is what landed;
- whether tests ran;
- whether “done” means **verified** or merely **stopped**.

DietCode answers these as **checkpoints** on a single mutation authority.

---

## The archive strategy

| Retained | Removed |
|----------|---------|
| `dietcode-kernel` + control plane | Cockpit React UI |
| Coherence tokens + tests | Legacy AppKit editor |
| Python RPC harnesses | TypeScript agent-bridge |
| Docs + contract lock | Hermes integrations |

The repo proves a **frozen baseline** (`coherence-core-v0.1`), not a shipping app. See [archive-note.md](archive-note.md).

---

## The answer

| Idea | Meaning |
|------|---------|
| **One mutation authority** | Only the kernel writes files |
| **Coherence tokens** | Task-scoped reads bind context before drift/approval |
| **Six checkpoints** | Context → Drift → Approval → Mutation → Verify → Completion |
| **Legible failure** | `coherence_mismatch`, drift blocks, verify failures — surfaced |
| **Local-first** | macOS socket + your verify commands |

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

**Rule:** Agent exit ≠ done. Completion requires verify pass or explicit waive.

Detail: [checkpoint-model.md](checkpoint-model.md)

---

## What it is not

- Not an IDE or web UI
- Not a chat window that silently edits files
- Not “done” when the model stops
- Not gated by adversarial benchmarks (those are frozen research)

---

## Who it is for

| You | DietCode helps you |
|-----|-------------------|
| **Researcher** | Study governed mutation with runnable proof |
| **Agent author** | Integrate via kernel RPC + Python helpers |
| **Maintainer** | Freeze and tag **coherence-core-v0.1** |

---

## Proof it works

```bash
make validate
```

Or the baseline only:

```bash
make coherence-core-v0.1
```

Daily development:

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

> Agents will edit code. You still own the consequences. This archive sequences edits through a local kernel — one authority, coherence tokens, six checkpoints, honest completion. Run `make validate` to prove the baseline on your machine.
