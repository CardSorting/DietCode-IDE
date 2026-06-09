# Build and Test Ledger

## Build system

Build file: `Makefile`

Primary targets:

- `make kernel` — builds `build/dietcode-kernel`
- `make test-coherence-tokens` — live coherence enforcement
- `make coherence-recovery-smoke-fast` — recovery vertical slice
- `make coherence-core-v0.1` — full coherence baseline gate
- `make validate` — baseline gate + docs drift (CI target)
- `make test-docs-code-drift` — docs ↔ contracts alignment
- `make test` — alias for `agent-self-test` (Python CLI smoke)
- `make clean` — removes `build/`

Removed targets: `make app`, `make run`, `make test` (C++ editor), `make cockpit`, `make agent-bridge-fast`.

## Verified commands

### Kernel build

```sh
make clean && make kernel
```

### Coherence baseline

```sh
make coherence-core-v0.1
```

### CI / full validate

```sh
make validate
```

GitHub Actions: `.github/workflows/coherence-core.yml` (macOS).

### Agent CLI smoke

```sh
make test
# equivalent: python3 scripts/dietcode_agent_client.py --self-test --compact
```

## Historical note

Editor C++ unit tests (`tests/test_editor.cpp`, `src/editor/`) were removed in the kernel/coherence archive refactor. The `.wiki/architecture.md` ledger still documents the former editor layers for historical reference.

## Broader harness ladder (optional)

```sh
make verify-agent-runtime-full
```

Broader than `coherence-core-v0.1`; exercises additional kernel RPC harnesses.
