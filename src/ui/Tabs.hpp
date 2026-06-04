#pragma once

#include <string>
#include <vector>

namespace dietcode::ui {

struct TabState {
    std::string title;
    bool active{false};
    bool dirty{false};
};

struct TabsState {
    std::vector<TabState> tabs;
};

} // namespace dietcode::ui
