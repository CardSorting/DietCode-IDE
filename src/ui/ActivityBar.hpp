#pragma once

#include <string>
#include <vector>

namespace dietcode::ui {

struct ActivityBarItem {
    std::string id;
    std::string label;
    bool active{false};
};

inline std::vector<ActivityBarItem> beginnerActivityItems() {
    return {
        {"files", "Files", true},
        {"search", "Search", false},
        {"run", "Run", false},
        {"errors", "Errors", false},
        {"settings", "Settings", false},
    };
}

} // namespace dietcode::ui
