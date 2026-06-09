# DietCode archive index

**Kernel/coherence-core repository** — methodology, kernel, harnesses, tests, and documentation for operational coherence enforcement. Not a shipping product.

---

## What this repo is

A local macOS experiment preserving **operational coherence** across agent read, diff, patch, approval, and verification — implemented as headless `dietcode-kernel` plus Python harnesses.

```text
agent → dietcode_agent_client.py → dietcode-kernel → workspace
```

---

## Validate the archive

```bash
make validate
```

| Step | Proves |
|------|--------|
| `coherence-core-v0.1` | Live coherence tokens + recovery smoke |
| `test-docs-code-drift` | Docs ↔ contracts ↔ Makefile |

Tag when green: **coherence-core-v0.1**

CI: `.github/workflows/coherence-core.yml` (macOS, `make validate`)

---

## Retained tree

| Path | Role |
|------|------|
| `src/kernel/` | Kernel entry, workspace session |
| `src/platform/macos/control/` | JSON-RPC, coherence tokens, gates |
| `src/platform/macos/services/` | Subprocess, diff/symbol analysis (RPC deps) |
| `src/filesystem/` | File + git services |
| `src/domain/control/` | Shared control-plane types |
| `scripts/dietcode_agent_client.py` | Python RPC CLI |
| `scripts/dietcode_coherence.py` | Coherence recovery helpers |
| `scripts/test_coherence_tokens.py` | Live coherence tests |
| `scripts/coherence_recovery_smoke.py` | Recovery vertical slice |
| `scripts/fixtures/coherence_recovery/` | Recovery fixtures |
| `docs/` | Coherence model + kernel reference |

---

## Removed

| Category | Paths |
|----------|-------|
| Product surfaces | `cockpit/`, `legacy_ui/`, `agent-bridge/`, `integrations/` |
| Editor scaffold | `src/editor/`, `src/search/`, `src/syntax/`, `src/ui/`, `src/core/`, `src/utils/` |
| App packaging | `DietCode.app`, `Info.plist`, agent-chat scripts |

Detail: [docs/archive-note.md](docs/archive-note.md)

---

## Research (not gated)

| Path | Status |
|------|--------|
| `benchmarks/agent_success/` | Frozen results; live runner needs restored `agent-bridge/` |
| `AGENT_RUNTIME_RELIABILITY.md` | Research program overview |

---

## Documentation entry points

| Doc | Purpose |
|-----|---------|
| [README.md](README.md) | Project overview |
| [docs/README.md](docs/README.md) | Full doc index |
| [docs/brief.md](docs/brief.md) | Five-minute companion |
| [docs/coherence-tokens.md](docs/coherence-tokens.md) | Coherence model |
| [docs/getting-started.md](docs/getting-started.md) | Build and run |
| [docs/testing.md](docs/testing.md) | Validation ladder |
