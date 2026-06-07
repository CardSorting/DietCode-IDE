# Symbol Indexing Strategy: The "Diet" Parser

DietCode uses a dual-mode symbol indexing strategy in `src/platform/macos/services/SymbolIndexService.mm`. It balances the need for high-speed navigation with the requirement for zero-bloat, avoiding the need for heavy external parsers for basic tasks.

## 🏃 Internal "Diet" Parsers

For many operations (and as a fallback when LSP is unavailable), DietCode uses high-speed internal parsers tailored for specific languages.

### 🐍 Python: Indentation-Based Extraction
The Python parser uses a combination of regex-matching for `class` and `def` keywords and **indentation-block analysis** to determine the scope of a symbol. This allows it to accurately identify symbol ranges without a full AST.

### ⚙️ C++/JS/TS: Brace-Counting Extraction
For curly-brace languages, DietCode uses a **Brace-Counting Scanner**. It identifies definition keywords and then tracks the nesting depth of `{ }` braces, while correctly ignoring braces inside strings or comments. This provides a highly accurate symbol map with negligible CPU overhead.

---

## 🔍 Situational Reference Scoring

When an agent or user searches for symbol references (`symbols.references`), DietCode uses a situational scoring algorithm to rank results:

- **Base Match**: Literal word-boundary match (Score: 1.0).
- **Open File Boost**: References in files currently open in editor tabs receive a `+0.5` boost, as they are likely more relevant to the current task.
- **Diagnostic Adjacency**: References in files with active compiler errors or warnings receive a `+0.3` boost, helping agents zero in on the cause of a failure.

---

## 🛡️ Scalability & Limits

To ensure "no jet engine" performance, the indexing service enforces strict limits:
- **Scan Depth**: Recursion is limited to 10 directory levels.
- **File Cap**: Workspace-wide scans stop at 10,000 files.
- **Size Limit**: Individual files larger than 2MB are skipped during indexing to prevent memory spikes.
- **Exclusion Policy**: Standard directories like `.git`, `node_modules`, `build`, and `__pycache__` are ignored by default.
