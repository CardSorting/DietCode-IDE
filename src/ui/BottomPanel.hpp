#pragma once

#include <string>

namespace dietcode::ui {

enum class BottomPanelTab {
    Output,
    Terminal,
    Errors,
    SearchResults
};

struct BottomPanelState {
    bool visible{false};
    BottomPanelTab active{BottomPanelTab::Output};
    std::string message;
};

} // namespace dietcode::ui
