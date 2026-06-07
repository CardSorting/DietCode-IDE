# LSP Integration: Language Intelligence

DietCode implements a lightweight, high-performance LSP (Language Server Protocol) client in `src/core/LSPClient.mm`, enabling intelligent features like diagnostics, completions, and definition jumping while maintaining the "diet" philosophy.

## 🔌 Architecture

The LSP client is designed to be asynchronous and decoupled from the main UI thread.

### Process Management
- **Spawn-on-Demand:** Language servers (like `clangd`, `pyright`, or `tsserver`) are spawned as subprocesses only when a supported file type is opened.
- **Pipe-Based Communication:** Uses standard `stdin`/`stdout` pipes for bidirectional JSON-RPC communication.
- **Background Reader:** A dedicated `DietCodeLSPReader` thread performs non-blocking reads from the server's stdout, parsing the `Content-Length` header protocol.

### Supported Language Servers
DietCode looks for standard language server binaries in the user's `$PATH` or via explicit configuration:
- **C/C++**: `clangd`
- **Python**: `pyright` or `pylsp`
- **TypeScript/JS**: `tsserver` (via a specialized bridge)

---

## 🧠 Core Capabilities

### 1. Real-time Diagnostics
The client listens for `textDocument/publishDiagnostics` notifications. These are normalized into DietCode's internal diagnostic model and published to the `EventBus`, where they are picked up by the Editor and the Agent Control surface.

### 2. Intelligent Code Navigation
- **Go to Definition**: Implements `textDocument/definition`, resolving URI-based locations back to absolute workspace paths.
- **Hover**: Fetches documentation and type information via `textDocument/hover`.

### 3. Symbol Extraction
The client leverages `textDocument/documentSymbol` when available, providing high-fidelity outlines of classes, functions, and variables. (For files without a running LSP, DietCode falls back to its internal "Diet" symbol parser).

---

## ⚡ Performance Optimization

- **Throttle/Debounce**: `didChange` notifications are debounced to prevent flooding the language server during rapid typing.
- **Lazy Initialization**: The `initialize` handshake is performed only once per server lifetime.
- **Context Filtering**: Large JSON payloads are parsed using native `NSJSONSerialization` on macOS to ensure maximum parsing speed.
