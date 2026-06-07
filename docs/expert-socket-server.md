# Expert-Tier: Control Server Threading & Security

The `MacControlServer` (`src/platform/macos/control/MacControlServer.mm`) is the most complex component of the DietCode platform shell, managing high-concurrency RPC traffic while ensuring the integrity of the UI and filesystem.

## 🧵 The Dual-Queue Threading Model

To maintain a responsive UI and safe data access, the server employs two distinct GCD (Grand Central Dispatch) queues:

### 1. The Execution Queue (`_executionQueue`)
- **Type**: Serial
- **Usage**: All "mutation" methods (e.g., `file.write`, `patch.apply`, `git.commit`).
- **Rationale**: Ensures that only one write operation occurs at a time, preventing race conditions and simplifying the rollback logic.

### 2. The Read Queue (`_readQueue`)
- **Type**: Concurrent
- **Usage**: All "read-only" methods (e.g., `file.read`, `workspace.grep`, `symbols.document`).
- **Rationale**: Allows multiple agents or tools to scan the workspace simultaneously, maximizing throughput during heavy analysis tasks.

---

## 🔒 Security & Session Integrity

DietCode implements a "Local-First Security" model to protect your code and system.

### 1. Dynamic Session Tokens
On every launch, DietCode generates a unique 128-bit session token (`_sessionToken`) using `arc4random()`. This token is:
- Written to `~/.dietcode/session.token` with strict `0600` permissions.
- Required in the header of every JSON-RPC request.
- Invalidated immediately when the app quits.

### 2. Socket Hardening
The Unix socket at `~/.dietcode/control.sock` is created with `0600` permissions, ensuring that only the local user can connect. The server also checks for:
- **Symbolic Link Protection**: Aborts if `~/.dietcode` is a symlink (to prevent redirection attacks).
- **Ownership Verification**: Ensures the config directory is owned by the current UID.

### 3. Frame Integrity
The server enforces a `kMaxRequestBytes` (1MB) limit on every JSON frame to prevent memory exhaustion attacks from malicious or runaway agents.

---

## 🚦 Thread Synchronization: The Window Bridge

When an RPC method needs to interact with the UI (e.g., `editor.insertText`), the `MacControlWindowBridge` performs a `dispatch_sync` to the **Main Thread**.

- **Deadlock Prevention**: The bridge is carefully engineered to only sync for UI-bound operations. Core domain logic and filesystem reads stay on the background RPC queues.
- **Atomic Snapshots**: For search operations, the bridge can capture a snapshot of the `TextBuffer` and hand it back to the background `_readQueue`, allowing the UI to continue rendering while the search proceeds.
