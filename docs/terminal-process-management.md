# Terminal & Process Management

DietCode provides a native interactive terminal panel and robust subprocess management, implemented in `src/platform/macos/`. It avoids the overhead of virtualized terminals, communicating directly with the host operating system's pseudo-terminal (PTY) interface.

## 📟 Native PTY Terminal

The integrated terminal panel in DietCode is not an emulation; it is a native macOS process connected to a PTY.

### Subprocess Spawning
- **`forkpty` Integration:** Uses the standard Unix `forkpty` call to spawn a shell (typically `/bin/zsh` or `/usr/bin/login`) with its own control terminal.
- **Master/Slave FDs:** The parent process (DietCode) communicates via the Master FD, while the shell process operates on the Slave FD.
- **Interactive Execution:** This setup allows for interactive CLI tools (like `vim`, `top`, or `ssh`) to run correctly with full TTY capabilities.

### Lifecycle Management
- **`SIGHUP` Termination:** When DietCode is closed or the terminal is stopped, a `SIGHUP` is sent to the PTY's process group to ensure clean termination of all child processes.
- **Scrollback Capture:** Terminal output is captured and buffered, allowing agents to read current terminal state via the `terminal.getOutput` RPC method.

---

## 🏃 Subprocess Runner (`SubprocessRunner.mm`)

For non-interactive background tasks (like builds, linting, or formatter runs), DietCode uses a dedicated `SubprocessRunner`.

- **`NSTask` Based:** Leverages the native `NSTask` (or `NSProcessInfo`) APIs for reliable process spawning.
- **Pipe Redirection:** Captures `stdout` and `stderr` asynchronously, publishing status and output to the IDE's UI and the Agent Control server.
- **Non-Blocking:** Task execution is entirely asynchronous, ensuring the main UI loop never stalls during a long build process.

---

## 🔒 Security & Sandboxing

- **Workspace Anchoring:** Subprocesses are by default anchored to the current workspace root (`cwd`).
- **Permission Elevation:** DietCode never asks for or grants elevated permissions (sudo) to subprocesses automatically.
- **Environment Scrubbing:** Critical system environment variables are preserved, while IDE-specific variables are injected for agent coordination.
