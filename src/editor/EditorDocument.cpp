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
    const std::string before = buffer_.toString();
    buffer_.setText(text);
    history_.record(before, buffer_.toString());
    dirty_ = true;
}

void EditorDocument::replace(TextRange range, std::string text) {
    const std::string before = buffer_.toString();
    buffer_.replace(range, text);
    history_.record(before, buffer_.toString());
    dirty_ = true;
}

CursorPosition EditorDocument::insert(CursorPosition position, std::string text) {
    const std::string before = buffer_.toString();
    const CursorPosition next = buffer_.insert(position, text);
    history_.record(before, buffer_.toString());
    dirty_ = true;
    return next;
}

void EditorDocument::erase(TextRange range) {
    const std::string before = buffer_.toString();
    buffer_.erase(range);
    history_.record(before, buffer_.toString());
    dirty_ = true;
}

bool EditorDocument::undo() {
    auto entry = history_.undo();
    if (!entry) {
        return false;
    }
    buffer_.setText(entry->before);
    dirty_ = true;
    return true;
}

bool EditorDocument::redo() {
    auto entry = history_.redo();
    if (!entry) {
        return false;
    }
    buffer_.setText(entry->after);
    dirty_ = true;
    return true;
}

void EditorDocument::markSaved() {
    dirty_ = false;
}

} // namespace dietcode::editor
