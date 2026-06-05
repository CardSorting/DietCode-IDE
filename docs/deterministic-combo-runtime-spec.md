# DietCode v1.6 Deterministic Local Transaction Kernel
## Architecture & Hardened Runtime Specification

This specification defines the DietCode v1.6 Local Transaction Kernel, evolving it from a sequential combo runner into a production-grade, deterministic, fail-closed operations substrate for coding agents.

---

### Core Philosophy
* **Mechanically Constrained:** DietCode does not infer intent, decide repair strategies, or make reasoning assumptions. It validates, constrains, executes, logs, and rolls back only when mechanically safe.
* **Hermetic and Isolated:** No background watchers, no cloud telemetry, no embedded vectors, and no self-modification.
* **Explicit Execution Contracts:** All state transitions, budget bounds, path checks, and lock acquisitions must be explicitly validated and fail-closed if invalid.

---

## Subsystem Specifications (1 - 50)

### 1. Runtime Boundary
* **Vulnerability:** Request/response line fragmentation on Unix sockets allows trailing bytes from oversized payloads to pollute subsequent operations.
* **Specification:** The IPC channel is a local UNIX domain socket at `~/.dietcode/control.sock`. The socket server reads messages using a strict line-based protocol terminated by `\n`. If any incoming stream segment exceeds `kMaxRequestBytes` (1MB) or fails JSON parsing, the server purges the channel buffer, sends a structured `invalid_request` error, and forcibly closes the client socket.

### 2. Core Runtime Model
* **Vulnerability:** Sync execution of terminal runners or file operations on the AppKit main UI thread blocks the editor interface.
* **Specification:** The runtime logic runs on a dedicated background serial queue `com.dietcode.runtime.kernel`. Main thread synchronization is limited to editor document buffer text retrievals and replacements, isolating the UI from long-running command execution.

### 3. Static Chip Registry
* **Vulnerability:** Weakly checked dynamic arrays of dictionaries defining supported commands.
* **Specification:** The register of supported execution units ("chips") is a static, compile-time table of C++ structures. The registry defines parameter types, permission level, and rollback support. No dynamic additions are permitted.

### 4. Chip Metadata Schema
* **Vulnerability:** Typo-prone dynamic lookup maps.
* **Specification:** Every chip registered must adhere to a strict compiled structure:
  ```cpp
  struct ChipDefinition {
      std::string name;
      int version;
      std::string category;
      PermissionLevel permission;
      bool deterministic;
      IdempotencyClass idempotency;
      SideEffects side_effects;
      std::vector<std::string> required_params;
  };
  ```

### 5. Chip Versioning and Compatibility
* **Vulnerability:** Mismatched versions executed without validation.
* **Specification:** Steps in a combo payload must declare an exact chip version (e.g., `file.readRange@1`). Mismatches between the step declaration and the compiled registry will trigger immediate validation rejection (`unknown_chip` / `version_mismatch`).

### 6. Contract Semantics
* **Vulnerability:** Undefined parameter structures causing downstream runtime assertion crashes.
* **Specification:** Before executing any chip, parameter keys and types are validated against the registry schema. Type coercion is disabled: integer variables must be numeric JSON types, arrays must be strictly validated for length, and strings must be non-null.

### 7. Preconditions and Postconditions
* **Vulnerability:** Applying changes to files that were edited externally after combo validation.
* **Specification:** Steps executing writes must declare pre-conditions (preimage hash) and post-conditions (postimage hash). Before mutation, the file is read, and its SHA-256 hash verified. If it mismatches, the step fails immediately.

### 8. Side-Effect Declarations
* **Vulnerability:** Declared side-effects (e.g., `runsProcess`) are never actively monitored.
* **Specification:** The kernel enforces declared constraints during validation. If a plan contains a step whose registry metadata declares `runsProcess: false` but its payload attempts execution, the validation pipeline aborts.

### 9. Idempotency Classes
* **Vulnerability:** Multiple read-only steps targeting the same file execute repetitive disk I/O.
* **Specification:** The kernel implements a transient transaction cache for chips marked `conditionally_idempotent`. If no mutation occurred in the current transaction, consecutive read-only steps fetch from the cache.

### 10. Output Reference and Wiring Model
* **Vulnerability:** Hardcoded sequential flow without variable interpolation.
* **Specification:** Supported dynamic parameters resolve references to previous outputs using strict bracket notation (e.g., `{{steps.step1.result.text}}`). The references are validated statically to prevent circular dependency loops.

### 11. Combo Schema
* **Vulnerability:** Unrecognized JSON parameters allowed, opening pathways for injection.
* **Specification:** The incoming plan is validated against a strict schema. Unrecognized top-level or step-level keys trigger immediate plan invalidation.

### 12. Combo Validation Pipeline
* **Vulnerability:** Partial validation checks leading to halfway execution.
* **Specification:** A five-stage validation pipeline runs atomically before execution:
  `Structure Checks` -> `Security & Token Checks` -> `Path Normalization & Scope` -> `Dependency Graph Sorting` -> `Dry-run Preimage Check`.

### 13. Immutable Execution Plan Generation
* **Vulnerability:** Step details updated during execution modify the input plan.
* **Specification:** Once validated, the plan is copied into a read-only C++ structure. The executor reads exclusively from this immutable structure.

### 14. Step Dependency Legality
* **Vulnerability:** Cyclic needs lists cause infinite loops or invalid execution orders.
* **Specification:** The dependency graph is topological-sorted. If sorting fails due to cycles, validation throws `cyclic_dependency`.

### 15. Sequential vs Parallel Execution Policy
* **Vulnerability:** Concurrent combos corrupting mutual paths.
* **Specification:** The kernel maintains a global sequential lock. Only one combo containing mutation actions is allowed to execute at a time. All other write combos are queued or rejected.

### 16. Execution State Machine
* **Vulnerability:** State tracked using simple string updates.
* **Specification:** The combo lifecycle operates under a strict finite state machine:
  `Validated` -> `Locked` -> `Executing` -> `RollingBack` -> `Terminated`. Direct state changes are enforced through a unified transition manager.

### 17. Step Lifecycle Phases
* **Vulnerability:** Phase transitions are implicit and not verified.
* **Specification:** Steps execute strictly through three phases: `Preflight` (verify lock, preimage, and scope) -> `Action` (execute code) -> `Postflight` (verify postimage and write backup).

### 18. Append-Only Trace Model
* **Vulnerability:** Memory trace records are lost during runtime crashes.
* **Specification:** Every state change and step result is written immediately to a persistent append-only log file at `~/.dietcode/transactions/history.log`.

### 19. Path Normalization
* **Vulnerability:** Traversal segments (`/../`) and relative paths bypass simple prefix checks.
* **Specification:** All path inputs are immediately normalized to their absolute canonical path representation using `std::filesystem::canonical`. If a target file does not exist, its parent directory is resolved and canonicalized.

### 20. Symlink Escape Prevention
* **Vulnerability:** Symlinks inside the workspace pointing to outside directories allow reading/writing sensitive system files.
* **Specification:** The canonical resolver resolves all symlinks. If the resolved path points outside the workspace, it is blocked. Creation of symlink files is disallowed.

### 21. Scope Enforcement
- **Vulnerability:** Weak, bypassable prefix tests.
- **Specification:** Scope limits (include/exclude globs) are evaluated against canonicalized absolute paths relative to the workspace root. Excludes override includes.

### 22. Budget Accounting
* **Vulnerability:** Mutable counters easily bypassed or overwritten.
* **Specification:** Execution budgets (limits on step counts, patches, and verification tasks) are loaded as read-only constants. Step consumption increments atomic execution counters. Reaching any limit triggers transaction abort.

### 23. Permission Model
* **Vulnerability:** No authentication for socket connections.
* **Specification:** A session-specific token is written to `~/.dietcode/session.token` (read-only by user, `0600`). Every incoming socket request must present this token, or it is immediately dropped.

### 24. Confirmation Flow Integrity
* **Vulnerability:** Blocked main thread causes socket read timeouts.
* **Specification:** Destructive actions requiring user confirmation are run with an asynchronous timer. If user consent is not granted within 60 seconds, the kernel defaults to "Deny", aborts the transaction, and rolls back.

### 25. Dirty Buffer/Editor Synchronization
* **Vulnerability:** Direct file modification on disk corrupts active editor windows with unsaved changes.
* **Specification:** The kernel maintains a registry of open tabs. If a path has a dirty editor buffer, disk mutations are rejected. The change must be applied directly to the in-memory document.

### 26. Disk vs Buffer Mutation Semantics
* **Vulnerability:** Ambiguity on whether a step modifies the disk or the buffer.
* **Specification:** Step schemas must define an execution domain: `disk` or `buffer`. If domain is `buffer` and the file is not open, the step fails. If domain is `disk` and the file is open and dirty, the step fails.

### 27. Patch Validation and Apply Semantics
* **Vulnerability:** Validation and application are decoupled, allowing race conditions.
* **Specification:** The apply step recalculates the diff validation immediately prior to executing the write. If the target file modification timestamp changes during the execution phase, it aborts.

### 28. Checkpoint Model
* **Vulnerability:** Volatile checkpoints overwritten during batch processes.
* **Specification:** Before any mutation, a backup copy of the target file is written to `~/.dietcode/backups/<combo-id>/`. This backup directory is tracked inside the transaction context.

### 29. Rollback Legality and Conflicts
* **Vulnerability:** Reverting modified files blindly overwrites external edits.
* **Specification:** A rollback fails closed if the file's current state on disk does not match the post-mutation state from the execution trace. Manual user resolution is required.

### 30. Cross-Combo Locking
* **Vulnerability:** Releasing locks between steps allows concurrent edits to pollute transactions.
* **Specification:** All paths to be modified are locked upon transaction entry. Locks are held globally and released only when the entire combo achieves a terminal state.

### 31. External Edit Detection
* **Vulnerability:** Git status modification checks are slow and run asynchronously.
* **Specification:** Record file modification timestamps (`mtime`) and file size on lock acquisition. If subsequent steps detect a change in `mtime` without kernel intervention, it aborts.

### 32. Verify Command Execution
* **Vulnerability:** Exit status validation is parsed from terminal stdout, allowing agents to spoof success by printing false logs.
* **Specification:** Verification commands are run using a dedicated `NSTask` pipeline. The process exit code is captured directly from the OS process table. Terminal output parsing for exit code resolution is disallowed.

### 33. Verify Side Effects
* **Vulnerability:** Compilation side-effects (e.g. build outputs) can overwrite locked source code.
* **Specification:** Verify commands must run with high-priority read-only source mappings. Write commands from build scripts are restricted to build directories.

### 34. Terminal Process Tracking
* **Vulnerability:** Spawning shells leaves orphaned processes running upon abort.
* **Specification:** The kernel tracks task Process Group IDs (PGID). On transaction abort, a `SIGKILL` is dispatched to the entire process group.

### 35. Cancellation Semantics
* **Vulnerability:** Cancellation commands are ignored during active subprocess execution.
* **Specification:** Sending `combo.cancel` flags the active transaction and dispatches immediate termination signals to the running verify tasks, triggering rollback.

### 36. Timeout Semantics
* **Vulnerability:** Slow build execution runs indefinitely.
* **Specification:** A hard timeout limit of 180 seconds is enforced for verification commands. If reached, the subprocess is killed and the transaction aborts.

### 37. Result Paging and Streaming
* **Vulnerability:** Giant files read via `file.read` overwhelm socket memory.
* **Specification:** Socket outputs are capped at `kMaxResponseBytes` (4MB). File reads exceeding `kMaxFileTextBytes` (1MB) must be requested via `file.readRange`.

### 38. Result Handle Lifecycle
* **Vulnerability:** Storing task statuses indefinitely results in memory leaks.
* **Specification:** Completed transaction payloads and logs are pruned from memory after 1 hour of inactivity.

### 39. Repair Chip Boundaries
* **Vulnerability:** Repair steps retrieve context files without validation checks.
* **Specification:** Paths requested in repair parameters are verified against the standard workspace prefix and scope checks.

### 40. Failure Propagation
* **Vulnerability:** Arbitrary string logs returned on failure.
* **Specification:** Errors are formatted as standard JSON-RPC 2.0 error blocks with numeric error codes.

### 41. Stable Error Taxonomy
* **Vulnerability:** Inconsistent error naming complicates automated recovery.
* **Specification:** Static error catalog:
  - `-32601`: `method_not_found`
  - `4001`: `outside_workspace`
  - `4002`: `lock_conflict`
  - `4003`: `budget_exceeded`
  - `4004`: `verification_failed`
  - `4005`: `rollback_conflict`

### 42. Crash Recovery Honesty
* **Vulnerability:** Startup state is corrupt after unhandled IDE crashes.
* **Specification:** A transactional journal file `~/.dietcode/transactions/pending.journal` logs active combos. On start, the server checks this journal. If a pending combo exists, rollback is automatically triggered from the backup folder.

### 43. Memory Pressure Behavior
* **Vulnerability:** Parsing large payloads blocks key threads.
* **Specification:** The Unix socket parser rejects any raw message frame larger than 2MB immediately.

### 44. Resource Exhaustion Limits
* **Vulnerability:** High request counts exhaust open file descriptors.
* **Specification:** The UNIX socket server accepts a maximum of 2 active client connections at any time.

### 45. Large Repository Behavior
* **Vulnerability:** Workspace lists hang on massive projects.
* **Specification:** Directory scanners are limited to a maximum depth of 10. Folders matching the default exclusions list (`.git`, `node_modules`, `build`, `dist`) are skipped immediately before checking contents.

### 46. Replay and Reproducibility
* **Vulnerability:** Steps lack the state records needed for replication.
* **Specification:** Trace logs include inputs, pre-images, post-images, and exit codes, allowing step-by-step transaction replay.

### 47. RPC Schema Evolution
* **Vulnerability:** Mismatched client/server versions cause parser failures.
* **Specification:** All requests must declare a version header: `schemaVersion: 1.6`. Mismatches are rejected.

### 48. Abuse Resistance
* **Vulnerability:** High-speed loops exhaust system cycles.
* **Specification:** Rate limiting restricts agents to a maximum of 10 requests per second.

### 49. Security Boundaries
* **Vulnerability:** Improper workspace paths point to sensitive system directories.
* **Specification:** Workspace roots must reside inside safe home directory structures. Roots in system folders (e.g. `/`, `/var`, `/etc`) are rejected.

### 50. Explicit Anti-Goals
* **Specification:**
  - No background directory indexing.
  - No network lookups.
  - No autonomous planner loops.
  - No self-repair of code without external instruction.
