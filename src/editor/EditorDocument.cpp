#include "editor/EditorDocument.hpp"

#include <utility>

namespace dietcode::editor {

EditorDocument::EditorDocument() = default;

EditorDocument::EditorDocument(std::string text) : buffer_(text) {}

const TextBuffer& EditorDocument::buffer() const noexcept {
    return buffer_;
}

TextBuffer& EditorDocument::buffer() noexcept {
    return buffer_;
}

std::string EditorDocument::text() const {
    return buffer_.toString();
}

bool EditorDocument::dirty() const noexcept {
    return dirty_;
}

bool EditorDocument::hasPath() const noexcept {
    return path_.has_value();
}

const std::optional<std::string>& EditorDocument::path() const noexcept {
    return path_;
}

void EditorDocument::setPath(std::string path) {
    path_ = std::move(path);
}

void EditorDocument::setText(std::string text) {
    TextRange fullRange = { {0, 0}, {buffer_.lineCount() - 1, buffer_.line(buffer_.lineCount() - 1).size()} };
    std::string deleted = buffer_.erase(fullRange);
    TextRange newRange = buffer_.insert({0, 0}, text);
    
    UndoEntry entry;
    entry.operations.push_back({ TextOperation::Kind::Erase, fullRange, std::move(deleted) });
    entry.operations.push_back({ TextOperation::Kind::Insert, newRange, std::move(text) });
    history_.record(std::move(entry));
    dirty_ = true;
}

void EditorDocument::replace(TextRange range, std::string text) {
    const TextRange normalized = range.normalized();
    std::string deleted = buffer_.textInRange(normalized);
    buffer_.erase(normalized);
    TextRange newRange = buffer_.insert(normalized.start, text);
    
    UndoEntry entry;
    entry.operations.push_back({ TextOperation::Kind::Erase, normalized, std::move(deleted) });
    entry.operations.push_back({ TextOperation::Kind::Insert, newRange, std::move(text) });
    history_.record(std::move(entry));
    dirty_ = true;
}

CursorPosition EditorDocument::insert(CursorPosition position, std::string text) {
    TextRange newRange = buffer_.insert(position, text);
    
    UndoEntry entry;
    entry.operations.push_back({ TextOperation::Kind::Insert, newRange, text });
    history_.record(std::move(entry));
    dirty_ = true;
    return newRange.end;
}

void EditorDocument::erase(TextRange range) {
    const TextRange normalized = range.normalized();
    std::string deleted = buffer_.erase(normalized);
    
    UndoEntry entry;
    entry.operations.push_back({ TextOperation::Kind::Erase, normalized, std::move(deleted) });
    history_.record(std::move(entry));
    dirty_ = true;
}

bool EditorDocument::undo() {
    auto entry = history_.undo();
    if (!entry) {
        return false;
    }
    
    // Apply operations in reverse order, with inverse actions
    for (auto it = entry->operations.rbegin(); it != entry->operations.rend(); ++it) {
        if (it->kind == TextOperation::Kind::Insert) {
            buffer_.erase(it->range);
        } else {
            buffer_.insert(it->range.start, it->text);
        }
    }
    
    dirty_ = true;
    return true;
}

bool EditorDocument::redo() {
    auto entry = history_.redo();
    if (!entry) {
        return false;
    }
    
    // Apply operations in normal order
    for (const auto& op : entry->operations) {
        if (op.kind == TextOperation::Kind::Insert) {
            buffer_.insert(op.range.start, op.text);
        } else {
            buffer_.erase(op.range);
        }
    }
    
    dirty_ = true;
    return true;
}

void EditorDocument::markSaved() {
    dirty_ = false;
}

} // namespace dietcode::editor
