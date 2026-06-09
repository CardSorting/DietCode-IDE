# Testing and release gates

> **“Is my install healthy?”** → `make coherence-core-v0.1`

[← Doc index](README.md) · [getting-started](getting-started.md) · [troubleshooting](troubleshooting.md)

| I want to… | Command |
|------------|---------|
| Prove coherence baseline on my Mac | `make coherence-core-v0.1` |
| Run only coherence token tests | `make test-coherence-tokens` |
| Run only recovery smoke | `make coherence-recovery-smoke-fast` |
| Quick kernel smoke | `make agent-self-test` |
| Full agent-runtime ladder (broader) | `make verify-agent-runtime-full` |

---

## Primary gate: coherence core

```bash
make coherence-core-v0.1
```

| Step | What it proves |
|------|----------------|
| `make test-coherence-tokens` | Kernel coherence issuance + enforcement (`file.readBatch` included) |
| `make coherence-recovery-smoke-fast` | Deterministic Python recovery vertical |

Tag when green: **coherence-core-v0.1**. See [coherence-tokens.md](coherence-tokens.md).

## Coherence token tests

```bash
make test-coherence-tokens
```

Live kernel checks in `scripts/test_coherence_tokens.py`:

- `file.read` and `file.readBatch` issue coherence tokens when `taskId` is set
- Stale `expectedWorkspaceRevision` rejected with `coherence_mismatch`
- Missing token rejected on guarded patch paths

Fast iteration (assumes server already matches HEAD):

```bash
make test-coherence-tokens-fast
```

## Coherence recovery smoke

```bash
make coherence-recovery-smoke-fast
```

Fixtures under `scripts/fixtures/coherence_recovery/`:

| File | Role |
|------|------|
| `probe.py` | Mutable target for patch smoke |
| `verify.sh` | Post-mutation verification |

Orchestrator: `scripts/coherence_recovery_smoke.py` — proves stale patch blocked, context refreshed, safe retry, verify passes.

Full gate (rebuild + restart kernel first):

```bash
make coherence-recovery-smoke
```

## Docs drift

```bash
make test-docs-code-drift
```

Locks Makefile targets, error-code docs, tool contracts, coherence cross-doc alignment, and release-gate references.

## Kernel harness ladder (agent runtime)

These prove RPC contracts and tooling — run after kernel changes, separate from `coherence-core-v0.1`:

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

## Benchmark track (optional)

```bash
make benchmark-agent-success-fast   # may require archived bridge tooling
```

See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md). Parallel evaluation — does not gate coherence core.

## CI-style minimal loop

```bash
make kernel
make coherence-core-v0.1
make test-docs-code-drift
```

If that passes, the kernel coherence model is proven for the frozen baseline.

## Agent runtime release ladder

Historical RPC pass ladder (broader than coherence core):

```bash
make verify-agent-runtime-full
make release-check-agent-runtime
```

Contract inventory versions live in `scripts/release_versions.py` and the kernel `rpc.version` response.
