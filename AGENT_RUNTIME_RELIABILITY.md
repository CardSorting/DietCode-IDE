# DietCode Agent Runtime Reliability

Start here.

## Core claim

Bounded agent code mutation requires observable contracts, safe execution protocols, semantic repair discipline, and replayable mutation evidence.

## Run the release gate

```bash
make benchmark-contract-release-check
```

## Validate schemas

```bash
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
