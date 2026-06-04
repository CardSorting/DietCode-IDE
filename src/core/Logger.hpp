#pragma once

#include <string>
#include <utility>
#include <vector>

namespace dietcode::core {

class Logger {
public:
    void info(std::string message) { entries_.push_back("info: " + std::move(message)); }
    void warn(std::string message) { entries_.push_back("warn: " + std::move(message)); }
    void error(std::string message) { entries_.push_back("error: " + std::move(message)); }

    [[nodiscard]] const std::vector<std::string>& entries() const noexcept { return entries_; }

private:
    std::vector<std::string> entries_;
};

} // namespace dietcode::core
