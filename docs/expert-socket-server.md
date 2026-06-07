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

The Python agent client preserves probe diagnostics while checking the socket. A failed probe can now report `not_found`, `connection_refused`, `timeout`, `permission_denied`, or an OS-level error. This matters in managed or sandboxed environments where the socket file may exist and be owned by the current user, but the calling process is not allowed to connect. In that case, the client reports the permission denial directly instead of misclassifying the server as inactive.

Startup recovery intentionally avoids unlinking an existing current-user socket from the client. If the socket refuses connections, the client delegates recovery to the native `--ensure-socket` path so the server lifecycle stays owned by the DietCode binary.

### 3. Frame Integrity
The server enforces a `kMaxRequestBytes` (1MB) limit on every JSON frame to prevent memory exhaustion attacks from malicious or runaway agents.

---

## 🚦 Thread Synchronization: The Window Bridge

When an RPC method needs to interact with the UI (e.g., `editor.insertText`), the `MacControlWindowBridge` performs a `dispatch_sync` to the **Main Thread**.

- **Deadlock Prevention**: The bridge is carefully engineered to only sync for UI-bound operations. Core domain logic and filesystem reads stay on the background RPC queues.
- **Atomic Snapshots**: For search operations, the bridge can capture a snapshot of the `TextBuffer` and hand it back to the background `_readQueue`, allowing the UI to continue rendering while the search proceeds.
- **Headless Guards**: UI-adjacent read methods such as `workspace.openFile`, `language.hover`, `language.completions`, and `language.definition` short-circuit safely in headless mode when editor views or UI-backed LSP state are unavailable. They return explicit headless results rather than invoking uninitialized UI paths.

---

## Event Stream Isolation

`event.subscribe` turns a socket connection into a duplex stream: it still receives the subscription response, and then receives asynchronous `event.emitted` frames. `scripts/dietcode_agent_client.py` keeps a per-socket read buffer, serializes reads on that socket, scopes temporary socket timeouts to each call, skips notification frames while waiting for a matching response id, and fails fast if it receives a mismatched response id. Listener loops should use `DietCodeAgentClient.event_subscription(...)`, `iter_events(...)`, or `read_rpc_frame` so they drain the same buffer as request/response calls.

Dedicated event connections are still recommended for long-running listeners. They avoid a common race where two different readers in the same process compete for one socket and consume each other's frames. Clean listeners should call `event.unsubscribe` before shutting down, though closing the subscribed socket also drops its subscription state. Event type lists must be non-empty strings; the Python helper validates that before sending subscription RPCs. For bounded automation, prefer `iter_events(..., max_events=N, idle_timeout=SECONDS)` or CLI `--listen-max-events` plus `--listen-idle-timeout`.

## Verification commands

```bash
# Offline transport checks (mock socketpair; no live server)
python3 scripts/dietcode_agent_client.py --self-test --compact

# Socket probe diagnostics (permission_denied vs connection_refused)
python3 scripts/dietcode_agent_client.py --status --compact | python3 -m json.tool

# Bounded event listener (stdout = NDJSON frames, stderr = status unless --quiet)
python3 scripts/dietcode_agent_client.py --listen --listen-type terminal.output \
  --listen-max-events 1 --listen-idle-timeout 2 --compact --error-json

# Grep the error-code mapping table
rg 'stringCode isEqualToString' src/platform/macos/control/MacControlServer.mm
```

See [Error Codes](error-codes.md) and [Headless Agent Control](headless-agent-control.md) for the full verification ladder.
