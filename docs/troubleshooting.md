# Troubleshooting

## Kernel socket

**Symptom:** `socket not active`, `transport_error`, bridge banner "Kernel offline".

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

Stale binary after `git pull`:

```bash
make kernel && make restart-agent-server-fast
```

Socket path: `~/.dietcode/control.sock`. Token: `~/.dietcode/session.token` (mode `0600`).

## Bridge: invalid session token

**Symptom:** `kernelConnected: false`, `Invalid or missing session token`.

Bridge RPC must send `token` at the top level of each kernel request (not inside `params`). Restart bridge after kernel restart so it reads the new token file.

```bash
pkill -f "tsx server/bridge.ts"
cd cockpit && npm run bridge
```

## Missing RPC method (e.g. `workspace.status`)

**Symptom:** `method_not_found`, `Unhandled file/workspace/search method`.

Running kernel is older than source. Rebuild and restart:

```bash
make kernel restart-agent-server-fast
```

## Workspace drift blocks patches

**Symptom:** `workspaceDriftRequired`, checkpoint 2 active, `workspace.drift.detected`.

```bash
# Via bridge
curl -X POST http://127.0.0.1:9477/api/workspace/refresh-anchor

# Via kernel RPC
python3 scripts/dietcode_agent_client.py rpc workspace.refreshAnchor
```

Or use cockpit Drift panel: **Refresh context**. See [workspace-drift.md](workspace-drift.md).

## Approval stuck

**Symptom:** Task `awaiting_approval`, pending approval in kernel.

```bash
curl http://127.0.0.1:9477/api/approvals?status=pending
curl -X POST http://127.0.0.1:9477/api/approvals/<id>/resolve \
  -H 'Content-Type: application/json' \
  -d '{"decision":"approved","resolvedBy":"cockpit"}'
```

Approvals expire after 30 minutes. See [approval-lifecycle.md](approval-lifecycle.md).

## Task completed before verify

**Symptom:** Agent exited 0 but task not `completed`.

Expected: mutations arm checkpoint 5. Run verify from cockpit or:

```bash
curl -X POST http://127.0.0.1:9477/api/tasks/<taskId>/run-verify \
  -H 'Content-Type: application/json' \
  -d '{}'
```

## Verify command rejected

**Symptom:** `verify.run command must match AgentVerifyCommands prefixes`.

Allowed defaults include `make test`, `npm test`, `./verify.sh`. Custom commands need kernel allowlist or `AgentVerifyCommands` user defaults.

For subproject workspaces, bridge passes `cwd` relative to kernel root when task workspace is a subdirectory.

## `cockpit-smoke` failures

```bash
make cockpit-smoke 2>&1 | python3 -c "
import sys, json
for line in sys.stdin:
    if line.strip().startswith('{'):
        o=json.loads(line)
        if o.get('type')=='check' and not o.get('ok'):
            print(o)
"
```

Common causes:

- Kernel not restarted after C++ pull
- Port 9477 in use by stale bridge
- Fixture workspace not under kernel root (`build/cockpit-smoke-ws`)

## Docs / contract drift

```bash
make test-docs-code-drift
```

## Error code lookup

```bash
rg 'string_code' docs/error-codes.md
```

Every failure envelope should include `string_code`, `recovery_hint`, `nextRecommendedCommand` when applicable.

## Still stuck

1. `make checkpoint-core` — reproduces the full baseline
2. [getting-started.md](getting-started.md) — clean build path
3. [architecture.md](architecture.md) — component boundaries
