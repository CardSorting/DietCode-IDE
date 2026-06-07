# Build & Test System

DietCode is designed to be built and verified using only platform-native tools, avoiding the overhead of external package managers or heavy build frameworks.

## 🛠️ The Build System (`Makefile`)

The build process is orchestrated by a single, transparent `Makefile`.

### Primary Targets
- **`make app`**: Compiles the portable C++20 core and the Objective-C++ macOS shell, then bundles them into `build/DietCode.app`.
- **`make test`**: Compiles and executes the unit test suite and agent self-tests.
- **`make clean`**: Wipes the `build/` directory for a fresh start.

### Platform Flags
- **`CXXFLAGS`**: Enables C++20 and strict warning levels (`-Wall -Wextra -Wpedantic`).
- **`OBJCXXFLAGS`**: Enables Automatic Reference Counting (`-fobjc-arc`) for the macOS shell integration.

---

## 🧪 Testing Strategy

DietCode employs a **Zero-Dependency Testing** approach. Tests are designed to be fast, readable, and executable on any machine with a C++ compiler.

### Unit Tests (`tests/test_editor.cpp`)
- **Direct Logic Verification**: Tests the `TextBuffer`, `EditorDocument`, and search algorithms directly in C++.
- **Self-Contained**: Implements its own minimal `expect()` assertion logic to avoid linking against heavy test frameworks like GTest or Catch2.
- **Speed**: The entire suite runs in milliseconds, encouraging frequent execution during the development cycle.

### Integration & Agent Tests
- **`make agent-self-test`**: Verifies the Python agent client's configuration and connectivity.
- **`make control-smoke`**: Executes `scripts/control_smoke_test.py` to perform high-level integration checks between the agent client and a running (or headless) DietCode instance.

---

## 🤖 Headless CI Support

DietCode's build system is fully CI-compatible:
- **Exit Codes**: The test runner and agent client use standard Unix exit codes (0 for success, non-zero for failure).
- **Headless Mode**: The `--headless` flag allows DietCode to run without a window, enabling automated testing of the RPC surface in virtualized environments.
