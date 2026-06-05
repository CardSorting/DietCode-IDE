#pragma once

#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace dietcode::editor {

struct UndoEntry {
    std::string before;
    std::string after;
};

class UndoRedoStack {
public:
    static constexpr std::size_t kMaxUndoDepth = 500;

    void record(std::string before, std::string after) {
        if (before == after) {
            return;
        }
        if (undo_.size() >= kMaxUndoDepth) {
            undo_.erase(undo_.begin());
        }
        undo_.push_back(UndoEntry{std::move(before), std::move(after)});
        redo_.clear();
    }

    [[nodiscard]] bool canUndo() const noexcept { return !undo_.empty(); }
    [[nodiscard]] bool canRedo() const noexcept { return !redo_.empty(); }

    std::optional<UndoEntry> undo() {
        if (undo_.empty()) {
            return std::nullopt;
        }
        UndoEntry entry = std::move(undo_.back());
        undo_.pop_back();
        redo_.push_back(entry);
        return entry;
    }

    std::optional<UndoEntry> redo() {
        if (redo_.empty()) {
            return std::nullopt;
        }
        UndoEntry entry = std::move(redo_.back());
        redo_.pop_back();
        undo_.push_back(entry);
        return entry;
    }

    void clear() {
        undo_.clear();
        redo_.clear();
    }

private:
    std::vector<UndoEntry> undo_;
    std::vector<UndoEntry> redo_;
};

} // namespace dietcode::editor
