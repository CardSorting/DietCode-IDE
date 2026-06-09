# Testing and release gates

> **“Is my install healthy?”** → `make checkpoint-core`

[← Doc index](README.md) · [getting-started](getting-started.md) · [troubleshooting](troubleshooting.md)

| I want to… | Command |
|------------|---------|
| Prove full baseline on my Mac | `make checkpoint-core` |
| Run only the 53-check vertical slice | `make cockpit-smoke` |
| Quick kernel smoke | `make agent-self-test` |
| Full agent-runtime ladder (separate track) | `make verify-agent-runtime-full` |

---

## Primary gate: checkpoint core

```bash
make checkpoint-core
```

| Step | What it proves |
|------|----------------|
| `make kernel` | C++ kernel compiles |
| `agent-bridge-fast` | TypeScript bridge compiles |
| `make cockpit` | Cockpit + server types build |
| `make cockpit-smoke` | **53-check vertical slice** — full checkpoint loop |
| `test-checkpoint-core-unit` | Resolver + session + checkpoint unit tests |
| `test-docs-code-drift` | Docs ↔ contracts ↔ Makefile alignment |

Tag when green: `checkpoint-core-v0.1`.

## Vertical slice (`cockpit-smoke`)

```bash
make cockpit-smoke
```

Fixtures under `scripts/fixtures/cockpit_smoke/`:

| Fixture | Verify command |
|---------|----------------|
| `npm-test/` | `npm test` |
| `make-test/` | `make test` |
| `verify-sh/` | `./verify.sh` |

Per fixture the orchestrator asserts:

- Kernel and bridge up
- Task submitted via `POST /api/tasks` (`mode: smoke`)
- Drift checkpoint passes
- Approval appears and resolves
- Mutation applies; diff ring updates
- Verify command resolves; verify passes
- Task `completed` only after `verified`
- Session survives bridge reload

Orchestrator: `scripts/cockpit_vertical_slice.py`.

## Checkpoint unit tests

```bash
make test-checkpoint-core-unit
```

- `scripts/test_checkpoint_resolver.py` — verify command resolution parity
- `cockpit/server/checkpoints.test.ts` — gate semantics
- `cockpit/server/sessionStore.test.ts` — task IDs + diff ring

## Docs drift

```bash
make test-docs-code-drift
```

Locks Makefile targets, error-code docs, tool contracts, coherence cross-doc alignment, and release-gate references in [checkpoint-model.md](checkpoint-model.md).

## Coherence gate (`coherence-core-v0.1`)

```bash
make coherence-core-v0.1
```

| Step | What it proves |
|------|----------------|
| `test-coherence-tokens` | Kernel coherence issuance + enforcement (`file.readBatch` included) |
| `coherence-recovery-smoke-fast` | Deterministic Python recovery vertical |
| `hermes-coherence-recovery-smoke-fast` | Hermes bridge patch auto-retry |
| `cockpit-smoke` | Full checkpoint loop still passes with coherence layer |

Tag when green: **coherence-core-v0.1**. See [coherence-tokens.md](coherence-tokens.md).

## Kernel harness ladder (agent runtime)

These prove RPC contracts and tooling — run after kernel changes, separate from `checkpoint-core`:

| Target | Focus |
|--------|-------|
| `make agent-self-test` | CLI + socket smoke |
| `make control-smoke` | Control plane smoke |
| `make test-agent-workflow-smoke` | Patch workflows |
| `make test-agent-shell-tooling` | Bounded shell |
| `make test-agent-shell-workflows` | Shell workflow integration |
| `make test-authority-boundaries` | Journal vs live authority |
| `make verify-agent-runtime-full` | Full agent-runtime release ladder |

Restart kernel before live harnesses when C++ changed:

```bash
make restart-agent-server
```

## Agent bridge

```bash
make test-agent-bridge-fast      # offline unit tests
make test-agent-bridge-authority # authority workflows
```

## Hermes (optional)

```bash
make smoke-agent-chat-live       # bounded Hermes edit — not cockpit-smoke
make test-hermes-bridge-audit
```

Hermes paths are **not** part of `checkpoint-core`.

## Benchmark track (optional)

```bash
make benchmark-agent-success-fast
```

See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md). Parallel evaluation — does not gate checkpoint core.

## CI-style minimal loop

```bash
make checkpoint-core
```

If that passes, the governed mutation control loop is proven for the frozen baseline.

## Agent runtime release ladder

Historical RPC pass ladder (broader than checkpoint core):

```bash
make verify-agent-runtime-full
make release-check-agent-runtime
```

Contract inventory versions live in `scripts/release_versions.py` and the kernel `rpc.version` response.
