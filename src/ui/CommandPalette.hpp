#pragma once

#include <string>

namespace dietcode::ui {

struct CommandPaletteState {
    bool visible{false};
    std::string query;
};

} // namespace dietcode::ui
