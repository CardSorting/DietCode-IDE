#pragma once

#include "Cursor.hpp"

namespace dietcode::editor {

struct TextRange {
    CursorPosition start{};
    CursorPosition end{};

    constexpr bool empty() const noexcept {
        return start == end;
    }

    constexpr TextRange normalized() const noexcept {
        return end < start ? TextRange{end, start} : *this;
    }
};

class Selection {
public:
    constexpr bool hasSelection() const noexcept { return !range_.empty(); }
    constexpr TextRange range() const noexcept { return range_; }
    constexpr void setRange(TextRange range) noexcept { range_ = range.normalized(); }
    constexpr void clear(CursorPosition position) noexcept { range_ = TextRange{position, position}; }

private:
    TextRange range_{};
};

} // namespace dietcode::editor
