# DietCode v1.6.2 Hardened Local Transaction Kernel
## Architecture & Hardened Durable Checkpoint Specification

This specification defines the DietCode v1.6.2 Local Transaction Kernel, establishing strict, crash-safe, durable checkpoint semantics for bounded agent code mutation, with strict manifest discipline.

---

### Core Philosophy
* **Verified Preimages:** Checkpoints are verified transaction preimages. They represent historical snapshots of modified files *before* a specific combo execution and are not general-purpose undo logs or workspace backplanes.
* **Deterministic Rollback legality:** Reverting changes is only legal when the kernel proves: "This exact combo changed these exact files from this exact preimage into this exact postimage, and nothing else has mutated them since."
* **Fail-Closed on Mismatch:** Any deviation in manifest validity, file hashes, path canonicalization, workspace containment, or open buffer states must block rollback immediately, failing closed with a stable, machine-readable error.
* **Manifest Discipline (v1.6.2):** Manifest parsing strictly rejects any unrecognized fields, enforces static type checks, limits maximum file size to 1MB, writes keys in alphabetical canonical order, and signs transactions with a companion checksum file.

---

## The Verified Backup Manifest Format

Every transaction creates a backup folder: `~/.dietcode/backups/<combo-id>/`. This folder contains backup blobs of preimages (`[backupBlobHash].blob`), a committed `manifest.json`, and a companion `manifest.checksum` file.

```json
{
  "chipVersions": [
    "patch.apply@1"
  ],
  "comboId": "combo-1234",
  "createdAt": "2026-06-05T12:00:00Z",
  "dietcodeVersion": "1.6.2",
  "files": [
    {
      "backupBlobHash": "df812ca43f0190ab",
      "canonicalPathHash": "a24f0c97de898bf1",
      "domain": "disk",
      "expectedPostimageHash": "fe8912c98ad23290",
      "newlineMode": "lf",
      "preimageHash": "df812ca43f0190ab",
      "sizeBytes": 2048,
      "wasBinary": false,
      "wasMissing": false,
      "workspaceRelativePath": "src/main.cpp"
    }
  ],
  "schemaVersion": "1.6.2",
  "sessionId": "unix_socket_session_token_hash",
  "workspaceRootCanonical": "/Users/user/Desktop/project",
  "workspaceRootHash": "1469598103934665603ULL"
}
```

---

## Subsystem Specifications (1 - 50)

### 1. Runtime Boundary
* **Boundary Rules:** The control Unix socket is bound to `~/.dietcode/control.sock`. Incoming message frames must be parsed line-by-line using a size limit of `kMaxRequestBytes` (1MB). If a frame boundary is breached, the read buffer is cleared and the socket connection is immediately closed to prevent request flooding.

### 2. Core Runtime Model
* **Model Rules:** The kernel runs long-running operations (such as grep, find, verification, and combo loop execution) on a private serial background thread queue `com.dietcode.runtime.execution`. AppKit UI objects are accessed synchronously on the Cocoa main thread via `dispatch_sync` only during buffer queries and replacements.

### 3. Static Chip Registry
* **Registry Rules:** Supported executable units ("chips") are registered in a compiled static structural array. Dynamic registration or dynamic code injection is prohibited.

### 4. Chip Metadata Schema
* **Schema Rules:** The static registry defines structural metadata for each chip, detailing input types, capabilities, permission tiers (`Read`, `Edit`, `Execute`, `Destructive`), determinism, and side-effects.

### 5. Chip Versioning and Compatibility
* **Versioning Rules:** Incoming step requests must specify an exact version string (e.g. `patch.apply@1`). If the requested version is not supported by the static registry, validation fails with `unknown_chip`.

### 6. Contract Semantics
* **Contract Rules:** Chip input parameter validation is strictly enforced. Schema checks verify keys and value types. No type-coercion is performed. Missing required inputs fail execution immediately.

### 7. Preconditions and Postconditions
* **Verification Rules:** Write steps must declare preconditions (expected target state preimage hash) and postconditions (expected output postimage hash). Steps fail if target preimages differ from actual file hashes.

### 8. Side-Effect Declarations
* **Enforcement Rules:** The kernel inspects steps for side-effect declarations. If a step declares no workspace side-effects (`writesWorkspace: false`), the kernel blocks any filesystem write operations initiated by that step.

### 9. Idempotency Classes
* **Idempotency Rules:** Chips are categorized as `non_idempotent` or `conditionally_idempotent`. Pure read queries are cached inside the transactional boundary session and reused if no mutations occur.

### 10. Output Reference and Wiring Model
* **Wiring Rules:** Step outputs are wired to subsequent steps using strict templating (e.g., `{{steps.s1.result.text}}`). Graph validation checks for circular references and missing parameters before execution starts.

### 11. Combo Schema
* **Schema Rules:** Plan validation checks the entire JSON payload. The presence of unrecognized top-level or step-level keys triggers an immediate `invalid_combo` failure.

### 12. Combo Validation Pipeline
* **Pipeline Phases:** validation operates as an atomic multi-phase checker:
  `Structure Checks` -> `Token Validation` -> `Path Canonicalization & Scope Check` -> `Dependency Cycle Check` -> `Preimage Verification`.

### 13. Immutable Execution Plan Generation
* **Immutability Rules:** Once validated, the combo plan is compiled into a read-only execution block. No step modification or injection is permitted at runtime.

### 14. Step Dependency Legality
* **Dependency Rules:** Dependency graphs must be cycle-free. Cycles or unresolvable needs arrays trigger plan validation failures.

### 15. Sequential vs Parallel Execution Policy
* **Execution Rules:** The kernel enforces single-transaction write locking. Only one mutation combo can run at a time. Read-only queries can run in parallel if targeting non-locked paths.

### 16. Execution State Machine
* **State Table:** State transitions are managed explicitly:
  `Idle` -> `Validated` -> `Locked` -> `Executing` -> `RollingBack` -> `Terminated`. Illegal transitions trigger transaction abort.

### 17. Step Lifecycle Phases
* **Step Phases:** Each step runs through: `Preflight` (scope/lock checks) -> `Execution` (action) -> `Postflight` (update expected postimage hashes, log trace).

### 18. Append-Only Trace Model
* **Trace Rules:** Execution traces are flushed directly to disk at `~/.dietcode/transactions/history.log` in an append-only format immediately after each step completes.

### 19. Path Normalization
* **Normalization Rules:** All path inputs are immediately normalized to their absolute canonical paths via `std::filesystem::canonical`. If a target does not exist, the parent path is canonicalized to prevent traversal escapes.

### 20. Symlink Escape Prevention
* **Symlink Rules:** No operation may create a symlink. If canonical path resolution points to a location outside the workspace root, the operation is blocked. If a target path is replaced by a symlink during execution, rollback is aborted.

### 21. Scope Enforcement
* **Scope Rules:** Folder-level and file-level inclusions/exclusions are evaluated using normalized canonical paths relative to the workspace. Excludes take absolute precedence over includes.

### 22. Budget Accounting
* **Budget Rules:** Step limits, patch sizes, verification runs, and files touched are checked against read-only constants. Exceeding any budget limit triggers immediate combo termination and rollback.

### 23. Permission Model
* **Permission Rules:** Every RPC request must pass the active session token. Destructive methods (like `git.discard` or `workspace.openFolder`) require user confirmation via UI prompt.

### 24. Confirmation Flow Integrity
* **Confirmation Rules:** UI confirmations run with an asynchronous timer. If the user does not respond within 60 seconds, the kernel defaults to "Deny" and aborts the transaction.

### 25. Dirty Buffer/Editor Synchronization
* **Synchronization Rules:** If a target path contains unsaved changes in the editor, disk mutations are rejected. The patch must be applied to the in-memory document first.

### 26. Disk vs Buffer Mutation Semantics
* **Domain Rules:** Steps must declare mutation domain: `disk` or `buffer`. If domain is `buffer` and the file is not open, the step fails. If domain is `disk` and the file is open and dirty, the step fails.

### 27. Patch Validation and Apply Semantics
* **Patch Rules:** The patch validator checks syntax and applies diff previews. Preimage hashes are validated immediately before write application.

### 28. Checkpoint Model
* **Checkpoint Rules:** Checkpoints represent verified transaction preimages stored on disk. Creation follows the atomic protocol:
  1. Write preimage content to `[backupBlobHash].blob`.
  2. Fsync the blob.
  3. Write `manifest.tmp`.
  4. Fsync `manifest.tmp`.
  5. Atomically rename `manifest.tmp` to `manifest.json`.

### 29. Rollback Legality and Conflicts
* **Rollback Preconditions:** Rollback is rejected (failing closed) if:
  - Manifest is missing or invalid.
  - Blob preimage hash does not match manifest.
  - Current file hash does not match `expectedPostimageHash`.
  - The target file was modified externally after the combo completed.
  - The target file became binary.

### 30. Cross-Combo Locking
* **Locking Rules:** All path locks are acquired at the start of `runComboWithPlan` and held globally. They are released only when the combo transitions to a terminal state (`complete` or `rolled_back`).

### 31. External Edit Detection
* **Detection Rules:** File modification times (`mtime`) and sizes are checked before any step execution. If they have changed since the combo started (without kernel intervention), the combo aborts.

### 32. Verify Command Execution
* **Verification Rules:** Verify commands are run using a dedicated `NSTask`. The process exit code is fetched directly from the OS process table. Terminal output parsing for exit status resolution is prohibited.

### 33. Verify Side Effects
* **Side-Effect Rules:** Verify commands are restricted to build directories. Writes to locked source code locations are blocked.

### 34. Terminal Process Tracking
* **Process Rules:** Spawning terminal tasks registers their Process Group ID (PGID). On cancel or abort, `SIGKILL` is sent to the PGID to clean up child processes.

### 35. Cancellation Semantics
- **Cancellation Rules:** Receiving `combo.cancel` halts execution and dispatches immediate SIGKILL to active verify tasks, initiating rollback.

### 36. Timeout Semantics
* **Timeout Rules:** A hard execution timeout of 180 seconds is enforced for verify commands. Reaching the limit kills the task and aborts the combo.

### 37. Result Paging and Streaming
* **Paging Rules:** RPC responses are capped at `kMaxResponseBytes` (4MB). File reads over `kMaxFileTextBytes` (1MB) must be paged via `file.readRange`.

### 38. Result Handle Lifecycle
* **Lifecycle Rules:** Completed transaction traces and backup registers are deleted from memory after 1 hour of inactivity.

### 39. Repair Chip Boundaries
* **Repair Rules:** Inputs to repair chips must be checked for workspace containment and glob scopes to prevent text leaks.

### 40. Failure Propagation
* **Propagation Rules:** Failed steps return standard JSON-RPC 2.0 error payloads.

### 41. Stable Error Taxonomy
* **Error Table:**
  - `backup_manifest_missing`: The checkpoint `manifest.json` is not found.
  - `backup_manifest_invalid`: The manifest has invalid JSON or version.
  - `backup_corrupt`: Backup blobs are missing or fail integrity checks.
  - `backup_scope_mismatch`: Path escapes canonical boundaries.
  - `backup_workspace_mismatch`: Checkpoint workspace does not match current workspace.
  - `rollback_postimage_mismatch`: Current target state does not match expected postimage.
  - `rollback_preimage_mismatch`: Preimage blob hash mismatch.
  - `rollback_target_escaped`: Path resolves outside workspace.
  - `rollback_buffer_conflict`: Unsaved edits exist in target editor buffer.
  - `rollback_partial_failure`: Failed to restore a subset of files.
  - `rollback_lock_unavailable`: Path is locked by another combo.
  - `checkpoint_write_failed`: Failed to write backup blob.
  - `checkpoint_incomplete`: manifest.json commit failed.
  - `checkpoint_disk_full`: Checkpoint failed due to disk space exhaustion.
  - `recovery_scan_only`: Restores are blocked on recovery scan.

### 42. Crash Recovery Honesty
* **Crash Policy:** Active transactions write a journal `~/.dietcode/transactions/pending.journal`. After a crash, the kernel does not auto-rollback. It only exposes `recovery.scan` to list orphans. Restores require manual confirmation and full validation checks.

### 43. Memory Pressure Behavior
* **Memory Rules:** Incoming message frames larger than 2MB are rejected by the socket layer immediately.

### 44. Resource Exhaustion Limits
* **Exhaustion Rules:** Maximum active socket connections: 2. Maximum concurrent subprocess tasks: 1.

### 45. Large Repository Behavior
* **Large Repo Rules:** Directory scanner searches are limited to depth 10. Excluded directories are skipped immediately.

### 46. Replay and Reproducibility
* **Replay Rules:** Step trace payloads preserve preimages, exact patches, and postimages for step-by-step transaction replay.

### 47. RPC Schema Evolution
* **RPC Rules:** Requests must declare `schemaVersion: 1.6.2`. Mismatches are rejected.

### 48. Abuse Resistance
* **Rate Limits:** Enforce token-bucket rate limiting of 10 requests per second (max 2 writes/second).

### 49. Security Boundaries
* **Workspace Safety:** Workspace folders are restricted to user home directory paths. System folders are blocked.

### 50. Explicit Anti-Goals
* **Anti-Goals:**
  - No autonomous planner loops.
  - No background project graph indexing.
  - No internet network requests.
  - No self-repair of compiler failures without explicit instructions.
