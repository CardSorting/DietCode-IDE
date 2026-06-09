<p align="center">
  <img src="resources/logo.svg" width="160" height="160" alt="DietCode logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>A local kernel experiment for preserving operational coherence across agent read, diff, patch, approval, and verification surfaces.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/baseline-coherence--core--v0.1-blue.svg?style=flat-square" alt="coherence-core-v0.1">
</p>

<p align="center">
  <a href="#what-dietcode-is">What it is</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#coherence-model">Coherence</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#troubleshooting">Help</a>
</p>

---

## What DietCode is

DietCode is a **headless macOS kernel** (`dietcode-kernel`) that governs workspace mutation through JSON-RPC. One trusted process holds mutation authority; every agent read, patch, approval, and verify step must stay coherent with kernel-issued tokens and revision anchors.

| Layer | Role |
|-------|------|
| **Kernel** (`dietcode-kernel`) | Sole authority that changes files; issues coherence tokens |
| **Control plane** (`src/platform/macos/control/`) | JSON-RPC server, drift/approval/verify gates |
| **Harnesses** (`scripts/`) | Python CLI, coherence tests, recovery smoke |

```text
agent or script → dietcode_agent_client.py → dietcode-kernel → your project
```

**Not** an IDE, **not** a web UI, **not** cloud-hosted. The retained artifact is the kernel/coherence methodology and the tests that prove it.

Architecture detail: [architecture.md](docs/architecture.md) · Coherence: [coherence-tokens.md](docs/coherence-tokens.md)

---

## Coherence model

Operational coherence binds agent context to kernel state before drift, approval, patch, and verify gates run.

| Step | What the kernel enforces |
|------|--------------------------|
| **Read** | `file.read` / `file.readBatch` with `taskId` issues a coherence token |
| **Patch** | `patch.apply` must include `coherenceTokenId` + `expectedWorkspaceRevision` |
| **Mismatch** | `coherence_mismatch` blocks stale writes; refresh context and retry |
| **Recovery** | Deterministic re-read → safe retry path (see recovery smoke) |

Deep dive: [coherence-tokens.md](docs/coherence-tokens.md) · [workspace-drift.md](docs/workspace-drift.md) · [checkpoint-model.md](docs/checkpoint-model.md)

---

## Quick start

**Prerequisites:** macOS, Xcode CLT, Python 3.11+ — [getting-started.md](docs/getting-started.md)

### 1. Build and validate

```bash
git clone <repo>
cd DietCode-IDE
make kernel
make coherence-core-v0.1
```

Proves kernel coherence token issuance, enforcement, and recovery smoke on your machine. Tag: **coherence-core-v0.1**.

### 2. Start the kernel

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
```

Socket: `~/.dietcode/control.sock` · Token: `~/.dietcode/session.token`

### 3. Exercise RPC from Python

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.openFolder \
  --params '{"path":"/path/to/your/project"}'
```

Full RPC reference: [kernel-rpc.md](docs/kernel-rpc.md)

---

## Core commands

| Command | What it does |
|---------|--------------|
| `make kernel` | Build `build/dietcode-kernel` |
| `make test-coherence-tokens` | Live kernel coherence issuance + enforcement |
| `make coherence-recovery-smoke-fast` | Deterministic recovery vertical slice |
| `make coherence-core-v0.1` | Full coherence baseline gate |
| `make restart-agent-server-fast` | Restart kernel socket (no rebuild) |
| `make test-docs-code-drift` | Docs ↔ contracts ↔ Makefile alignment |

More: [testing.md](docs/testing.md)

---

## Documentation

| Job | Docs |
|-----|------|
| **Concept** | [brief](docs/brief.md) · [philosophy](docs/philosophy.md) · [checkpoint-model](docs/checkpoint-model.md) |
| **Coherence** | [coherence-tokens](docs/coherence-tokens.md) · [workspace-drift](docs/workspace-drift.md) · [session-recovery](docs/session-recovery.md) |
| **Run** | [getting-started](docs/getting-started.md) · [testing](docs/testing.md) · [troubleshooting](docs/troubleshooting.md) |
| **Build** | [kernel-rpc](docs/kernel-rpc.md) · [agent-tooling](docs/agent-tooling.md) · [file-structure](docs/file-structure.md) |

Index: [docs/README.md](docs/README.md) · Archive note: [docs/archive-note.md](docs/archive-note.md)

---

## Troubleshooting

| Symptom | First command |
|---------|---------------|
| Kernel offline | `make restart-agent-server-fast` |
| Stale binary after `git pull` | `make kernel && make restart-agent-server-fast` |
| Coherence blocks patch | Re-read with `taskId` — [coherence-tokens.md](docs/coherence-tokens.md) |
| Install health unknown | `make coherence-core-v0.1` |

Full playbook: [troubleshooting.md](docs/troubleshooting.md) · [error-codes.md](docs/error-codes.md)

---

## Repository layout

```text
src/kernel/                     Kernel entry
src/platform/macos/control/     JSON-RPC server + coherence tokens
scripts/                        CLI, coherence harnesses, fixtures
docs/                           Coherence model + kernel reference
```

[file-structure.md](docs/file-structure.md)

---

## License

MIT — see [LICENSE](LICENSE).
