# Runtime Contracts (Frozen)

Plain-text operational contracts for the DietCode control kernel. Grep inventory:

```bash
rg 'CONTRACT:|INVARIANT:|RELEASE:' docs/runtime-contracts.md scripts/agent_contracts.py src/platform/macos/control
```

---

## RELEASE: Contract versions

Canonical surfaces (keep C++ and Python in sync — `test_release_readiness.py` → `release.versions_synced`):

| Version ID | Current | Surface |
|------------|---------|---------|
| `contractInventory` | **1.0.0** | This document's contract index |
| `controlProtocol` | 1.6 | RPC transport |
| `transactionSchema` | 1.6.2 | Request `schemaVersion` |
| `clientSchema` | 1.6.2 | Python client `SCHEMA_VERSION` |
| `rpcEnvelope` | 1.0 | `id`, `ok`, `result` / `error` keys |
| `errorTaxonomy` | 1.0 | `string_code` + numeric mapping |
| `diagnostics` | 1.0 | NDJSON `runtime_diagnostic` lines |
| `safetyLimits` | 1.0 | `ControlRuntimeLimits.hpp` |
| `harnessSummary` | 1.0 | NDJSON `type:summary` schema |

Expose via:

```bash
python3 scripts/dietcode_agent_client.py --emit-config --json | rg contractVersions
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.version
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.describe '{"method":"rpc.ping"}'
make release-check-agent-runtime
```

Stability classification: `scripts/fixtures/release/surface_classification.json` (grep `STABILITY:`).

---

## Contract index

| ID | Name | Verify |
|----|------|--------|
| C-QUEUE-01 | Read-queue affinity | `make test-rpc-transaction` + `rg executeNestedMethod` |
| C-QUEUE-02 | Execution-queue mutations | `docs/queue-contract.md` + source grep |
| C-RPC-01 | One terminal envelope per request | `make test-rpc-transaction` |
| C-RPC-02 | Success envelope shape | `scripts/fixtures/rpc/envelope_success.schema.json` |
| C-RPC-03 | Error envelope shape | `scripts/agent_contracts.py` |
| C-RPC-04 | JSON-safe success payloads | `rg MacControlJsonSanitizedDictionary` |
| C-RPC-05 | Serialization failure code | `response_serialization_failed` in `error-codes.md` |
| C-RPC-06 | Oversized response fallback | `rg response_too_large` in `MacControlServer.mm` |
| C-CONN-01 | Failed request does not poison socket | `make test-task-health` |
| C-CONN-02 | Malformed line → error, socket survives | `rpc.malformed_line_survives` check |
| C-TASK-01 | Task failure containment | `make test-task-health` |
| C-HARNESS-01 | NDJSON summary schema | `make test-agent-offline` |
| C-HARNESS-02 | Stable check names | `rg '"name":' scripts/test_*.py` |
| C-HARNESS-03 | Nonzero exit on failure | all `test_*.py` return `finish_test_run` code |
| C-DIAG-01 | Request ID correlation | `rg request_id ~/.dietcode/agent-runtime.ndjson` |
| C-DIAG-02 | Runtime NDJSON log schema | `make test-operator-diagnostics` |
| C-DIAG-03 | Error envelope diagnostics | `assert_rpc_error_diagnostics` in harnesses |
| C-DIAG-04 | Diagnostic snapshot command | `python3 scripts/dietcode_agent_client.py --diagnose --json` |
| C-AGENT-01 | Literal grep disk fallback | `make test-grep-diff-tooling` |
| C-AGENT-02 | Grep response schema | `GREP_RESPONSE_KEYS` in `agent_contracts.py` |
| C-AGENT-03 | Stale-write rejection | `expectBeforeHash` → `stale_content` (`make test-runtime-determinism`) |
| C-AGENT-04 | Mutation receipt shape | `MUTATION_RECEIPT_KEYS` (`make test-runtime-determinism`) |
| C-AGENT-05 | Workspace revision monotonicity | `make test-transaction-kernel` |
| C-AGENT-06 | Batch atomicity + rollback | `patch.applyBatch` (`make test-transaction-kernel`) |
| C-AGENT-07 | Symlink skip-never-follow | `make test-harness-realism` |
| C-AGENT-08 | Deterministic path search (no score) | `SEARCH_FILES_RESPONSE_KEYS` (`make test-harness-realism`) |
| C-AGENT-09 | Semantic search quarantine | `semantic_disabled` (4008) (`make test-deterministic-retrieval`) |
| C-AGENT-10 | Tool registry agent-safe surface | `TOOL_REGISTRY_*` (`make test-deterministic-retrieval`) |
| C-AGENT-11 | Partial-success enrichment | `PARTIAL_SUCCESS_OPTIONAL_KEYS` (`make test-partial-success-closure`) |
| C-AGENT-12 | Error recovery hints | `ERROR_RECOVERY_HINTS` (`make test-docs-code-drift`) |
| C-AGENT-13 | Internal method namespaces | `INTERNAL_METHOD_NAMESPACES` fixture |

Audit pass mapping: [Agent Runtime Audit](agent-runtime-audit.md).

---

## C-QUEUE-01: Read-queue affinity

**CONTRACT:** Methods in `MacControlIsReadQueueMethod` MUST execute on `com.dietcode.runtime.read`.

**INVARIANT:** Nested runtime calls use `executeNestedMethod`, never raw `executeMethod`.

```bash
rg 'MacControlIsReadQueueMethod|executeNestedMethod' src/platform/macos/control
make test-task-health
```

---

## C-QUEUE-02: Execution-queue mutations

**CONTRACT:** Non-read RPC methods and nested mutations run on `com.dietcode.runtime.execution` (serial).

**INVARIANT:** Same-queue nested calls use `dispatch_get_specific` fast path (no async self-dispatch).

See [Queue Contract](queue-contract.md).

---

## C-RPC-01: One terminal envelope per request

**CONTRACT:** Each accepted request produces exactly one newline-delimited JSON object with terminal `ok`.

**INVARIANT:** `processRequest` ends in `sendSuccess`, `sendError`, or `@catch` → `sendError`.

```bash
make test-rpc-transaction
rg 'sendSuccess|sendError|@catch' src/platform/macos/control/MacControlServer.mm
```

---

## C-RPC-02: Success envelope shape

**CONTRACT:** `ok: true` responses include `id`, `ok`, `result` (object).

Fixture: `scripts/fixtures/rpc/envelope_success.schema.json`

---

## C-RPC-03: Error envelope shape

**CONTRACT:** `ok: false` responses include `error.code`, `error.string_code`, `error.message`.

Golden codes: `scripts/fixtures/rpc/expected_error_codes.json`

```bash
make test-rpc-transaction
rg 'assert_rpc_envelope|RPC_ERROR_ENVELOPE_KEYS' scripts/
```

---

## C-RPC-04: JSON-safe success payloads

**CONTRACT:** `sendSuccess` round-trips results through `MacControlJsonSanitizedDictionary` before serialization.

```bash
rg 'MacControlJsonSanitizedDictionary' src/platform/macos/control
```

---

## C-RPC-05: Serialization failure

**CONTRACT:** Non-serializable success payloads become `response_serialization_failed` errors (not silent drops).

---

## C-RPC-06: Oversized response

**CONTRACT:** Success payloads over 4 MB become `response_too_large` with a written fallback line.

```bash
rg 'response_too_large' src/platform/macos/control/MacControlServer.mm
```

---

## C-CONN-01: Connection survives failures

**CONTRACT:** One failed RPC on a connection MUST NOT prevent the next RPC on that connection.

Checks: `task.runloop_same_connection`, `rpc.invalid_params_envelope`, `rpc.method_not_found_envelope`

```bash
make test-task-health
make test-rpc-transaction
```

---

## C-CONN-02: Malformed JSON line

**CONTRACT:** A malformed NDJSON line returns `invalid_request` and the connection remains usable.

Fixture: `scripts/fixtures/rpc/malformed_line.txt`

---

## C-TASK-01: Task lifecycle containment

**CONTRACT:** Task step failures are contained in `results[]`; outer RPC remains `ok: true` unless params invalid.

Unknown `taskId` → `invalid_params` per fixture.

```bash
make test-task-health
```

---

## C-HARNESS-01: NDJSON summary schema

**CONTRACT:** Every harness ends with:

```json
{"type":"summary","suite":"...","ok":bool,"checks":N,"passed":N,"failed":N,"failedNames":[]}
```

Constants: `scripts/agent_contracts.py` → `SUMMARY_SCHEMA_KEYS`

```bash
make test-agent-offline
python3 scripts/test_contract_lockdown.py --compact | rg '"type":"summary"'
```

---

## C-HARNESS-02: Stable check names

**CONTRACT:** Check `name` fields use dotted stable identifiers (`rpc.golden_ping_success`, not prose).

```bash
rg '"name":' scripts/test_*.py scripts/control_smoke_test.py
```

---

## C-HARNESS-03: Exit codes

**CONTRACT:** Failed suites exit nonzero; successful suites exit 0.

```bash
make verify-agent-runtime
echo $?
```

---

## Operational verification

### Verify RPC contract

```bash
make test-rpc-transaction
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.ping
python3 scripts/dietcode_agent_client.py --raw-response --json __no_such_method__
```

### Verify queue safety

```bash
rg '_readQueue|_executionQueue|executeNestedMethod' src/platform/macos/control
make test-task-health
```

### Verify failure containment

```bash
make test-rpc-transaction | rg 'failedNames'
make test-task-health | rg '"ok":false' || echo "all passed"
```

### Verify harness summaries

```bash
make test-agent-offline | rg '"type":"summary"'
python3 -c "from scripts.agent_contracts import validate_summary_line; print(validate_summary_line({'type':'summary','suite':'x','ok':True,'checks':0,'passed':0,'failed':0,'failedNames':[]}))"
```

### Verify error codes

```bash
rg 'string_code' docs/error-codes.md scripts/fixtures/rpc/expected_error_codes.json
cat scripts/fixtures/rpc/expected_error_codes.json | python3 -m json.tool
```

### Review this pass

```bash
git diff src/platform/macos/control scripts/ docs/ Makefile
```

---

## Strongest local ladder

```bash
make release-check-agent-runtime
make verify-agent-runtime
# offline only:
python3 scripts/release_check_agent_runtime.py --compact --skip-live
```

---

## C-DIAG-01: Request correlation

**CONTRACT:** Each server-handled RPC emits `runtime_diagnostic` NDJSON lines keyed by stable `request_id` through parse → dispatch → response phases.

Log path: `~/.dietcode/agent-runtime.ndjson`

```bash
make test-operator-diagnostics
rg 'operator-diag-correlation' ~/.dietcode/agent-runtime.ndjson
```

---

## Intentionally not added

This pass freezes contracts with grep/diff-first tooling only. The following were **not** introduced:

- Semantic graphs, embeddings, or vector search
- Fuzzy matching or opaque agent memory
- Hidden routing or dynamic scheduling frameworks
- Abstraction-heavy test harnesses (shared base classes, reflection-driven discovery)
- Live `response_too_large` trigger (only static source grep + fixture entry; no synthetic 4 MB payload against a running server)
- Auto-sync between `READ_METHODS` in Python and `MacControlMethodCatalog.mm` (manual grep audit remains the source of truth)
- NDJSON conversion of legacy v1.6/v1.7 prose integration scripts (`test_v1_6_*.py`, `test_v1_7_*.py`)
- CI workflow YAML or hosted runner configuration (Makefile targets are CI-ready; wiring is left to the consumer)
- Machine-readable audit log beyond plain NDJSON harness output

Operator diagnostics pass (separate): see [Operator Diagnostics](operator-diagnostics.md) intentionally-not-added section for tracing/metrics exclusions.

Release readiness pass: see [Maintainer Guide](maintainer-guide.md) intentionally-not-added section for release framework exclusions.

Regressions should surface as **grep misses**, **diff-visible contract drift**, or **nonzero harness exit** — not silent behavioral change.

---

## C-AGENT-01 through C-AGENT-13: Agent runtime audit contracts

**CONTRACT:** Passes I–VI freeze deterministic agent surfaces in `scripts/agent_contracts.py`. Live behavior is verified by per-pass harnesses and rolled up in `make verify-agent-runtime` / `make verify-agent-runtime-full`.

Key frozen constants:

```bash
rg 'GREP_RESPONSE_KEYS|MUTATION_RECEIPT_KEYS|TOOL_REGISTRY|PARTIAL_SUCCESS|ERROR_RECOVERY' scripts/agent_contracts.py
make verify-agent-runtime-full
```

See [Agent Runtime Audit](agent-runtime-audit.md) for implementation file paths and migration table.

---

## Related docs

- [Agent Runtime Audit](agent-runtime-audit.md)
- [Agent Tooling](agent-tooling.md)
- [Runtime Invariants](runtime-invariants.md)
- [Queue Contract](queue-contract.md)
- [Error Codes](error-codes.md)
- [Task Server Recovery](task-server-recovery.md)
- [Agent Environment](agent-environment.md)
- [Build & Test System](build-and-test-system.md)
