# Expert-Tier: Tokenizer State Machine & Logic

DietCode's syntax highlighting engine (`src/syntax/Tokenizer.cpp`) is engineered for "extreme diet" performance. It prioritizes zero-latency editing over full semantic correctness.

## ⚡ The Streaming Regex Strategy

Unlike modern IDEs that use heavy, tree-based parsers (like Tree-sitter), DietCode uses a **Stateless Streaming Regex Scanner**.

### Why Regex?
- **O(N) Complexity**: Tokenization is strictly proportional to the length of the line.
- **Zero Memory Pressure**: No complex AST nodes are allocated or garbage collected.
- **Instant Incrementalism**: Since the tokenizer is stateless per line, editing line 1,000 never requires re-parsing lines 1-999.

## 🛠️ Implementation Breakdown

The `tokenizeLine` method implements a greedy matching loop:

1. **Pattern Ordering**: Patterns are tested in a strict priority order (Comments -> Strings -> Keywords -> Numbers -> Words).
2. **Continuous Matching**: Uses `std::regex_constants::match_continuous` to anchor matches at the current position, avoiding unnecessary lookaheads.
3. **Keyword Hashing**: Identifier matches are checked against a pre-compiled `std::set` of language-specific keywords for $O(\log N)$ lookup.

### Language Support
- **C/C++**: Optimized for preprocessor directives and standard keyword sets.
- **Python**: Tailored for hash-comments and Python-specific keywords.
- **Plain Text**: A passthrough mode that returns a single `Text` token for the entire line.

---

## 🚀 Extending the Tokenizer

Adding support for a new language is a high-signal task for contributors:

1. **Define the Keywords**: Add a new `std::set<std::string>` in `Tokenizer.cpp`.
2. **Register the Language**: Add the language to the `Language` enum in `Language.hpp`.
3. **Update the Loop**: Add a branch in `tokenizeLine` to use your new keyword set.

*Expert Tip: For languages with complex nesting (like HTML/XML), keep the regex simple. DietCode's philosophy is "visual comfort over perfect semantics."*
