# Performance Budget

## Startup

- Cold start should feel immediate.
- No project scan on launch.
- No terminal process on launch.
- No network on launch.
- No extension host.
- No background language servers by default.

## Idle

- CPU should be near zero.
- No background indexing.
- No polling loops unless explicitly needed.
- File watchers are optional and lightweight.
- No hidden shell sessions.

## Memory

- Keep baseline memory small.
- Open files only as needed.
- Warn for huge files.
- Render visible editor region only once custom rendering exists.
- Do not allocate memory proportional to project size on folder open.

## Search

- Search only when user triggers it.
- Folder search must be cancelable.
- Exclude common heavy folders by default:
  - `node_modules`
  - `.git`
  - `dist`
  - `build`
  - `target`
  - `vendor`
  - `.next`
  - `.venv`
  - `__pycache__`

## Folder opening

- Do not recursively parse everything.
- Load the file tree lazily.
- Expand folders on demand.

## Feature audit

Before adding a feature, ask:

1. Does this run while idle?
2. Does this scan the whole folder?
3. Does this spawn a process?
4. Does this allocate memory proportional to project size?
5. Can the user cancel it?
6. Can it be lazy-loaded?
7. Can it be disabled?
8. Is it necessary for v1?
