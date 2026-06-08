# FAQ & Troubleshooting

This guide addresses common hurdles encountered when developing, building, or integrating with DietCode.

---

## 🛠️ Build & Environment Issues

### Q: `make app` fails with "Cocoa/Cocoa.h not found".
**A:** You likely don't have the Xcode Command Line Tools correctly linked to the macOS SDK.
- **Fix:** Run `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` (or wherever your Xcode is installed).

### Q: The build is slow even though DietCode is "diet".
**A:** Ensure you aren't building inside a directory being heavily indexed by Spotlight or a cloud-sync service (like Dropbox/iCloud).
- **Fix:** Add the project directory to Spotlight exclusions in System Settings.

---

## 🤖 Agent & RPC Issues

### Q: `rpc.ping` returns `connection refused`.
**A:** The DietCode control server only starts if the app is launched normally or with `--headless` / `--ensure-socket`.
- **Fix:** Check if the socket exists: `ls -la ~/.dietcode/control.sock`. Then run `make agent-ready` or `build/DietCode.app/Contents/MacOS/DietCode --ensure-socket --ensure-timeout 10` to start or refresh the headless server.

### Q: The client says the socket exists but this process cannot connect to it.
**A:** The Python client now reports the real probe error. In managed sandboxes, a process may be able to see `~/.dietcode/control.sock` but still receive `permission_denied` when connecting.
- **Fix:** Run the harness with permission to access the DietCode Unix socket, or use an already approved command path such as `make agent-status` / `make agent-ready` when available.

### Q: `python3 scripts/test_v1_7_ergonomics.py` fails before RPC assertions.
**A:** If the failure includes `permission_denied`, the harness is blocked by the execution sandbox rather than by DietCode. If it reports `connection_refused`, the socket file is stale or no server is listening.
- **Fix:** For permission denial, run with socket access. For refused sockets, run `make agent-ready` to start a fresh headless server.

### Q: I'm getting `permission_denied` for a simple file read.
**A:** DietCode enforces strict path security. You cannot read or write files outside of the currently opened workspace.
- **Fix:** Use `workspace.openFolder` to switch the active workspace to the directory containing your target files.

### Q: Event subscriptions make later RPC calls return strange responses.
**A:** `event.subscribe` sends asynchronous frames on the subscribed socket. The bundled Python helper filters notification frames while waiting for the requested response id, but two independent readers sharing one socket can still consume each other's frames.
- **Fix:** Use `scripts/dietcode_agent_client.py` for request/response calls and use two control connections for long-running event listeners: one dedicated to `event.subscribe` and one for ordinary RPC calls.

### Q: Headless `workspace.openFile` or language methods do not open a visible editor.
**A:** In headless mode there is no initialized editor UI. `workspace.openFile` validates the file and updates recent-file state, while `language.hover`, `language.completions`, and `language.definition` return stable headless fallback results when UI-backed LSP state is unavailable.
- **Fix:** For UI navigation, run DietCode normally. For agent workflows, treat the `headless: true` response as a successful non-UI operation.

### Q: My patches are being rejected with `dirty_buffer_conflict`.
**A:** By default, DietCode protects you from overwriting unsaved user changes in the editor.
- **Fix:** Either call `editor.saveFile` before patching, or set `allowDirtyBuffer: true` in your RPC params if you are certain you want to patch the editor's memory directly.

### Q: `workspace.grep` returns zero matches in headless mode but ripgrep finds hits.
**A:** Earlier builds only searched open editor buffers. Current builds fall back to disk via `TextForSearchAtPath`.
- **Fix:** Rebuild and restart the server: `make app && make restart-agent-server`. Check `filesReadFromDisk` in the grep response. See [Agent Runtime Audit](agent-runtime-audit.md) Pass I.

### Q: `patch.apply` fails with `stale_content` (4004).
**A:** The file changed between `patch.validate` and `patch.apply`. The server checks `expectBeforeHash` before re-validation.
- **Fix:** Re-run `patch.validate` on the **current** file content, then apply with the fresh `beforeContentHash`. See [Error Codes](error-codes.md).

### Q: `search.semantic` returns `semantic_disabled` (4008).
**A:** Semantic search is quarantined on the deterministic agent surface (Pass V).
- **Fix:** Use `search.literal`, `search.tokens`, or `workspace.grep`. CLI: `--search-literal` instead of `--search-semantic`.

### Q: Live harnesses fail after I changed C++ control code but `make app` succeeded.
**A:** A stale headless server process may still be listening on the socket.
- **Fix:** `make restart-agent-server` then re-run the failing target (`make test-deterministic-retrieval`, `make verify-agent-runtime`, etc.).

### Q: Success response has `partial: true` or `complete: false` — did the RPC fail?
**A:** No — `ok: true` with partial success means the operation succeeded but results may be truncated or used disk fallback.
- **Fix:** Read `warnings` and call `nextRecommendedCommand` (e.g. paginate with `resultOffset`, or re-validate patch). See [Runtime Invariants](runtime-invariants.md).

### Q: Which RPC methods are safe for autonomous agents?
**A:** Query `tool.capabilities` for `agentSafeMethods`. `analysis.*` and `language.*` are internal — not in `tool.registry`.
- **Fix:** `python3 scripts/dietcode_agent_client.py tool.capabilities --compact`

---

## 📝 Editor & UI Issues

### Q: Syntax highlighting is missing for my language.
**A:** DietCode uses lightweight regex-based tokenizers. If your language isn't supported, it defaults to plain text.
- **Fix:** Check `src/syntax/Tokenizer.cpp` to see the currently supported extensions and feel free to contribute a new tokenizer!

### Q: The terminal isn't responding to input.
**A:** This can happen if the PTY process has crashed or hung.
- **Fix:** Click the "Refresh" icon in the Terminal panel or restart DietCode. Check for orphaned shell processes in Activity Monitor.

---

## 💡 Pro-Tips
- **Headless Development**: You can develop and test agents entirely in the terminal by running `make headless`. This avoids the overhead of the macOS window while keeping the RPC surface active.
- **Verbose Logging**: Launch DietCode with the `--verbose` flag to see detailed internal event and RPC traffic in your terminal.
