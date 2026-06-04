#pragma once

#include "Cursor.hpp"
#include "Selection.hpp"
#include "TextBuffer.hpp"
#include "UndoRedo.hpp"

#include <optional>
#include <string>

namespace dietcode::editor {

class EditorDocument {
public:
    EditorDocument();
    explicit EditorDocument(std::string text);

    [[nodiscard]] const TextBuffer& buffer() const noexcept;
    [[nodiscard]] TextBuffer& buffer() noexcept;
    [[nodiscard]] std::string text() const;

    [[nodiscard]] bool dirty() const noexcept;
    [[nodiscard]] bool hasPath() const noexcept;
    [[nodiscard]] const std::optional<std::string>& path() const noexcept;

    void setPath(std::string path);
    void setText(std::string text);
    void replace(TextRange range, std::string text);
    CursorPosition insert(CursorPosition position, std::string text);
    void erase(TextRange range);

    bool undo();
    bool redo();
    void markSaved();

private:
    TextBuffer buffer_;
    UndoRedoStack history_;
    std::optional<std::string> path_;
    bool dirty_{false};
};

} // namespace dietcode::editor
