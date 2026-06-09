<p align="center">
  <img src="resources/logo.svg" width="160" height="160" alt="DietCode logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>A kernel/coherence-core archive — local mutation authority with operational coherence enforcement for agent workflows.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/baseline-coherence--core--v0.1-blue.svg?style=flat-square" alt="coherence-core-v0.1">
</p>

<p align="center">
  <a href="#what-this-repository-is">What it is</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#coherence-model">Coherence</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#troubleshooting">Help</a>
</p>

---

## What this repository is

DietCode is a **frozen kernel/coherence-core archive** for macOS. It preserves a working methodology — not a shipping product — for governing agent-mediated code mutation through a single local authority.

| Layer | Role |
|-------|------|
| **Kernel** (`build/dietcode-kernel`) | Sole process that may change files; issues coherence tokens |
| **Control plane** (`src/platform/macos/control/`) | JSON-RPC server, drift/approval/verify gates |
| **Harnesses** (`scripts/`) | Python CLI, coherence tests, recovery smoke, contract lock |

```text
agent or script → dietcode_agent_client.py → dietcode-kernel → your project
```

**This is not** an IDE, web app, cockpit, or cloud agent platform. Experimental UI and TypeScript bridge surfaces were removed; the retained artifact is the kernel, coherence enforcement, tests, fixtures, and documentation that prove **coherence-core-v0.1**.

Strategy index: [ARCHIVE.md](ARCHIVE.md) · Doc index: [docs/README.md](docs/README.md)

---

## Coherence model

Operational coherence binds agent context to kernel revision **before** drift, approval, patch, and verify gates evaluate a mutation.

| Step | Kernel enforcement |
|------|-------------------|
| **Read** | `file.read` / `file.readBatch` with `taskId` issues a coherence token |
| **Patch** | `patch.apply` requires `coherenceTokenId` + `expectedWorkspaceRevision` |
| **Stale** | `coherence_mismatch` blocks the write; refresh context and retry |
| **Recovery** | `scripts/dietcode_coherence.py` + `coherence_recovery_smoke.py` prove the retry path |

Deep dive: [docs/coherence-tokens.md](docs/coherence-tokens.md) · [docs/workspace-drift.md](docs/workspace-drift.md) · [docs/checkpoint-model.md](docs/checkpoint-model.md)

---

## Quick start

**Prerequisites:** macOS, Xcode CLT (`clang++`, `make`), Python 3.11+ — [docs/getting-started.md](docs/getting-started.md)

### 1. Build and validate

```bash
git clone <repo>
cd DietCode-IDE
make validate
```

`make validate` builds the kernel (incremental object compile), runs **coherence-core-v0.1** (live coherence token tests + recovery smoke), then **test-docs-code-drift**. This is the CI target (`.github/workflows/coherence-core.yml`).

Tag when green: **coherence-core-v0.1**.

### 2. Start the kernel

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
```

Socket: `~/.dietcode/control.sock` · Token: `~/.dietcode/session.token`

### 3. Exercise RPC

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.openFolder \
  --params '{"path":"/path/to/your/project"}'
```

Full reference: [docs/kernel-rpc.md](docs/kernel-rpc.md)

---

## Core commands

| Command | What it does |
|---------|--------------|
| `make kernel` | Build `build/dietcode-kernel` (incremental; ~1s after first compile) |
| `make validate` | **Primary health check** — coherence baseline + docs drift |
| `make coherence-core-v0.1` | Live coherence tokens + recovery smoke only |
| `make test-coherence-tokens` | Coherence issuance/enforcement (rebuild + restart) |
| `make coherence-recovery-smoke-fast` | Recovery vertical slice (assumes server ready) |
| `make restart-agent-server-fast` | Restart kernel socket without rebuild |
| `make test-docs-code-drift` | Docs ↔ contracts ↔ Makefile alignment |

Full ladder: [docs/testing.md](docs/testing.md)

---

## Documentation

| Job | Start here |
|-----|------------|
| **Understand the archive strategy** | [ARCHIVE.md](ARCHIVE.md) · [docs/archive-note.md](docs/archive-note.md) |
| **Five-minute overview** | [docs/brief.md](docs/brief.md) |
| **Coherence model** | [docs/coherence-tokens.md](docs/coherence-tokens.md) |
| **Build and run** | [docs/getting-started.md](docs/getting-started.md) |
| **RPC reference** | [docs/kernel-rpc.md](docs/kernel-rpc.md) |
| **Validate / CI** | [docs/testing.md](docs/testing.md) |

Complete index: [docs/README.md](docs/README.md)

---

## Troubleshooting

| Symptom | First command |
|---------|---------------|
| Kernel offline | `make restart-agent-server-fast` |
| Stale binary after `git pull` | `make kernel && make restart-agent-server-fast` |
| Coherence blocks patch | Re-read with `taskId` — [docs/coherence-tokens.md](docs/coherence-tokens.md) |
| Install health unknown | `make validate` |

Playbook: [docs/troubleshooting.md](docs/troubleshooting.md) · Codes: [docs/error-codes.md](docs/error-codes.md)

---

## Repository layout

```text
src/kernel/                     Kernel entry + workspace session
src/platform/macos/control/     JSON-RPC, coherence tokens, gates
scripts/                        CLI, coherence harnesses, fixtures
docs/                           Coherence model + kernel reference
benchmarks/                     Frozen research (not gated)
```

Detail: [docs/file-structure.md](docs/file-structure.md)

---

## License

MIT — see [LICENSE](LICENSE).
