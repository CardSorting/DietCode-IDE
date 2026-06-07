# Event Orchestration: The Async Event Bus

DietCode uses a thread-safe, asynchronous **Event Bus** in `src/core/Event.hpp` to decouple core logic from the platform-native UI and the agent control surface.

## 📡 Pub/Sub Architecture

The `EventBus` implements a classic Publish/Subscribe pattern, allowing different parts of the system to communicate without direct dependencies.

### Core Event Types
- `DocumentOpened` / `DocumentClosed`: Emitted when editor tabs are managed.
- `DocumentSaved`: Triggered after successful filesystem write.
- `DocumentChanged`: Emitted on every buffer edit (debounced for observers).
- `ActivityChanged`: Emitted when the user switches between sidebar panels (Files, Search, etc.).
- `SettingsChanged`: Triggered when user preferences (Theme, Font) are modified.

### Thread Safety
- **Locking:** Uses `std::mutex` and `std::lock_guard` to protect the handler registry.
- **Snapshot Execution:** When an event is emitted, the bus takes a local snapshot of the handlers before executing them. This prevents deadlocks if a handler attempts to unsubscribe itself or emit a new event during execution.

---

## 🔗 Observer Integration

The Event Bus is the primary driver for high-level IDE behavior:
1. **The Editor**: Listens for `DocumentChanged` to update the dirty indicator and trigger incremental re-tokenization.
2. **The Status Bar**: Subscribes to `ActivityChanged` and cursor movement events to update the line/column display.
3. **Agent Control**: Uses the bus to push real-time notifications to external subscribers over the Unix socket.
4. **Auto-Recovery**: Monitors `DocumentChanged` to determine when to take periodic snapshots of the buffer state.
