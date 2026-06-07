# Operator Diagnostics

Plain-text operator workflows for diagnosing DietCode control runtime failures. Grep inventory:

```bash
rg 'request_id|runtime_diagnostic|recovery_hint|diagnostic_snapshot' src/ scripts/ docs/
```

---

## Quick reference

| Artifact | Path / command |
|----------|----------------|
| Runtime NDJSON log | `~/.dietcode/agent-runtime.ndjson` |
| Audit log (legacy text) | `~/.dietcode/control_audit.log` |
| Diagnostic snapshot | `python3 scripts/dietcode_agent_client.py --diagnose --json` |
| Failure bundle | `python3 scripts/capture_failure_bundle.py -- make test-operator-diagnostics` |
| Contract inventory | [Runtime Contracts](runtime-contracts.md) |
| Error taxonomy | [Error Codes](error-codes.md) |

---

## How to diagnose a failed RPC

1. Re-run with full envelope and client timing:

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json --error-json --verbose rpc.ping
```

2. Note the stable fields (do not rely on prose):

- `id` / `error.request_id`
- `error.string_code`
- `error.phase`
- `error.recovery_hint`

3. Grep the runtime log for the same `request_id`:

```bash
rg 'your-request-id' ~/.dietcode/agent-runtime.ndjson
```

4. Follow the `recovery_hint` or run health verification:

```bash
make verify-agent-runtime
```

---

## How to trace one request

Server phases (grep-friendly `phase` values):

| Phase | Meaning |
|-------|---------|
| `request_accepted` | NDJSON line parsed enough to read `id` |
| `request_parsed` | `method` validated |
| `queue_dispatch` | Dispatched to read/execution/main queue |
| `response_success` | Terminal success envelope |
| `response_error` | Terminal error envelope |
| `serialization_fallback` | JSON encode or size limit fallback |
| `exception` | `@catch` containment path |
| `connection_close` | Client disconnect cleanup |

```bash
# Trace one request ID through server log
REQUEST_ID='my-req-1'
python3 scripts/dietcode_agent_client.py --raw-response --json --request-id "$REQUEST_ID" rpc.ping
rg "$REQUEST_ID" ~/.dietcode/agent-runtime.ndjson
```

Client-side correlation (stderr when `--verbose` or `--error-json`, or on failure):

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json --verbose --request-id trace-1 rpc.ping 2>&1 | rg client_diagnostic
```

---

## How to capture a diagnostic snapshot

```bash
python3 scripts/dietcode_agent_client.py --diagnose --json
```

Snapshot includes: socket/token/app state, process probe, Makefile verification targets, doc paths, recent runtime log lines, timeout defaults, and copy-paste recovery commands.

Safe to paste into an issue — local only, no upload.

---

## How to confirm queue ownership

```bash
rg '_readQueue|_executionQueue|executeNestedMethod|queueLabelForMethod' src/platform/macos/control
make test-task-health
```

Failed RPC envelopes may include `error.queue` (`com.dietcode.runtime.read`, `com.dietcode.runtime.execution`, or `com.dietcode.runtime.main`).

---

## How to produce a failure bundle

```bash
python3 scripts/capture_failure_bundle.py --compact -- make test-operator-diagnostics
```

Bundle fields (single NDJSON object):

- `command`, `exitCode`, `durationMs`
- `stdout` / `stderr` (split)
- `summary` (last harness `type:summary` if present)
- `contractIds` (frozen contract IDs involved)
- `gitDiff` (control/scripts/docs/Makefile)
- `rg` excerpts for `request_id`, `runtime_diagnostic`, `recovery_hint`
- `recoveryCommands`

No zip, telemetry, or external services.

---

## How to inspect runtime contracts

```bash
rg 'CONTRACT:|INVARIANT:' docs/runtime-contracts.md scripts/agent_contracts.py src/platform/macos/control
make test-agent-offline
make verify-agent-runtime
```

---

## NDJSON runtime diagnostic line schema

Each line in `~/.dietcode/agent-runtime.ndjson`:

```json
{"type":"runtime_diagnostic","timestamp":"2026-06-07T12:00:00Z","request_id":"req-1","method":"rpc.ping","phase":"response_success","ok":true,"queue":"com.dietcode.runtime.read","duration_ms":3}
```

Constants: `scripts/agent_contracts.py` → `RUNTIME_DIAGNOSTIC_LINE_KEYS`

---

## Error envelope diagnostic fields (optional, stable)

On `ok: false`, `error` may also include:

| Field | Stable? | Purpose |
|-------|---------|---------|
| `request_id` | Yes | Grep correlation (matches top-level `id`) |
| `category` | Yes | `validation`, `transport`, `resource`, `auth`, `serialization`, `domain`, `recovery` |
| `retryable` | Yes | Boolean hint only — not auto-retry |
| `phase` | Yes | Server phase at failure |
| `queue` | Yes | Dispatch queue label when known |
| `recovery_hint` | Yes | Short stable token (e.g. `make verify-agent-runtime`) |

Required contract keys remain: `code`, `string_code`, `message`.

---

## Latency and timeout visibility

| Layer | Default | Override |
|-------|---------|----------|
| Socket connect / ensure | 10s | `--timeout` |
| Per-RPC read | 30s | `--request-timeout` |
| Socket probe | 2s | internal |
| Client RPC round-trip | measured | `_client_duration_ms` + `client_diagnostic` stderr line |

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json --verbose --request-timeout 5 rpc.ping 2>&1 | rg 'duration_ms'
```

---

## Verification commands

```bash
make test-operator-diagnostics
make verify-agent-runtime
python3 scripts/dietcode_agent_client.py --self-test --compact | rg diagnostic
rg 'request_id|runtime_diagnostic|MacControlAppendRuntimeDiagnostic' src/ scripts/ docs/
git diff src/platform/macos/control scripts/ docs/ Makefile
```

---

## Intentionally not added

- Semantic graphs, embeddings, vector search, or fuzzy log matching
- Opaque agent memory or hidden routing
- Dynamic tracing framework (OpenTelemetry, spans, sampling)
- Metrics platform or hosted telemetry
- Auto-upload failure bundles
- Unstable prose in test assertions (`recovery_hint` values are stable tokens, not sentences)

Regressions should surface via **grep misses**, **missing diagnostic keys in tests**, or **nonzero harness exit**.

---

## Related docs

- [Runtime Contracts](runtime-contracts.md)
- [Error Codes](error-codes.md)
- [Queue Contract](queue-contract.md)
- [Task Server Recovery](task-server-recovery.md)
- [Expert Socket Server](expert-socket-server.md)
