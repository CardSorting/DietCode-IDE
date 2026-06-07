# Editor Internals: The Buffer & Document Engine

DietCode's core editing engine is implemented in pure C++20, residing in `src/editor/`. It prioritizes memory efficiency and predictable performance for large-file manipulation.

## 📄 The Text Buffer (`TextBuffer.hpp`)

Unlike traditional editors that use a single contiguous block (gap buffer) or complex piece tables, DietCode uses a **Line-Based Vector of Strings**.

### Why Line-Based?
- **O(1) Line Access:** Jumping to a specific line index is an array lookup.
- **Fast Local Edits:** Inserting a character only reallocates the memory for a single line, rather than the entire document.
- **Agent Compatibility:** Most code-editing operations (and diffs) are line-oriented. This structure maps 1-to-1 with unified diff hunks.

### Implementation Details
- **Storage:** `std::vector<std::string> lines_`.
- **Large File Strategy:** By splitting on newlines during the initial load, memory fragmentation is reduced compared to a single massive string.
- **Caching:** The buffer maintains a `cachedString_` with a dirty flag (`cacheValid_`). Full document serialization only occurs when `toString()` is requested (e.g., during a file save).

---

## ↩️ Undo & Redo Mechanics (`UndoRedo.hpp`)

DietCode uses a **Command-Based Transaction Stack** for its undo system.

### Transactional Integrity
- **Operations:** Every edit is recorded as a `TextOperation` (either `Insert` or `Erase`).
- **UndoEntry:** A single "Undo" step can contain multiple operations (e.g., a "Replace All" or a multi-line auto-format).
- **Depth:** The stack is capped at `kMaxUndoDepth = 500` steps to maintain a low memory footprint.

---

## 🎨 Syntax Tokenization (`src/syntax/`)

Syntax highlighting in DietCode is designed to be "diet"—avoiding the CPU tax of full AST parsing (like Tree-sitter) while remaining more accurate than simple regex.

- **Tokenizer:** A streaming character-by-character scanner that emits `Token` objects.
- **Incrementalism:** The system is designed to re-tokenize only the lines affected by a buffer edit.
- **Theme Engine:** Maps token types to platform-native attributes (NSAttributedString on macOS) using a lightweight theme definition.

---

## 🧵 Thread Safety & Concurrency

- **Immutable Snapshots:** The `TextBuffer` is not inherently thread-safe. Thread safety is managed at the `EditorDocument` and `MacControlServer` layers.
- **Locking:** Mutation operations (inserts/erases) acquire a document-level lock. Read operations (grep/search) can operate on immutable snapshots of the line vector.
