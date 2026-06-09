# Getting started

> **Goal:** Build the kernel, start the socket, and validate the coherence-core baseline.

[← Doc index](README.md) · [← README](../README.md#quick-start)

| Step | What you do | What you should see |
|------|-------------|---------------------|
| 1 | [Prerequisites](#prerequisites) | Tools installed |
| 2 | [Build the kernel](#1-build-the-kernel) | Socket at `~/.dietcode/control.sock` |
| 3 | [Open a workspace](#2-open-a-workspace) | Project bound to kernel session |
| 4 | [Validate coherence](#3-validate-coherence) | `coherence-core-v0.1` green |

---

## Prerequisites

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`clang++`, `make`)
- Python 3.11+ (harnesses, `dietcode_agent_client.py`)

---

## 1. Build the kernel

The kernel is the **only** component allowed to change files on disk.

```bash
make kernel
./build/dietcode-kernel --ensure-socket
```

| Path | Role |
|------|------|
| `~/.dietcode/control.sock` | Unix socket — how CLI and harnesses talk to the kernel |
| `~/.dietcode/session.token` | Auth token (mode `0600`) |

**Verify it is alive:**

```bash
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
```

You should get a successful ping response. If not, see [troubleshooting.md](troubleshooting.md#kernel-socket).

---

## 2. Open a workspace

Tell the kernel which project folder to govern:

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.openFolder \
  --params '{"path":"/path/to/your/project"}'
```

Or set `DIETCODE_REPO_ROOT` / `DIETCODE_WORKSPACE` for harness defaults.

---

## 3. Validate coherence

```bash
make coherence-core-v0.1
```

This runs:

1. `test-coherence-tokens` — live kernel coherence issuance and enforcement
2. `coherence-recovery-smoke-fast` — stale-patch block, refresh, retry, verify

Tag when green: **coherence-core-v0.1**.

Optional docs alignment check:

```bash
make test-docs-code-drift
```

---

## Restart after code changes

```bash
make kernel && make restart-agent-server-fast
```

Fast restart without rebuild (binary already matches HEAD):

```bash
make restart-agent-server-fast
```

---

## Next steps

| Task | Doc |
|------|-----|
| Understand coherence tokens | [coherence-tokens.md](coherence-tokens.md) |
| RPC method reference | [kernel-rpc.md](kernel-rpc.md) |
| Full test ladder | [testing.md](testing.md) |
| Removed UI surfaces | [archive-note.md](archive-note.md) |
