#pragma once

#include "Cursor.hpp"
#include "Selection.hpp"

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace dietcode::editor {

class TextBuffer {
public:
    TextBuffer();
    explicit TextBuffer(std::string_view text);

    static TextBuffer fromString(std::string_view text);

    [[nodiscard]] std::size_t lineCount() const noexcept;
    [[nodiscard]] const std::string& line(std::size_t index) const;
    [[nodiscard]] const std::vector<std::string>& lines() const noexcept;
    [[nodiscard]] std::string toString() const;

    [[nodiscard]] CursorPosition clamp(CursorPosition position) const noexcept;
    [[nodiscard]] std::string textInRange(TextRange range) const;

    CursorPosition insert(CursorPosition position, std::string_view text);
    void erase(TextRange range);
    void replace(TextRange range, std::string_view text);
    void setText(std::string_view text);

private:
    std::vector<std::string> lines_;
};

} // namespace dietcode::editor
