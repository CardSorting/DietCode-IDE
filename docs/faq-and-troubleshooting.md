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
- **Fix:** Check if the socket exists: `ls -la ~/.dietcode/control.sock`. If not, run `make headless`.

### Q: I'm getting `permission_denied` for a simple file read.
**A:** DietCode enforces strict path security. You cannot read or write files outside of the currently opened workspace.
- **Fix:** Use `workspace.openFolder` to switch the active workspace to the directory containing your target files.

### Q: My patches are being rejected with `dirty_buffer_conflict`.
**A:** By default, DietCode protects you from overwriting unsaved user changes in the editor.
- **Fix:** Either call `editor.saveFile` before patching, or set `allowDirtyBuffer: true` in your RPC params if you are certain you want to patch the editor's memory directly.

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
