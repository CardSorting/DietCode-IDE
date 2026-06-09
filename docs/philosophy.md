# The philosophy of governed mutation

**Why DietCode treats AI code editing as an operations problem — and why the retained artifact is an archive, not a product.**

Version 1.1 · June 2026  
Companion: [brief.md](brief.md) · Technical whitepaper: [whitepaper.md](whitepaper.md) · Archive index: [ARCHIVE.md](../ARCHIVE.md)

---

## 1. The central claim

Software mutation by autonomous agents is already happening. The missing layer is not more intelligence. The missing layer is **governance**: visible authority, sequenced clearance, and honest completion semantics.

DietCode exists to answer one question repeatedly and in public:

> *Under what conditions is it safe to let an agent change this workspace — and how does everyone in the loop know those conditions were met?*

That question is operational. It is not answered by a better prompt, a larger model, or a prettier chat interface.

The repository's current form — a **kernel/coherence-core archive** — is itself a philosophical statement: the valuable output is not a feature roadmap. It is a **falsifiable control loop** you can run on your machine and tag when green.

---

## 2. Air-traffic control, not autopilot

The most accurate metaphor for DietCode is **air-traffic control for AI edits**.

| ATC concept | DietCode equivalent |
|-------------|---------------------|
| Multiple actors | Human operator, agent, CI, external tools |
| Control tower | `dietcode-kernel` + control plane |
| Clearance before movement | Coherence, drift, approval, verify gates |
| Centralized authority | Single mutation authority over the workspace |
| Visibility | Kernel RPC, harness NDJSON, `string_code` errors |
| “Landed” | `completed` requires verify pass or explicit waive |
| Incidents reported | Disconnects, expiry, blocks surface immediately |

DietCode is deliberately **not** the plane. It is not the airport terminal. It is the tower that sequences dangerous operations so that movement is **governed**, not merely **possible**.

Most agent products optimize for takeoff: fast generation, fluent explanation, impressive demos. DietCode optimizes for **clearance and landing** — the parts that determine whether anyone actually wants the flight to happen.

The archive keeps the tower. It removes the terminal gift shop.

---

## 3. Archive as operational honesty

A common failure mode in research-to-product transitions is **zombie productization**: dead UI surfaces, stale Makefile targets, and docs that describe software you can no longer build.

DietCode refuses that posture.

| Honest choice | Why |
|---------------|-----|
| Remove cockpit, bridge, editor scaffold | They proved visibility; they are not the kernel claim |
| Freeze `coherence-core-v0.1` | One baseline tag, one validate command |
| Keep benchmarks as research artifacts | Stress results inform design; they do not gate the archive |
| Lock docs to code | `make test-docs-code-drift` prevents narrative drift |

An archive is not a retreat. It is a **commitment to reproducibility**. If the coherence model is real, it should survive without a React dashboard.

Philosophically:

> **A claim you cannot rebuild is indistinguishable from marketing.**

`make validate` is the anti-marketing move.

---

## 4. Bounded autonomy, not full autonomy

The industry default treats “agent finished” as synonymous with “job done.” DietCode rejects that equivalence.

**Bounded autonomy** means:

- The agent may propose reads and patches within a declared task.
- The control plane may block, pause, or require human resolution at defined gates.
- Completion is a **system state**, not an LLM exit code.

This is realism about **shared state**. A codebase is a concurrent system. The agent is never the only writer. Git pulls, formatters, tests, and human edits all interleave.

> **Autonomy without observability is negligence. Observability without authority is theater.**

DietCode provides both: the operator can see which gate blocked progress, and the kernel enforces that block until the condition is resolved.

---

## 5. Coherence before drift (the v0.1 insight)

Many systems treat “something changed” as one undifferentiated failure. DietCode separates:

| Layer | Question | Precision |
|-------|----------|-----------|
| **Coherence** | Is *this task's observed context* still valid? | File-level anchors, revision counters |
| **Drift** | Did the *workspace* change underneath the agent? | Git dirty state, external edits, refresh anchors |

Coherence mismatch is **surgical** — it names `changedPaths` and tells the agent to re-read. Drift is **broad** — it forces workspace re-anchoring.

This layering is the core methodological contribution preserved in v0.1. The archive exists to keep that distinction executable, not merely documented.

---

## 6. Failure is signal, not embarrassment

Many products smooth failure — retry silently, collapse errors into chat, or imply progress when the control loop has stalled. DietCode takes the opposite stance:

**Operational failure should be legible.**

When the loop breaks, the operator should see:

- a disconnect, not a hung spinner;
- an expired approval, not an assumed yes;
- `coherence_mismatch`, not a mysterious patch rejection;
- a verify failure, not a premature “completed” badge.

> **The system must never imply an agent is operating safely when it is not.**

Hiding failure feels helpful in a demo. It is destructive when agents touch production code.

---

## 7. Separation as a moral architecture

DietCode separates concerns that other systems merge:

```text
workspace authority   — who may change files (kernel only)
orchestration         — how a task progresses (harness + RPC)
human oversight       — when a human must decide (approval gate)
verification          — whether the result is valid (verify gate)
observability         — what happened (events, errors — not gates)
```

Collapsing authority and conversation into one opaque stack creates a category error. The user believes they are conversing. The system is mutating shared infrastructure.

**Only the kernel mutates the workspace.** Agents, harnesses, and scripts request clearance via RPC.

Agents may request mutation. They do not perform it. The tower clears; the plane does not clear itself.

---

## 8. Checkpoints are questions, not features

A checkpoint is not a button or a panel. It is a **question the control plane must answer** before proceeding or before calling a task done.

1. Did the agent read valid state?
2. Did the workspace change underneath it?
3. Is this mutation allowed?
4. Did the patch apply cleanly?
5. Did the result pass?
6. Can this task be called done?

If a proposed feature does not answer one of these questions, it does not earn a new gate. It belongs in observability, recovery, or transport hygiene — the **noise bucket**.

This discipline is how the archive stayed small. UI panels were useful experiments. They were not new questions.

---

## 9. Local-first is a trust boundary

DietCode runs on your Mac. The workspace is on disk beside you. The kernel socket is local.

| Property | Implication |
|----------|-------------|
| Local process | You can inspect, restart, and diff the kernel |
| Local verify | `make test`, `./verify.sh`, `npm test` — your commands decide |
| Local approvals | No vendor policy engine in another region |

Cloud-assisted models may connect as optional agents. The **control loop** does not depend on them. External runtimes are RPC clients — not the product identity.

---

## 10. What DietCode refuses

| Refusal | Reason |
|---------|--------|
| Pretend chat is low-risk | Chat is an entry point to mutation |
| Conflate patch success with task success | Applying a diff ≠ solving the problem |
| Auto-approve on timeout | Silence is not consent |
| Auto-resume into drift or verify failure | Recovery requires intent |
| Add gates without questions | Checkpoints stay six |
| Maintain zombie product surfaces | Archive honesty over demo continuity |
| Position as an IDE replacement | The artifact is methodology + proof |
| Gate the archive on bridge-dependent benchmarks | Research ≠ baseline |

These refusals trade demo magic for **operational honesty**.

---

## 11. Who this philosophy serves

| Reader | Need |
|--------|------|
| Individual developer | Supervise agent edits without babysitting every line |
| Team lead | Know that “done” means verified, not merely attempted |
| Agent author | Stable kernel RPC + coherence recovery instead of raw file hacks |
| Maintainer | Frozen baseline (`coherence-core-v0.1`) provable via `make validate` |
| Researcher | Separable claims: coherence enforcement vs adversarial stress |

DietCode does not promise agents will always succeed. It promises that **success and failure will be visible at the right gate**.

---

## 12. Relation to evidence

Philosophy without evidence is marketing. DietCode binds claims to runnable proof:

```bash
make validate
```

| Step | What it falsifies if it fails |
|------|-------------------------------|
| `test-coherence-tokens-fast` | Token issuance or enforcement is broken |
| `coherence-recovery-smoke-fast` | Stale-context recovery path is broken |
| `test-docs-code-drift` | Documentation no longer matches contracts |

Tag when green: **coherence-core-v0.1**.

Parallel research under `benchmarks/agent_success/` evaluates runtime contracts under adversarial fixtures. It informs design; it is **not** the archive gate. See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md).

---

## 13. Summary

> AI agents will edit code. Humans and teams still own the consequences. DietCode is a local control tower — preserved as an archive — that sequences reads, approvals, patches, and verification through six visible checkpoints, with a single mutation authority, coherence tokens before drift, legible failure, and completion semantics that do not confuse “the model stopped” with “the job succeeded.” Bounded autonomy is the goal. Air-traffic control is the model. Operational honesty — including the refusal to pretend this is still a shipping app — is the obligation.

---

## Further reading

| Doc | Role |
|-----|------|
| [brief.md](brief.md) | Five-minute executive companion |
| [whitepaper.md](whitepaper.md) | Full technical specification |
| [checkpoint-model.md](checkpoint-model.md) | Six-gate specification |
| [coherence-tokens.md](coherence-tokens.md) | v0.1 coherence primitive |
| [archive-note.md](archive-note.md) | What was removed and why |
| [README.md](../README.md) | Project entry point |
