# Technical Deep Dive: Data Flow and Orchestration

This guide visualizes how data and commands flow through the DietCode architecture, from an external agent's RPC call to the native macOS UI and back.

---

## 🛰️ Anatomy of an RPC Call (Agent -> IDE)

When an agent calls `editor.insertText`, the following sequence occurs:

```text
[External Agent]
      | (JSON-RPC over Unix Socket)
      v
[MacControlServer] (src/platform/macos/control/MacControlServer.mm)
      | 1. Parses JSON frame
      | 2. Validates session token
      v
[MacControlComboRuntime] (src/platform/macos/control/services/MacControlComboRuntime.mm)
      | 3. Acquires Path Lock for the file
      | 4. Dispatches to Method Executor
      v
[MacControlWindowBridge] (src/platform/macos/control/services/MacControlWindowBridge.mm)
      | 5. Switches from Control Thread to Main UI Thread (dispatch_sync)
      v
[MacWindow+AgentAPI] (src/platform/macos/ui/controllers/categories/MacWindow+AgentAPI.mm)
      | 6. Locates the correct NSTextView for the path
      | 7. Performs -[NSTextView replaceCharactersInRange:withString:]
      | 8. Marks tab as dirty and updates UI
      v
[MacControlServer]
      | 9. Returns { "ok": true } response to socket
      v
[External Agent]
```

---

## 🔔 Anatomy of an Event (IDE -> Agent)

When a user manually saves a file, the following sequence occurs:

```text
[User Action] (Cmd+S)
      |
      v
[MacWindow+Files] (src/platform/macos/ui/controllers/categories/MacWindow+Files.mm)
      | 1. Triggers -[self saveTab:]
      | 2. Calls fileService.writeTextFile()
      v
[EventBus] (src/core/Event.hpp)
      | 3. IDE core emits DocumentSaved event
      v
[MacControlServer] (src/platform/macos/control/MacControlServer.mm)
      | 4. Listener in Control Server catches the event
      | 5. Identifies all socket clients subscribed to DocumentSaved
      | 6. Serializes event to JSON
      v
[External Agent]
      | (Receives notification frame)
```

---

## 🌳 The "Chip & Combo" Transaction Flow

For high-fidelity multi-file mutations, DietCode uses a transactional "Combo" flow:

1. **Pre-flight**: `MacControlComboRuntime` validates the entire plan version and permissions.
2. **Checkpoint**: `MacControlRecoveryStore` takes a "Pre-image" of every file in the scope (hashes + literal backups).
3. **Execution**: Chips are executed sequentially. Each successful step updates the manifest's `expectedPostimageHash`.
4. **Validation**: If a step fails or a budget is exceeded, the **Rollback** logic is triggered.
5. **Rollback**: `MacControlRecoveryStore` restores every file in the manifest to its Pre-image state, ensuring the workspace is never left in a "half-broken" state.

---

## 🛠️ Hands-On: Debugging the Flow

If you are developing a new RPC method or debugging an event, use these probe points:

- **Socket Level**: Run `tail -f ~/.dietcode/control.log` to see real-time RPC traffic.
- **Server Level**: Set a breakpoint in `MacControlServer.mm` at `processMessage:`.
- **Bridge Level**: Check `MacControlWindowBridge.mm` to see how thread-switching is handled.
- **Core Level**: Use `dietcode::core::Logger` to log events flowing through the `EventBus`.
