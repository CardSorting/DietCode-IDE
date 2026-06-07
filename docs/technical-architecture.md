# Technical Architecture

DietCode is engineered with a strict decoupled architecture, separating a portable C++20 core from high-performance native shells and a robust agent-control surface.

## Layer Model

### 1. Domain / Editor Core (`src/editor/`, `src/search/`, `src/syntax/`)
- **Text Buffer:** Gap-buffer or piece-table based implementation for efficient large-file handling.
- **State Management:** Pure C++ implementation of cursors, selections, and a recursive undo/redo stack.
- **Search Engine:** High-speed literal substring scan and regex primitives.
- **Syntax Scaffolding:** Lightweight tokenization and language-detection logic.
- **Rules:** Zero platform dependencies. Testable in a headless environment.

### 2. Infrastructure & I/O (`src/filesystem/`, `src/platform/`)
- **File Service:** Thread-safe file I/O with change notification support.
- **Git Service:** Native integration for staging, diffing, and committing.
- **Path Utilities:** UTF-8 safe path manipulation and security validation.

### 3. macOS Platform Shell (`src/platform/macos/`)
The macOS implementation is the primary high-fidelity reference for the DietCode architecture.

#### Native UI (`ui/`)
- **AppKit Shell:** Uses `NSWindowController` and `NSView` for zero-latency rendering and standard macOS behavior.
- **Terminal Panel:** Native PTY (Pseudo-Terminal) implementation with interactive execution support.
- **Layout Engine:** Nested `NSSplitView` architecture for the sidebar, editor, and bottom panels.

#### Control & Agent Surface (`control/`)
- **MacControlServer:** A dedicated Unix socket listener running a JSON-RPC 2.0 protocol.
- **Chip/Combo Runtime:** A deterministic execution engine for atomic operations (Chips) and complex transactions (Combos).
- **Security & Routing:** Strict permission-based routing policy and path-security verification.

#### Platform Services (`services/`)
- **SymbolIndexService:** High-speed, on-demand symbol extraction and indexing.
- **WorkspaceAnalysisService:** Real-time linguistic and statistical analysis of the opened directory.
- **DiffAnalysisService:** Structured hunk analysis for agentic patching and conflict detection.

### 4. Application Orchestration (`src/core/`)
- **Command Registry:** Centralized dispatch for IDE actions.
- **Event Bus:** Duplex notification system for document and session events.

## Native Vertical Slice Strategy

The initial implementation uses `NSTextView` for the editor surface to provide immediate accessibility, IME, and high-quality text rendering. The pure C++ editor primitives in `src/editor/` are designed to eventually drive a custom CoreText-based renderer, but the "Diet" philosophy prioritizes stable product loops (Launch -> Edit -> Save) over early custom rendering complexity.

## Threading & Performance

- **Main Thread:** Reserved for UI rendering and standard event processing.
- **Control Thread:** Handles RPC requests from the Unix socket to ensure the UI remains responsive during large-scale agent operations.
- **Worker Pool:** Used for background search, symbol indexing, and diff generation.
