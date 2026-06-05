#pragma once

#include "Command.hpp"

#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace dietcode::core {

class CommandRegistry {
public:
    void registerCommand(Command command) {
        commands_[command.id] = std::move(command);
    }

    [[nodiscard]] const Command* find(const std::string& id) const {
        const auto it = commands_.find(id);
        return it == commands_.end() ? nullptr : &it->second;
    }

    bool execute(const std::string& id) const {
        const Command* command = find(id);
        if (!command || !command->execute) {
            return false;
        }
        try {
            return command->execute();
        } catch (...) {
            return false;
        }
    }

    [[nodiscard]] std::vector<Command> all() const {
        std::vector<Command> result;
        result.reserve(commands_.size());
        for (const auto& [_, command] : commands_) {
            result.push_back(command);
        }
        return result;
    }

private:
    std::unordered_map<std::string, Command> commands_;
};

} // namespace dietcode::core
