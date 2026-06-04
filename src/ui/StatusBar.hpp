#pragma once

#include <cstddef>
#include <string>

namespace dietcode::ui {

struct StatusBarState {
    std::string fileName{"No file open"};
    std::string savedState{"Saved"};
    std::string language{"Plain Text"};
    std::size_t line{1};
    std::size_t column{1};
};

} // namespace dietcode::ui
