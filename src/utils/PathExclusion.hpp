#pragma once

#include <filesystem>
#include <string>

namespace dietcode::utils {

inline bool isPathExcluded(const std::filesystem::path& path) {
    std::string name = path.filename().string();
    if (name == "node_modules" || name == ".git" || name == "dist" ||
        name == "build" || name == ".next" || name == "vendor" ||
        name == "__pycache__") {
        return true;
    }
    for (const auto& part : path) {
        std::string partStr = part.string();
        if (partStr == "node_modules" || partStr == ".git" || partStr == "dist" ||
            partStr == "build" || partStr == ".next" || partStr == "vendor" ||
            partStr == "__pycache__") {
            return true;
        }
    }
    return false;
}

} // namespace dietcode::utils
