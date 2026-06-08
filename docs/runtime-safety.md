# Runtime Safety (Local Abuse-Resistance)

Plain-text safety audit for the DietCode control runtime. Grep inventory:

```bash
rg 'SAFETY:|RUNTIME_LIMITS|socket_symlink|connection_limit_exceeded' src/ scripts/ docs/
```

---

## Safety audit summary

| Area | Enforcement | Verify |
|------|-------------|--------|
| Socket path | `MacControlSocketSafety`, `0700` dir, `0600` socket, symlink/owner checks | `audit_socket_path()` + server startup |
| Request size | `kMaxRequestBytes` (1 MB) per line/buffer | `safety.oversized_request` |
| Response size | `kMaxResponseBytes` (4 MB) | `docs/error-codes.md` |
| Concurrency | `kMaxActiveConnections` (8), `kMaxPendingRequestsPerConnection` (32) | source grep + stable `429` codes |
| Malformed flood | `kMaxMalformedRequestsPerConnection` (16) | `safety.malformed_survival` |
| Nested calls | `kMaxNestedCallWaitSeconds` (120) | `nested_call_timeout` |
| Log growth | `kMaxRuntimeDiagnosticLogBytes`, `kMaxAuditLogBytes` (5 MB rotate) | `runtime_safety.py` |
| Failure bundles | `kMaxFailureBundleBytes` (2 MB) + redaction | `capture_failure_bundle.py` |
| Secrets in diagnostics | `redact_diagnostic_snapshot()` | `safety.redact_diagnostic_snapshot` |

Canonical limits header: `src/domain/control/ControlRuntimeLimits.hpp`  
Python mirror: `scripts/runtime_safety.py` → `RUNTIME_LIMITS`

---

## Runtime limit constants

```bash
rg 'constexpr.*kMax' src/domain/control/ControlRuntimeLimits.hpp
python3 -c "from scripts.runtime_safety import RUNTIME_LIMITS; print(sorted(RUNTIME_LIMITS.items()))"
```

| Constant | Value |
|----------|-------|
| `kMaxRequestBytes` | 1,048,576 (1 MB) |
| `kMaxResponseBytes` | 4,194,304 (4 MB) |
| `kMaxActiveConnections` | 8 |
| `kMaxPendingRequestsPerConnection` | 32 |
| `kMaxMalformedRequestsPerConnection` | 16 |
| `kMaxNestedCallWaitSeconds` | 120 |
| `kMaxRuntimeDiagnosticLogBytes` | 5,242,880 (5 MB) |
| `kMaxFailureBundleBytes` | 2,097,152 (2 MB) |
| `kSocketFileMode` | `0600` |
| `kDietcodeDirMode` | `0700` |

---

## Socket safety

### Server startup checks

- `~/.dietcode` must not be a symlink; must be owned by current user; mode `0700`
- Existing `control.sock` checked before bind: no symlink, correct owner, mode `0600`
- Stale socket unlinked only after safety check passes
- Unsafe startup emits `runtime_diagnostic` with `string_code` like `socket_symlink`

### Stable socket error codes

| string_code | Meaning |
|-------------|---------|
| `socket_symlink` | Path or parent is a symlink |
| `socket_wrong_owner` | Not owned by current user |
| `socket_unsafe_permissions` | World/group writable or unexpected mode |
| `socket_unsafe_type` | Not a socket/file/dir as expected |
| `socket_unsafe_path` | Empty or invalid path |

### How to verify local socket safety

```bash
python3 scripts/dietcode_agent_client.py --diagnose --json | rg 'socketAudit|isSymlink|ownerIsCurrentUser'
python3 -c "from scripts.runtime_safety import audit_socket_path; import json; print(json.dumps(audit_socket_path('~/.dietcode/control.sock'), indent=2))"
ls -la ~/.dietcode ~/.dietcode/control.sock
```

### How to clean stale sockets/logs

```bash
# Stop DietCode first, then:
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
rm -f ~/.dietcode/control.sock
# Optional log rotation preview:
wc -c ~/.dietcode/agent-runtime.ndjson ~/.dietcode/control_audit.log 2>/dev/null
```

---

## Concurrency guardrail errors

| string_code | numeric | When |
|-------------|---------|------|
| `connection_limit_exceeded` | 429 | More than 8 active connections |
| `too_many_pending` | 429 | More than 32 in-flight requests on one connection |
| `malformed_request_flood` | 429 | More than 16 malformed lines per connection |
| `nested_call_timeout` | 429 | Nested executor wait exceeded 120s |

---

## Log and artifact hygiene

### Redaction rules (grep: `redact_` in `scripts/runtime_safety.py`)

- Environment keys containing `TOKEN`, `SECRET`, `KEY`, `PASSWORD`, `CREDENTIAL` → `[REDACTED]`
- 32-char hex sequences → `[REDACTED_TOKEN]`
- `Bearer ...` headers → `Bearer [REDACTED]`
- Token file **contents** never included in `--diagnose` output
- Failure bundle stdout/stderr/gitDiff truncated per `kMaxFailureBundleBytes`

### How to capture diagnostics without leaking secrets

```bash
python3 scripts/dietcode_agent_client.py --diagnose --json > /tmp/diag.ndjson
rg 'REDACTED|sekrit|session.token' /tmp/diag.ndjson || echo "no obvious leaks"
python3 scripts/capture_failure_bundle.py --compact -- make test-runtime-safety | rg '"redacted":true'
```

---

## How to run abuse-resistance checks

```bash
make test-runtime-safety
make verify-agent-runtime
make test-agent-offline
```

---

## How to inspect runtime limits

```bash
rg 'kMaxActiveConnections|kMaxPendingRequestsPerConnection' src/platform/macos/control/MacControlServer.mm
python3 scripts/test_runtime_safety.py --compact
```

---

## How to classify destructive methods

See [Operator Policy](operator-policy.md) and fixture:

```bash
cat scripts/fixtures/safety/destructive_methods.json
rg 'Destructive|Execute' src/platform/macos/control/services/MacControlMethodCatalog.mm
```

---

## Review this pass

```bash
git diff src/platform/macos/control scripts/ docs/ Makefile src/domain/control/
rg 'SAFETY:|test-runtime-safety|runtime_safety' scripts/ docs/ Makefile
```

---

## Intentionally not added

- Semantic graphs, embeddings, vector search, fuzzy matching, opaque agent memory
- Telemetry upload, metrics platform, distributed rate limiting
- Hidden routing or dynamic orchestration framework
- Abstraction-heavy security framework (no policy engine, no RBAC service)
- Interactive permission theater beyond existing destructive confirmation UI
- Cloud-side socket brokering or remote attestation
- Automatic secret scanning beyond deterministic grep/redact rules

Regressions should surface via **grep misses**, **limit constant drift**, **harness `failedNames`**, or **nonzero `make test-runtime-safety`**.

---

## Related docs

- [Agent Runtime Audit](agent-runtime-audit.md)
- [Operator Policy](operator-policy.md)
- [Operator Diagnostics](operator-diagnostics.md)
- [Runtime Contracts](runtime-contracts.md)
- [Error Codes](error-codes.md)
