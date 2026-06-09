# Benchmarks (research archive)

The `benchmarks/` tree preserves adversarial evaluation artifacts from the DietCode agent-runtime reliability research program.

## Active repo baseline

The **active** DietCode repository is now a kernel/coherence-core archive. Release validation is:

```bash
make coherence-core-v0.1
```

Benchmarks do **not** gate `coherence-core-v0.1`.

## `agent_success/` — archived bridge dependency

The agent success benchmark under `benchmarks/agent_success/` was built against the removed TypeScript `agent-bridge` and live agent-chat integration surfaces. It remains as frozen research evidence (results JSONL, whitepapers, audit docs) but **Makefile targets were removed** in the kernel/coherence refactor. See [agent_success/ARCHIVE_NOTE.md](agent_success/ARCHIVE_NOTE.md).

| Status | Detail |
|--------|--------|
| Corpus + results | Preserved — see `agent_success/RESULTS*.md` |
| Live runner | Requires archived `agent-bridge/dist/cli/dietcode-agent-client.js` |
| Release gate | `release_check.py` — not wired to current Makefile |

To explore:

- [agent_success/README.md](agent_success/README.md) — methodology and frozen results
- [agent_success/WHITEPAPER.md](agent_success/WHITEPAPER.md) — evaluation instrument spec
- [../AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) — research program overview

## Restoring live benchmark runs

Live benchmark execution requires restoring `agent-bridge/` from git history and re-adding Makefile targets. That is intentionally out of scope for the coherence-core archive.

Offline unit tests under `benchmarks/agent_success/test_*.py` may still run without the bridge:

```bash
python3 benchmarks/agent_success/test_benchmark_schema.py
python3 benchmarks/agent_success/test_contracts.py
```

## Related

- [../docs/archive-note.md](../docs/archive-note.md) — removed product surfaces
- [../docs/testing.md](../docs/testing.md) — current validation ladder
