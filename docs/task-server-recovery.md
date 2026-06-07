# Task Server Recovery & Live-Socket Health

Copy-paste workflows for reproducing, locating, and recovering from task-related control-socket failures.

---

## Grep anchors

```bash
# Task runtime routing
rg 'task\.runLoop|taskRunLoop|task\.result' src/platform/macos/control

# Nested executor (read-queue isolation fix)
rg 'executeNestedMethod' src/platform/macos/control/MacControlServer.mm

# Task regression harness
rg 'task_server_health|task.runloop_same_connection' scripts/
```

---

## Rebuild and restart (required after native patches)

```bash
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
make app
build/DietCode.app/Contents/MacOS/DietCode --ensure-socket --ensure-timeout 15
python3 scripts/dietcode_agent_client.py --wait-ready --json
```

---

## Reproduce the historical failure

Before the `executeNestedMethod` fix, `task.runLoop` and `task.result` called `changes.current` from the execution queue thread. That could close the client socket without sending a response.

```bash
# Start a task
python3 scripts/dietcode_agent_client.py --raw-response --json task.start '{"goal":"repro"}'

# Run empty runLoop (use taskId from prior response)
python3 scripts/dietcode_agent_client.py --raw-response --json task.runLoop \
  '{"taskId":"task-1","steps":[]}'

# Same connection should still answer (regression check)
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.describe '{"method":"task.runLoop"}'
```

Expected after fix: all three return JSON envelopes; the connection stays open; `task.runLoop` returns `"status":"complete"`.

---

## Focused regression suite

```bash
make test-task-health
python3 scripts/test_task_server_health.py --compact | rg '"type":"summary"'
python3 scripts/test_task_server_health.py --compact | rg '"ok":false'
```

Checks:

| Check name | Asserts |
|------------|---------|
| `task.runloop_same_connection` | `task.runLoop` completes; `rpc.describe` works on same socket |
| `task.result_same_connection` | `task.result` returns `finalDiff` + `verify`; `rpc.ping` succeeds |
| `task.invalid_params_survives` | unknown `taskId` → `invalid_params`; socket survives |

---

## Socket health probes

```bash
python3 scripts/dietcode_agent_client.py --status --json
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.ping
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.describe '{"method":"task.runLoop"}'
```

---

## Review server patches

```bash
git diff src/platform/macos/control/MacControlServer.mm
git diff src/platform/macos/control/services/MacControlTaskRuntime.mm
```

Key fix: `executeNestedMethod` routes `MacControlIsReadQueueMethod` calls (including `changes.current`, `verify.status`) through `_readQueue`, matching standalone RPC dispatch.

---

## Full integration rollup

```bash
make agent-integration
python3 scripts/run_agent_integration_tests.py --compact | rg '"failedNames"'
```

See [Agent Environment](agent-environment.md) and [Error Codes](error-codes.md).
