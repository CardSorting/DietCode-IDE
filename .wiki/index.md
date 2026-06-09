# Sovereign Knowledge Ledger — DietCode

## Current verified state

DietCode is a **kernel/coherence-core archive**: headless `dietcode-kernel` with operational coherence enforcement across agent read, patch, approval, and verify surfaces.

Experimental cockpit, legacy AppKit UI, agent-bridge, and editor scaffold code were removed. See [ARCHIVE.md](../ARCHIVE.md) and [docs/archive-note.md](../docs/archive-note.md).

## Verified deliverables

- Coherence model docs in `docs/`
- Headless kernel: `src/kernel/`, `src/platform/macos/control/`
- Python RPC CLI and coherence harnesses in `scripts/`
- Frozen benchmark research under `benchmarks/agent_success/`

## Verified build state

```sh
make kernel
make coherence-core-v0.1
```

## Navigation

- [ARCHIVE.md](../ARCHIVE.md) — removed vs retained map
- `.wiki/changelog.md` — historical changes
- `.wiki/architecture.md` — layer map (includes historical editor notes)
- `.wiki/build-and-test.md` — current commands
- `.wiki/decisions.md` — product decisions
