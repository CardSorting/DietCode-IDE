#pragma once

#include <cstddef>

namespace dietcode::editor {

struct CursorPosition {
    std::size_t line{0};
    std::size_t column{0};

    constexpr bool operator==(const CursorPosition& other) const noexcept {
        return line == other.line && column == other.column;
    }

    constexpr bool operator!=(const CursorPosition& other) const noexcept {
        return !(*this == other);
    }

    constexpr bool operator<(const CursorPosition& other) const noexcept {
        return line < other.line || (line == other.line && column < other.column);
    }
};

class Cursor {
public:
    constexpr CursorPosition position() const noexcept { return position_; }
    constexpr void setPosition(CursorPosition position) noexcept { position_ = position; }

private:
    CursorPosition position_{};
};

} // namespace dietcode::editor
