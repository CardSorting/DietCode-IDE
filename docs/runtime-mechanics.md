# Runtime Mechanics: Chips, Combos, and Safety

DietCode features a unique, deterministic runtime designed to make the IDE a reliable environment for both humans and autonomous agents.

## 🏗️ The "Chip & Combo" Architecture

At the heart of DietCode's automation layer is the **Chip & Combo** system.

### Atomic Chips
A **Chip** is the smallest unit of executable logic in the DietCode control surface (e.g., `file.write`, `patch.apply`). Every Chip is metadata-enriched with:
- **Idempotency:** Whether the operation can be safely retried.
- **Side-Effects:** Detailed tracking of what the chip modifies (Buffers, Filesystem, Processes).
- **Permissions:** Granular access control (Read, Edit, Execute, Destructive).

### Orchestrated Combos
A **Combo** is a stateful sequence of Chips. It is treated as a **transaction**. If any step in a Combo fails, the system can trigger an automatic rollback.

---

## 🛡️ Transactional Safety & Recovery

DietCode uses a **Pre-image Backup Strategy** to ensure the workspace can always be restored to a known good state.

### 1. Checkpointing
Before a mutation-heavy Combo begins, the `MacControlRecoveryStore` creates a **Checkpoint**:
- **Manifest:** A JSON file recording the state (hashes) of all files declared in the Combo's scope.
- **Backups:** Literal copies of the files are stored in `~/.dietcode/backups/`.

### 2. Mutation Locking
To prevent race conditions, DietCode implements a two-tier locking system:
- **Path Locks:** Individual files are locked for the duration of a Combo.
- **Global Mutation Lock:** Only one mutation-active Combo can run at a time, ensuring that agents don't step on each other's toes.

### 3. Automatic Rollback
If a Combo is cancelled or fails a budget check (e.g., too many verify failures, timeout), the runtime automatically restores the workspace using the Pre-image backups. This makes "trial and error" coding by agents significantly safer.

---

## 📊 Budget & Resource Management

Agents are constrained by a **Combo Budget** to prevent infinite loops or runaway resource consumption:
- `maxSteps`: Maximum number of Chips in a single Combo.
- `maxDurationMs`: Hard time limit for execution.
- `maxFilesTouched`: Prevents "shotgun" refactorings that affect too many files at once.
- `maxVerifyRuns`: Limits the number of times an agent can trigger expensive build/test cycles.

---

## 🔗 The Window Bridge

The `MacControlWindowBridge` acts as the glue between the background Control Thread and the main UI thread. It ensures that:
- Agent edits are reflected in the open editor tabs immediately.
- The UI remains responsive while the agent performs heavy analysis or search tasks.
- Document events (Focus, Save, Edit) are published back to the agent via the event subscription bus.
