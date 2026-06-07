# Control Server Queue Contract

Mechanical reference for RPC dispatch queues. Grep-first; no hidden scheduling.

```bash
rg '_readQueue|_executionQueue|executeNestedMethod|MacControlIsReadQueueMethod' src/platform/macos/control
rg 'dispatch_queue_create\("com.dietcode' src/platform/macos/control/MacControlServer.mm
```

---

## Queue names

| Queue | GCD label | Type | Owns |
|-------|-----------|------|------|
| Read | `com.dietcode.runtime.read` | Concurrent | Read-only RPC methods (`MacControlIsReadQueueMethod`) |
| Execution | `com.dietcode.runtime.execution` | Serial | Mutations, task/combo runtime, context methods |
| Main | `dispatch_get_main_queue()` | Serial | UI bridge (`MacControlWindowBridge`), destructive prompts |

Queue identity keys: `kDietCodeReadQueueKey`, `kDietCodeExecutionQueueKey` (set via `dispatch_queue_set_specific`).

---

## Dispatch rules

### Top-level RPC (`processRequest`)

1. `queueForRequestLine` routes by method name → read or execution queue.
2. `isBackgroundMethod` list decides whether `executeMethod` runs on the worker queue directly or is `dispatch_async` to main first.
3. Exactly **one** terminal envelope per request (`sendSuccess` or `sendError`), including `@catch` exceptions.

### Nested RPC (`executeNestedMethod`)

Used by task/combo executors. **Never call `executeMethod` directly from runtime code.**

| Nested method kind | Target queue | Same-queue fast path |
|--------------------|--------------|----------------------|
| `MacControlIsReadQueueMethod` | `_readQueue` | Yes — avoids async re-entry deadlock |
| All other methods | `_executionQueue` | Yes — serial queue must not `dispatch_async` to self |

### UI access

`MacControlWindowBridge` always `dispatch_sync` to main when off main thread. Safe from read or execution queues.

---

## Forbidden patterns

- Calling `executeMethod` from task/combo runtime (bypasses queue contract).
- `dispatch_async(_executionQueue)` from code already running on `_executionQueue` (deadlock).
- Returning `NSMutableDictionary` / `NSDate` in RPC results without JSON sanitization (`sendSuccess` now round-trips via `MacControlJsonSanitizedDictionary`).

---

## Investigation commands

```bash
# Queue hops
rg 'dispatch_sync|dispatch_async' src/platform/macos/control/MacControlServer.mm

# Read-method registry (must stay in sync with routing policy)
rg 'workspace.grep|changes.current' src/platform/macos/control/services/MacControlRoutingPolicy.mm

# Nested executor wiring
rg 'nestedExecutor|executeNestedMethod' src/platform/macos/control/MacControlServer.mm

# Live socket + task health
make test-task-health
make test-rpc-transaction

# Socket process
lsof -U | rg dietcode
ps aux | rg 'DietCode.app/Contents/MacOS/DietCode'
```

---

## Failure envelopes

Queue/runtime failures surface as standard RPC errors — never silent connection drops:

| Scenario | `string_code` |
|----------|---------------|
| Non-JSON result payload | `response_serialization_failed` |
| Oversized success payload | `response_too_large` |
| Unhandled exception | `internal_error` |
| Unknown method | `method_not_found` |

See [Error Codes](error-codes.md) and [Task Server Recovery](task-server-recovery.md).
