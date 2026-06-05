#pragma once

#include "SearchResult.hpp"

#include <atomic>
#include <filesystem>
#include <string>
#include <vector>

namespace dietcode::search {

struct WorkspaceSearchResult {
    std::filesystem::path path;
    std::vector<SearchResult> matches;
};

struct WorkspaceSearchOptions {
    bool caseSensitive{false};
    std::atomic<bool> cancelRequested{false};
};

} // namespace dietcode::search
