# State & Configuration Management

DietCode manages persistent user preferences and transient application state through a decoupled model in `src/core/Config.hpp` and `src/core/AppState.hpp`.

## ⚙️ User Configuration (`Config.hpp`)

The `Config` struct defines the user's IDE preferences.

### Core Settings
- **Theme**: Supports `Light`, `Dark`, and a high-fidelity `HighContrast` mode for accessibility.
- **Editor**: Controls font family, font size, tab behavior (soft tabs, size), and word wrap.
- **Onboarding**: Persistent flags for `beginnerMode` and `showBeginnerTips`.
- **Performance**: Toggle for `autoSave`, which triggers the internal recovery snapshotting system.

---

## 🏗️ Application State (`AppState.hpp`)

`AppState` acts as the single source of truth for the IDE's runtime condition.

- **Navigation**: Tracks the active `Activity` (Files, Search, Run, etc.) and sidebar/bottom panel visibility.
- **Workspace**: Stores the path to the currently `openedFolder`.
- **Editor Integration**: Holds the `EditorController`, which manages the collection of open `EditorDocument` objects and the multi-tab state.

---

## 💾 Persistence Layer

On macOS, state and configuration are synchronized between the C++ models and the host operating system:
- **`NSUserDefaults`**: Persistent settings (Font, Theme, Auto-Save) are stored in the standard macOS user defaults system.
- **Session Restoration**: On launch, DietCode reads from the recovery store and `NSUserDefaults` to restore the user's workspace, including open tabs and the last-used sidebar panel.
- **Manual Overrides**: Command-line flags (e.g., `--headless`, `--ensure-socket`) can override persistent configuration for specific sessions.
