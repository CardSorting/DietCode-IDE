#pragma once

#include <string>
#include <vector>

namespace dietcode::ui {

struct WelcomeAction {
    std::string title;
    std::string description;
};

struct WelcomeScreenContent {
    std::string title{"Welcome to DietCode"};
    std::string subtitle{"A quiet place to write and run code. Nothing runs unless you ask."};
    std::vector<WelcomeAction> actions{
        {"Open File", "Edit an existing file."},
        {"New File", "Start with a blank file."},
        {"Open Folder", "See a folder of files on the left."},
    };
};

} // namespace dietcode::ui
