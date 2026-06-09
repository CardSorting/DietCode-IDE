# DietCode archive index

DietCode is a **kernel/coherence-core** repository. This file maps what was removed, what remains, and how to validate the retained artifact.

## What this repo is

A local macOS experiment for preserving **operational coherence** across agent read, diff, patch, approval, and verification surfaces — implemented as headless `dietcode-kernel` plus Python harnesses.

## Validate the retained baseline

```bash
make validate
```

(`validate` = `coherence-core-v0.1` + `test-docs-code-drift`; builds and restarts the kernel as needed.)

Tag when green: **coherence-core-v0.1**

## Retained tree

| Path | Role |
|------|------|
| `src/kernel/` | Kernel entry, workspace session |
| `src/platform/macos/control/` | JSON-RPC, coherence tokens, gates |
| `src/filesystem/` | File + git services used by kernel |
| `src/domain/control/` | Shared control-plane types |
| `scripts/dietcode_agent_client.py` | Python RPC CLI |
| `scripts/dietcode_coherence.py` | Coherence recovery helpers |
| `scripts/test_coherence_tokens.py` | Live coherence enforcement tests |
| `scripts/coherence_recovery_smoke.py` | Recovery vertical slice |
| `scripts/fixtures/coherence_recovery/` | Recovery smoke fixtures |
| `docs/` | Coherence model + kernel reference |

## Removed product surfaces

Documented in [docs/archive-note.md](docs/archive-note.md):

- `cockpit/` — React UI + HTTP bridge
- `legacy_ui/` — AppKit editor shell
- `agent-bridge/` — TypeScript client workflows
- `integrations/` — Hermes plugin wiring

## Removed editor scaffold (pass 4)

Pre-kernel IDE experiment code no longer compiled or tested:

- `src/editor/`, `src/search/`, `src/syntax/`, `src/ui/`, `src/core/`
- `src/utils/`, `src/filesystem/FileWatcher.*`
- `tests/test_editor.cpp`
- `resources/Info.plist`, agent-chat/Hermes packaging scripts

The kernel build no longer links LSP client or file-watcher stubs.

## Research artifacts (not gated)

| Path | Status |
|------|--------|
| `benchmarks/agent_success/` | Frozen results; live runner needs restored `agent-bridge/` |
| `AGENT_RUNTIME_RELIABILITY.md` | Research program overview |

See [benchmarks/README.md](benchmarks/README.md).

## Docs entry points

- [README.md](README.md) — project overview
- [docs/README.md](docs/README.md) — documentation index
- [docs/coherence-tokens.md](docs/coherence-tokens.md) — coherence model
- [docs/kernel-rpc.md](docs/kernel-rpc.md) — RPC reference
- [docs/testing.md](docs/testing.md) — validation ladder
