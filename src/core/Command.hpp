#pragma once

#include <functional>
#include <string>

namespace dietcode::core {

enum class CommandRisk {
    Low,
    Destructive,
    ProcessSpawning
};

struct Command {
    std::string id;
    std::string title;
    std::string description;
    std::string menuPath;
    std::string shortcut;
    CommandRisk risk{CommandRisk::Low};
    std::function<void()> execute;
};

} // namespace dietcode::core
