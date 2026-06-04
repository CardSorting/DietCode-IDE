#pragma once

#include "Config.hpp"
#include "editor/EditorController.hpp"

#include <optional>
#include <string>

namespace dietcode::core {

enum class Activity {
    Files,
    Search,
    Run,
    Errors,
    Settings
};

struct AppState {
    Config config{};
    editor::EditorController editor{};
    Activity activity{Activity::Files};
    bool sidebarVisible{true};
    bool bottomPanelVisible{false};
    std::optional<std::string> openedFolder;
};

} // namespace dietcode::core
