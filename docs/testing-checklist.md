# Testing Checklist

## Agent / RPC surface

- [ ] `make agent-self-test` passes (offline, no socket)
- [ ] `make agent-ready` → `make agent-status` reports `"ok":true`
- [ ] `make control-smoke` emits NDJSON summary with `"ok":true`
- [ ] `make agent-integration` passes smoke + ergonomics rollup
- [ ] `python3 scripts/dietcode_agent_client.py --emit-config --json` shows resolved paths
- [ ] Error envelopes use stable `string_code` (see [Error Codes](error-codes.md))
- [ ] `make test-agent-offline` passes (self-test + contract lockdown)
- [ ] `make verify-agent-runtime` passes (full ladder)
- [ ] Runtime contracts documented in [Runtime Contracts](runtime-contracts.md)
- [ ] `make test-operator-diagnostics` passes
- [ ] `python3 scripts/dietcode_agent_client.py --diagnose --json` shows socket/RPC readiness
- [ ] `make test-runtime-safety` passes
- [ ] `make test-grep-diff-tooling` passes (literal grep/diff/patch contracts)
- [ ] Grep/diff/patch contracts documented in [Agent Tooling](agent-tooling.md)
- [ ] `make test-runtime-determinism` passes (state hashes, stale-write rejection)
- [ ] `make test-transaction-kernel` passes (revision, batch atomicity, search parity)
- [ ] `make test-harness-realism` passes (symlink escape, transport, concurrency)
- [ ] `make test-deterministic-retrieval` passes (semantic quarantine, tool registry, literal/token search)
- [ ] `search.semantic` returns `semantic_disabled` (4008) without `allowExperimental`
- [ ] `tool.registry` / `tool.capabilities` list agent-safe deterministic methods
- [ ] `make test-agent-workflow-smoke` passes (find/patch, stale recovery, batch rollback, deprecated recovery)
- [ ] `make test-cli-agent-failures` passes (CLI bad JSON, deprecation, error-json envelopes)
- [ ] `make test-docs-code-drift` passes (docs match contracts and recovery hints)
- [ ] `make verify-agent-runtime-full` passes (full release ladder)
- [ ] `make test-partial-success-closure` passes (batch/snapshot/diff partial-success parity)
- [ ] `analysis.*` / `language.*` documented as internal (not in `tool.registry`)
- [ ] Partial success fields (`complete`, `partial`, `warnings`) present on truncated reads
- [ ] Error envelopes include `nextRecommendedCommand`
- [ ] Runtime invariants documented in [Runtime Invariants](runtime-invariants.md)
- [ ] Runtime limits documented in [Runtime Safety](runtime-safety.md)
- [ ] `make release-check-agent-runtime` passes before release
- [ ] Contract versions documented in [Runtime Contracts](runtime-contracts.md)
- [ ] Release notes filled from [template](templates/runtime-release-notes.md) when contracts change

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

## Performance/trust checks

- No network on launch.
- No terminal process on launch.
- No recursive folder scan on launch.
- Idle CPU near zero.
- No hidden background job is started by the MVP.

## UX checks

- Primary actions are visible.
- Empty states explain what to do next.
- Menu items mirror visible actions.
- Beginner-facing labels avoid jargon.
- The user can tell whether their file is saved.
