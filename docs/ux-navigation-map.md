# UX and Navigation Map

## Navigation intent

DietCode uses a familiar IDE layout so a non-technical user can understand the app within 30 seconds without reading documentation.

## Top-level layout

```text
Native menu bar
┌─────────────────────────────────────────────────────────────┐
│ File Edit Selection View Go Run Terminal Help               │
├─────────────┬─────────────────────┬─────────────────────────┤
│ Activity    │ Sidebar             │ Editor area             │
│ bar         │                     │                         │
│             │ Files/Search/Run/   │ Welcome, tabs, editor   │
│ Files       │ Errors/Settings     │                         │
│ Search      │                     │                         │
│ Run         │                     │                         │
│ Errors      │                     │                         │
│ Settings    │                     │                         │
├─────────────┴─────────────────────┴─────────────────────────┤
│ Bottom panel: Output / Terminal / Errors / Search Results    │
├─────────────────────────────────────────────────────────────┤
│ Status bar: file, saved state, language, line/column, folder │
└─────────────────────────────────────────────────────────────┘
```

## Beginner-facing language

| Technical term | Beginner label |
|---|---|
| Explorer | Files |
| Problems | Errors |
| Workspace | Folder |
| Task | Run command |
| Output channel | Output |
| Preferences | Settings |
| Terminal session | Terminal |
| Diagnostics | Details |

## Main navigation areas

### Menu bar

- File
- Edit
- Selection
- View
- Go
- Run
- Terminal
- Help

Menus provide visible equivalents for keyboard shortcuts and command palette entries.

### Activity bar

Beginner Mode shows labels by default:

- Files
- Search
- Run
- Errors
- Settings

Developer Mode may use compact icon-first navigation, but labels/tooltips remain available.

### Sidebar

The sidebar changes with the selected activity.

- Files: open folder, folder tree, file actions.
- Search: find in file and later search folder.
- Run: current file run action and later run profiles.
- Errors: friendly problem summaries and raw details.
- Settings: visual settings first, advanced settings later.

### Editor area

- Welcome screen when no file is open.
- Tabs when files are open.
- Text editor view.
- Split editor is later-phase only.

### Bottom panel

Closed by default in early phases. Opens only by user action or when a requested action produces output/errors.

- Output
- Terminal
- Errors
- Search Results

### Status bar

Beginner Mode status bar is simple:

- Current file name.
- Saved or unsaved state.
- Line/column.
- Language mode.

Developer Mode may add encoding, indentation, current folder, and run status.

## First-launch welcome screen

Title: **Welcome to DietCode**

Subtitle: **A quiet place to write and run code. Nothing runs unless you ask.**

Primary actions:

- Open File — Edit an existing file.
- New File — Start with a blank file.
- Open Folder — See a folder of files on the left.

Secondary actions:

- Learn DietCode Basics.
- Settings.
- Open Recent, once available.

## Navigation audit questions

Every screen must answer:

1. Where am I?
2. What is selected?
3. What can I do next?
4. Is my work safe?
5. Can I recover from a mistake?
6. Is there both a visible path and a keyboard/menu path?
