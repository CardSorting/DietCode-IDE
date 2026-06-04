#pragma once

#include <cstddef>
#include <string>

namespace dietcode::editor {

struct EditorViewModel {
    std::string title{"Untitled"};
    bool dirty{false};
    std::size_t line{1};
    std::size_t column{1};
    std::string language{"Plain Text"};
};

} // namespace dietcode::editor
