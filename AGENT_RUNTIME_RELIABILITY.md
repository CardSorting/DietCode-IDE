# DietCode Agent Runtime Reliability

Start here.

## Core claim

Bounded agent code mutation requires observable contracts, safe execution protocols, semantic repair discipline, and replayable mutation evidence.

## Agent Chat trust loop (installed app)

The native Agent Chat sidebar (`dietcode-agent-chat`) adds a four-layer authority chain on every run:

| Layer | Invariant |
|-------|-----------|
| Workspace authority | Requested workspace == observed runtime workspace |
| Mutation authority | Changed files explained by bridge patch telemetry |
| Diff authority | Visible diff changed set == mutation reported files |
| Verification authority | Executable verify passes after final mutation |

```bash
make smoke-agent-chat-live          # live proof of all four layers
make verify-hermes-bridge           # integration ladder
make verify-agent-runtime-full      # full release ladder
```

Details: [Agent Chat Sidebar](docs/agent-chat-sidebar.md).

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
