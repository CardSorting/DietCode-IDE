# Expert-Tier: Design Patterns & Governance

DietCode is built using modern C++20 and Objective-C++ patterns that ensure long-term maintainability and performance.

## 🏛️ The PIMPL Pattern (Pointer to Implementation)

Many core and platform classes (e.g., `LSPClient`, `FileWatcher`) use the **PIMPL pattern**.

### Rationale:
- **ABI Stability**: Changes to the private implementation don't require re-compiling the entire project.
- **Header Purity**: Keeps platform-specific headers (like `<Windows.h>` or `<Cocoa/Cocoa.h>`) out of the core C++ headers, preventing namespace pollution and reducing compile times.
- **Encapsulation**: Truly hides private members and helper methods from the public interface.

## 👁️ The Observer Pattern (Asynchronous)

The `EventBus` implements a decoupled Observer pattern.

- **Thread-Safe Dispatch**: Handlers are executed in a way that allows them to interact with the bus during their execution without causing deadlocks.
- **Weak References**: The macOS shell uses weak references in its event handlers to prevent retain cycles between the UI and the background orchestration layers.

## 🛠️ Transactional Command Pattern

Undo/Redo is implemented as a stack of command objects (`UndoEntry`).

- **Atomic Reversal**: Every entry contains enough metadata (`TextOperation`) to perfectly reverse its side-effects.
- **Grouping**: Multiple low-level edits (like a batch replace) are grouped into a single transactional entry, ensuring the user (or agent) can revert complex changes in one step.

---

## 🧠 Sovereign Knowledge Ledger

The `.wiki` directory is the project's **Sovereign Knowledge Ledger**. It is a foundational mandate that:

1. **Decisions are Logged**: Significant architectural choices must be recorded in `decisions.md`.
2. **State is Verified**: The `index.md` must reflect the current "verified" state of the codebase.
3. **Internal First**: Documentation in the `.wiki` is for the project's "permanent memory," while the `docs/` directory is for developer onboarding and integration.

## ⚖️ Coding Standards

- **C++20**: Prefer `std::string_view`, `std::optional`, and `std::span` for efficient data handling.
- **Obj-C++**: Use Automatic Reference Counting (ARC) and modern Objective-C syntax (literals, subscripting).
- **Naming**: Use `PascalCase` for classes, `camelCase` for methods/variables, and `kPascalCase` for constants.
