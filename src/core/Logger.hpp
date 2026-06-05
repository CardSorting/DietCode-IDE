#pragma once

#include <chrono>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace dietcode::core {

enum class LogLevel {
    Debug,
    Info,
    Warn,
    Error
};

struct LogEntry {
    LogLevel level;
    std::chrono::system_clock::time_point timestamp;
    std::string message;
};

class Logger {
public:
    static constexpr std::size_t kMaxEntries = 10000;

    void debug(std::string message) { log(LogLevel::Debug, std::move(message)); }
    void info(std::string message)  { log(LogLevel::Info, std::move(message)); }
    void warn(std::string message)  { log(LogLevel::Warn, std::move(message)); }
    void error(std::string message) { log(LogLevel::Error, std::move(message)); }

    void log(LogLevel level, std::string message) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (entries_.size() >= kMaxEntries) {
            entries_.erase(entries_.begin());
        }
        entries_.push_back(LogEntry{level, std::chrono::system_clock::now(), std::move(message)});
    }

    [[nodiscard]] std::vector<LogEntry> entries() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return entries_;
    }

    [[nodiscard]] std::size_t size() const noexcept {
        std::lock_guard<std::mutex> lock(mutex_);
        return entries_.size();
    }

private:
    mutable std::mutex mutex_;
    std::vector<LogEntry> entries_;
};

} // namespace dietcode::core
