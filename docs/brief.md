# DietCode in Brief

**A five-minute companion to the philosophy and whitepaper.**

[Philosophy →](philosophy.md) · [Whitepaper →](whitepaper.md) · [README →](../README.md)

---

## One sentence

**DietCode is air-traffic control for AI edits** — a local runtime on macOS that clears each workspace change through six visible checkpoints before a task can be called done.

---

## The problem

When agents edit your code, you usually cannot tell:

- whether the agent read current files or stale ones;
- whether someone else changed the repo mid-task;
- whether you approved the exact patch that landed;
- whether tests passed — or ran at all;
- whether “finished” means **verified** or merely **stopped talking**.

Most tools hide these in chat. DietCode surfaces them as **checkpoints**.

---

## The answer

| Idea | What it means |
|------|---------------|
| **One mutation authority** | Only `dietcode-kernel` writes files. UI and agents request clearance. |
| **Six checkpoints** | Context → Drift → Approval → Mutation → Verify → Completion |
| **Bounded tasks** | You submit a governed task, not an open-ended conversation |
| **Legible failure** | Disconnect, drift block, and verify failure are visible — not smoothed away |
| **Local-first** | Runs on your Mac; your tests decide if the edit worked |

```text
You or agent → Cockpit → Bridge → kernel → your project
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

- Not a web IDE or cloud workspace
- Not a chat window that silently edits files
- Not “done” when the model stops

The optional native editor in `legacy_ui/` is legacy. The product is the **control loop**.

---

## Who it is for

| You | DietCode helps you |
|-----|-------------------|
| **Developer** | Supervise agent edits with approve / reject / verify |
| **Team lead** | Know “completed” means verified |
| **Agent author** | Integrate via bridge workflows, not raw file hacks |
| **Operator** | Recover cleanly after bridge restart or drift |

---

## Proof it works

```bash
make checkpoint-core
```

Frozen baseline **checkpoint-core-v0.1**: kernel + bridge + cockpit + 53-check vertical slice (npm, Make, `verify.sh` fixtures).

Daily dev:

```bash
make kernel && make restart-agent-server-fast
cd cockpit && npm install && npm run dev
```

Cockpit: http://localhost:5173 · Bridge API: http://127.0.0.1:9477

---

## How failure looks (by design)

| Situation | You see |
|-----------|---------|
| Connection lost | Disconnect — not a silent hang |
| Approval expired | Explicit expiry — not assumed yes |
| Files changed mid-task | Drift gate blocks patch |
| Tests fail | Verify gate blocks completion |

DietCode never implies an agent is safe when it is not.

---

## Optional extras

- **Hermes / legacy app chat** — [integrations/README.md](../integrations/README.md)
- **Adversarial benchmarks** — [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) (research track, separate from `checkpoint-core`)

---

## Read next

| Time | Document |
|------|----------|
| **5 min** | You are here |
| **20 min** | [philosophy.md](philosophy.md) — why governed mutation |
| **45 min** | [whitepaper.md](whitepaper.md) — architecture and contracts |
| **Reference** | [checkpoint-model.md](checkpoint-model.md) — gate specification |
| **Hands-on** | [getting-started.md](getting-started.md) — build and run |

---

## Summary

> Agents will edit code. You still own the consequences. DietCode sequences those edits through a local control tower — one authority, six checkpoints, visible clearance, honest completion. Bounded autonomy, not blind trust.
