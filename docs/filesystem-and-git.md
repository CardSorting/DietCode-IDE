# Filesystem & Git Integration

DietCode manages workspace state and version control through native platform services in `src/filesystem/`, ensuring high-performance I/O and accurate state tracking.

## 📁 Native File Watching (`FileWatcher.mm`)

DietCode maintains an accurate view of the workspace through native filesystem events.

- **FSEvents (macOS):** Uses the Apple `FSEvents` API for high-efficiency, recursive directory watching.
- **Batched Notifications:** Events are batched and debounced to prevent UI "flashing" during high-volume operations like `npm install` or a large build.
- **State Synchronization:** File changes (Created, Deleted, Renamed, Modified) are instantly synchronized with the sidebar file tree and open editor tabs.

---

## 🌳 Git Service (`GitService.mm`)

Version control is integrated as a first-class citizen, providing agents and users with structured access to repository state.

### Capabilities
- **Status Mapping:** Maps `git status` output into structured `GitChange` objects (staged, unstaged, untracked).
- **Staging Management:** Provides atomic methods for staging (`git add`) and unstaging (`git reset`) individual files.
- **Native Diffing:** Fetches raw diff text or structured hunks directly from the git index.
- **Commit Transactions:** Orchestrates commit operations with custom messages.

### Implementation
The Git Service executes git commands via the `SubprocessRunner`, parsing the output to avoid the overhead of heavy git libraries (like libgit2) while maintaining full feature compatibility with the user's installed `git` binary.

---

## 🛠️ Path Security & Utilities (`PathUtils.hpp`)

All filesystem operations are routed through a security-conscious utility layer:
- **Workspace Locking:** Prevents operations from escaping the workspace root (directory traversal protection).
- **UTF-8 Sanitization:** Ensures all paths are normalized and safe for cross-platform processing.
- **Existence Checks:** High-speed cache-backed file existence and metadata verification.
