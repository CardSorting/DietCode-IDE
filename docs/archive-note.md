# Archive note

DietCode began as a governed mutation experiment with multiple product surfaces. The retained repository is the **kernel/coherence-core archive** — methodology, kernel binary, harnesses, tests, and documentation — not a shipping IDE or web app.

[ARCHIVE.md](../ARCHIVE.md) · [README.md](../README.md) · [testing.md](testing.md)

---

## What this archive preserves

| Artifact | Purpose |
|----------|---------|
| `dietcode-kernel` | Headless mutation authority |
| `src/platform/macos/control/` | JSON-RPC, coherence tokens, drift/approval/verify |
| `scripts/dietcode_agent_client.py` | Python RPC CLI |
| `scripts/dietcode_coherence.py` | Coherence recovery helpers |
| `scripts/test_coherence_tokens.py` | Live coherence enforcement tests |
| `scripts/coherence_recovery_smoke.py` | Recovery vertical slice |
| `scripts/fixtures/coherence_recovery/` | Recovery smoke fixtures |
| `docs/` | Coherence model + kernel reference |
| `make validate` | CI-equivalent health gate |

---

## Removed experimental surfaces

These proved the checkpoint model in realistic workflows. They are **not** in the active tree:

| Surface | Former role |
|---------|-------------|
| `cockpit/` | React UI + HTTP bridge for tasks, approvals, checkpoint visibility |
| `legacy_ui/` | AppKit editor shell |
| `agent-bridge/` | TypeScript client (`safePatchFile`, session recovery) |
| `integrations/` | Hermes plugin wiring |

Their removal does not invalidate the kernel proof. Coherence enforcement, drift layering, and recovery smoke run entirely through Python harnesses today.

---

## Removed editor scaffold (pass 4)

Pre-kernel IDE experiment code:

- `src/editor/`, `src/search/`, `src/syntax/`, `src/ui/`, `src/core/`, `src/utils/`
- `src/filesystem/FileWatcher.*`, `tests/test_editor.cpp`
- LSP client and file-watcher stubs

Kernel build links only control plane + workspace ops.

---

## Benchmarks archive

`benchmarks/agent_success/` retains frozen JSONL results and methodology. Live runners depended on `agent-bridge/`. See [../benchmarks/README.md](../benchmarks/README.md) and [../benchmarks/agent_success/ARCHIVE_NOTE.md](../benchmarks/agent_success/ARCHIVE_NOTE.md).

Benchmarks do **not** gate `coherence-core-v0.1`.

---

## Validation baseline

```bash
make validate
```

Or baseline only:

```bash
make coherence-core-v0.1
```

Tag when green: **coherence-core-v0.1**.

---

## Related

- [checkpoint-model.md](checkpoint-model.md)
- [coherence-tokens.md](coherence-tokens.md)
- [getting-started.md](getting-started.md)
