#pragma once

#include <filesystem>
#include <string>

namespace dietcode::filesystem {

inline std::string displayName(const std::filesystem::path& path) {
    if (path.filename().empty()) {
        return path.string();
    }
    return path.filename().string();
}

} // namespace dietcode::filesystem
