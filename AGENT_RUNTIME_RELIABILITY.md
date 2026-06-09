# DietCode Agent Runtime Reliability

Start here.

## Core claim

Bounded agent code mutation requires observable contracts, safe execution protocols, semantic repair discipline, and replayable mutation evidence.

## Kernel coherence trust loop

The retained kernel enforces a coherence-first mutation path:

| Layer | Invariant |
|-------|-----------|
| Coherence | Task-scoped reads issue tokens; stale writes return `coherence_mismatch` |
| Drift | Workspace changes block Edit/Destructive RPCs until refresh |
| Approval | Destructive mutations require explicit `approval.resolve` |
| Verification | `verify.run` must pass before harness marks completion |

```bash
make coherence-core-v0.1          # coherence tokens + recovery smoke
make verify-agent-runtime-full      # broader RPC release ladder
```

Details: [coherence-tokens.md](docs/coherence-tokens.md) · [kernel-rpc.md](docs/kernel-rpc.md)

## Benchmark track (archived bridge dependency)

The adversarial benchmark harness under `benchmarks/agent_success/` was built against the removed TypeScript agent-bridge. It remains as a research artifact; it does not gate `coherence-core-v0.1`.

```bash
# Requires archived agent-bridge tooling — may not run on current tree
make benchmark-contract-release-check
make test-agent-benchmark-schema
```

## Read the evidence

- [benchmarks/agent_success/WHITEPAPER.md](benchmarks/agent_success/WHITEPAPER.md)
- [benchmarks/agent_success/RESULTS.md](benchmarks/agent_success/RESULTS.md)
- [benchmarks/agent_success/NIGHTMARE_RESULTS.md](benchmarks/agent_success/NIGHTMARE_RESULTS.md)
- [benchmarks/agent_success/RESULTS_ORCHESTRATOR.md](benchmarks/agent_success/RESULTS_ORCHESTRATOR.md)
- [benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md](benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md)

## Release line

**v1.0** — research release (`agent-runtime-reliability-v1.0`). Frozen; do not extend in place.

Future benchmark work belongs on the **v1.1 experimental** line.
