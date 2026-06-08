# Getting Started Tutorial: Your First Contribution

This guide walks you through setting up the DietCode development environment, making a simple change to the UI, and verifying it with a test.

## 1. Environment Setup

### Prerequisites
- **macOS** (12.0 or later recommended).
- **Xcode Command Line Tools**: Run `xcode-select --install` in your terminal.
- **Python 3**: For running agent tests and integration scripts.

### Clone and Verify
```bash
git clone https://github.com/your-repo/DietCode-IDE.git
cd DietCode-IDE

# Run the core test suite
make test
```
*Expected output: `All DietCode editor tests passed.`*

---

## 2. Build and Launch

Compile the full macOS application bundle:
```bash
make app
```
The app will be generated at `build/DietCode.app`. You can launch it using:
```bash
make run
```

---

## 3. Hands-On: Modifying the Welcome Screen

Let's change the subtitle on the Welcome Screen to see how the UI layer works.

1. Open `src/platform/macos/ui/controllers/MacWindow.mm`.
2. Locate the `showWelcome:` method (around line 125).
3. Find the line:
   ```objectivec
   NSTextField* subtitle = MakeLabel(@"A quiet place to write and run code. Nothing runs unless you ask.", 17, NSFontWeightRegular);
   ```
4. Change the text to something new, like:
   ```objectivec
   NSTextField* subtitle = MakeLabel(@"DietCode: High-fidelity, agent-native, and lightning fast.", 17, NSFontWeightRegular);
   ```
5. Save the file and rebuild:
   ```bash
   make app && make run
   ```
6. Observe your change on the Welcome screen!

---

## 4. Hands-On: Adding a Core Test

Now let's add a unit test for the `TextBuffer` to ensure our core logic remains solid.

1. Open `tests/test_editor.cpp`.
2. Find the `testTextBufferBasics` function.
3. Add a new expectation at the end of the function:
   ```cpp
   buffer.setText("DietCode is great");
   expect(buffer.lineCount() == 1, "setText resets line count to 1");
   expect(buffer.line(0) == "DietCode is great", "setText correctly updates content");
   ```
4. Run the tests:
   ```bash
   make test
   ```

---

## 5. Experimenting with the Agent API

Interact with the headless control surface over the local Unix socket.

1. Build and start the server:
   ```bash
   make app
   make restart-agent-server    # use after any C++ control-server change
   make agent-ready
   ```

2. Preflight checks:
   ```bash
   make agent-status
   make agent-self-test         # offline parser checks (no socket)
   python3 scripts/dietcode_agent_client.py tool.capabilities --compact
   ```

3. Literal workspace search (agent-safe — no semantic layer):
   ```bash
   python3 scripts/dietcode_agent_client.py --grep CONTRACT --max-results 5 --compact
   python3 scripts/dietcode_agent_client.py --search-literal CONTRACT --max-results 5 --compact
   ```

4. Inspect open files and workspace root:
   ```bash
   python3 scripts/dietcode_agent_client.py --compact editor.getOpenFiles
   python3 scripts/dietcode_agent_client.py --compact workspace.getRoot
   ```

5. Run the verification ladder:
   ```bash
   make test-agent-offline
   make verify-agent-runtime
   ```

---

## Next Steps

- [Agent Integration Cookbook](agent-integration-cookbook.md) — find/patch workflows and stale-content recovery
- [Agent Runtime Audit](agent-runtime-audit.md) — what Passes I–VI implemented and why
- [Headless Agent Control](headless-agent-control.md) — full RPC reference and CLI flags
- [Technical Architecture](technical-architecture.md) — layers and transaction kernel
- [Build Instructions](build-instructions.md) — all Makefile targets and troubleshooting
