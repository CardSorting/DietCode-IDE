#pragma once

#include <filesystem>
#include <utility>
#include <vector>

namespace dietcode::filesystem {

class RecentFiles {
public:
    void add(std::filesystem::path path) {
        entries_.push_back(std::move(path));
    }

    [[nodiscard]] const std::vector<std::filesystem::path>& entries() const noexcept {
        return entries_;
    }

private:
    std::vector<std::filesystem::path> entries_;
};

} // namespace dietcode::filesystem
