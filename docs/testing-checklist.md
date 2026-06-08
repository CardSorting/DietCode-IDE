# Testing Checklist

Audit context: [Agent Runtime Audit](agent-runtime-audit.md). Full ladder: `make verify-agent-runtime-full`.

---

## Preflight (every change)

- [ ] `make test` passes (C++ unit tests + offline self-test)
- [ ] `make app` builds without warnings treated as errors
- [ ] After C++ control changes: `make restart-agent-server` before live harnesses
- [ ] `make agent-ready` → `make agent-status` reports `"ok":true`
- [ ] `python3 scripts/dietcode_agent_client.py --emit-config --json` shows resolved paths

---

## Agent / RPC — offline

- [ ] `make agent-self-test` passes (no socket)
- [ ] `make test-agent-offline` passes (self-test + contract lockdown)
- [ ] `make test-docs-code-drift` passes (docs ↔ fixtures ↔ source parity)
- [ ] Error envelopes use stable `string_code` ([Error Codes](error-codes.md))
- [ ] Runtime contracts documented ([Runtime Contracts](runtime-contracts.md))

---

## Agent / RPC — core live

- [ ] `make control-smoke` emits NDJSON summary with `"ok":true`
- [ ] `make test-rpc-transaction` passes
- [ ] `make test-task-health` passes
- [ ] `make test-operator-diagnostics` passes
- [ ] `python3 scripts/dietcode_agent_client.py --diagnose --json` shows socket/RPC readiness
- [ ] `make test-runtime-safety` passes
- [ ] `make test-ergonomics` passes
- [ ] `make agent-integration` passes smoke + ergonomics rollup

---

## Pass I — Grep / diff / patch

- [ ] `make test-grep-diff-tooling` passes
- [ ] Grep returns disk fallback hits headless (`filesReadFromDisk` > 0 when files on disk match)
- [ ] Contracts documented in [Agent Tooling](agent-tooling.md)

---

## Pass II — Runtime determinism

- [ ] `make test-runtime-determinism` passes
- [ ] `stale_content` returned when `expectBeforeHash` mismatches
- [ ] `mutationReceipt` present on successful `patch.apply`
- [ ] Invariants in [Runtime Invariants](runtime-invariants.md)

---

## Pass III — Transaction kernel

- [ ] `make test-transaction-kernel` passes
- [ ] `workspace.revision` bumps after mutation
- [ ] `patch.applyBatch` rolls back atomically on failure
- [ ] `operation.status` resolves idempotency replay

---

## Pass IV — Harness realism

- [ ] `make test-harness-realism` passes
- [ ] `search.files` has no `score` field; `searchMode: deterministic_path_match`
- [ ] Symlink paths skipped in search; patch rejects `symlink_target`
- [ ] `workspace.snapshot` reports `complete` / `truncated` correctly

---

## Pass V — Deterministic retrieval

- [ ] `make test-deterministic-retrieval` passes
- [ ] `search.semantic` → `semantic_disabled` (4008) without `allowExperimental`
- [ ] `analysis.searchRanked` → `ranked_search_disabled` (4008)
- [ ] `tool.registry` / `tool.capabilities` list agent-safe methods
- [ ] `analysis.*` / `language.*` documented as internal (not in registry)

---

## Pass VI — Agent failure traps

- [ ] `make test-agent-workflow-smoke` passes (find/patch, stale recovery, batch rollback, deprecated recovery)
- [ ] `make test-cli-agent-failures` passes
- [ ] `make test-partial-success-closure` passes (batch/snapshot/diff enrichment)
- [ ] Partial success fields (`complete`, `partial`, `warnings`) on truncated reads
- [ ] Error envelopes include `nextRecommendedCommand`

---

## Pass VII — BroccoliQ runtime memory

- [ ] `make test-broccoliq-runtime-memory-fast` passes during iteration (assumes fresh server/binary; no rebuild)
- [ ] `make test-broccoliq-runtime-memory` passes before merge (full rebuild + restart)
- [ ] `runtime.diagnostics` reports `mutationAuthority: cpp_kernel` and `recordAuthority: runtime_journal`
- [ ] `operation.status` / `memory.operation.findByIdempotencyKey` resolve durable replay after mutation
- [ ] Docs: [BroccoliQ Runtime Memory](broccoliq-runtime-memory.md)

---

## Pass VIII — Native runtime integration

- [ ] `make test-runtime-native-integration-fast` passes during iteration
- [ ] `make test-runtime-native-integration` passes before merge
- [ ] `runtime.timeline` / `workspace.activity` return deterministic `timestamp_desc` ordering
- [ ] `runtime.correlate` joins operation + replay + timeline by `idempotencyKey`
- [ ] `runtime.diagnostics` exposes `startup.lastKnownRevision` and replay restoration counts
- [ ] Docs: [Runtime Native Integration](runtime-native-integration.md)

---

## Verification ladders

- [ ] `make verify-agent-runtime-fast` passes during iteration (no rebuild/restart)
- [ ] `make verify-agent-runtime` passes (14 checks, rebuilds + restarts once)
- [ ] `make verify-agent-runtime-full-fast` passes during iteration (full ladder, no rebuild/restart)
- [ ] `make verify-agent-runtime-full` passes (release ladder, includes full BroccoliQ memory verification; rebuilds + restarts once)
- [ ] `make release-check-agent-runtime` passes before release
- [ ] Release notes filled from [template](templates/runtime-release-notes.md) when contracts change
- [ ] Runtime limits in [Runtime Safety](runtime-safety.md)

---

## Pure C++ tests

- Text buffer initializes with one empty line.
- Text buffer splits lines predictably.
- Insert within a line.
- Insert multi-line text.
- Delete range within a line.
- Delete range across lines.
- Editor document dirty state.
- Save acknowledgement resets dirty state.
- Undo and redo.
- Find in file returns line/column matches.

---

## macOS manual tests

- App launches without opening a terminal or scanning folders.
- Welcome screen appears.
- New File opens editor.
- Typing updates dirty state.
- Save As writes a new file.
- Open File loads content.
- Save writes content.
- Window title shows unsaved indicator.
- Quitting with unsaved changes asks for confirmation.
- Canceling Save As leaves document open and dirty.
- File permission errors show a plain-language alert.

---

## Performance/trust checks

- No network on launch.
- No terminal process on launch.
- No recursive folder scan on launch.
- Idle CPU near zero.
- No hidden background job is started by the MVP.

---

## UX checks

- Primary actions are visible.
- Empty states explain what to do next.
- Menu items mirror visible actions.
- Beginner-facing labels avoid jargon.
- The user can tell whether their file is saved.
