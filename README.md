<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode IDE</h1>

<p align="center">
  <strong>The High-Fidelity, Agent-Native Coding Workspace.</strong><br>
  <em>Native performance. Zero-latency. Transactable automation.</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg?style=for-the-badge" alt="Language">
  <img src="https://img.shields.io/badge/Agent--Native-Enabled-blue.svg?style=for-the-badge" alt="Agent-Native">
</p>

---

## 💎 The Thesis

**DietCode** is a native, lightweight IDE engineered for developers and autonomous agents who demand a high-performance, predictable, and local-first coding environment. It is the antithesis of modern, bloated editors, offering a "glass box" view of its internals and an ultra-high-fidelity control surface for the next generation of software engineering.

---

## ⚖️ Why DietCode?

| Feature | Electron-Based IDEs | DietCode IDE |
|---|---|---|
| **Memory Footprint** | 500MB - 2GB+ (Idle) | **~30MB - 80MB** (Typical) |
| **Startup Time** | 5s - 15s | **< 200ms** |
| **Background Noise** | High (Indexing, Telemetry, Daemons) | **Zero** (Pure on-demand execution) |
| **Agent Integration** | Plugin-based / Surface-level | **Native / Direct RPC over Unix Socket** |
| **Reliability** | "Surprise" compute spikes | **Deterministic resource allocation** |

---

## 🤖 Built for Agents: The Headless Control Surface

DietCode is designed from the ground up as an **Agent-First IDE**. It exposes its entire internal state via a high-performance JSON-RPC surface over a local Unix socket.

- **Transactional Safety:** Operations are executed as atomic **Chips**, composed into stateful, recoverable **Combos**.
- **Pre-image Recovery:** Automatic workspace restoration using pre-mutation snapshots.
- **Deep Visibility:** Direct access to the PTY terminal, symbol indices, and real-time event bus.
- **Budgetary Governance:** Hard limits on agent duration, file mutations, and verification cycles.

---

## ⚡ Technical Stack

<table align="center">
  <tr>
    <td align="center"><b>Core Engine</b><br>C++20</td>
    <td align="center"><b>Platform Shell</b><br>Obj-C++ / AppKit</td>
    <td align="center"><b>Control Surface</b><br>Unix Sockets / JSON-RPC</td>
  </tr>
  <tr>
    <td>Line-based text buffer, greedy regex tokenizer, async event bus.</td>
    <td>Native Cocoa windows, NSTextView rendering, PTY terminal integration.</td>
    <td>Multi-threaded RPC server with concurrent read/serial execution queues.</td>
  </tr>
</table>

---

## 🏗️ Architecture at a Glance

```text
      [ External Agents ]          [ Human Developer ]
              |                           |
      ( Unix Socket RPC )          ( Native Cocoa UI )
              |                           |
      v-------v---------------------------v-------v
      |            MacControlWindowBridge         |  <-- Main Thread Sync
      +-------------------------------------------+
      |      Domain Core (Portable C++20)         |
      | (Buffer, Search, Undo, LSP Client, Bus)   |
      +-------------------------------------------+
      |     Infrastructure (I/O, Git, PTY)        |
      v-------------------------------------------v
```

---

## 🚀 Quick Start

### 1. Build and Test
```bash
make test    # Verify the C++20 core
make app     # Compile the macOS .app bundle
```

### 2. Launch
```bash
make run     # Launch the interactive IDE
```

### 3. Agent Integration
```bash
make headless # Run as a headless control server
```

---

## 🗺️ Navigation & Documentation

The project is extensively documented for both human maintainers and autonomous agents.

- **[Documentation Index](docs/README.md)**: Your starting point for all technical specifications.
- **[Getting Started Tutorial](docs/getting-started-tutorial.md)**: Your first hands-on contribution.
- **[Expert-Tier Deep Dives](docs/README.md#🎓-expert-tier-deep-dives)**: Intimate implementation details.
- **[Visual Identity](docs/visual-identity.md)**: Brand guidelines and design language.
- **[Sovereign Knowledge Ledger](.wiki/index.md)**: Internal decision logs and project memory.

---

## 📄 License

DietCode is open-source software released under the [MIT License](LICENSE).

<p align="center">
  <em>Small tools are good tools. High-fidelity tools are better.</em>
</p>
