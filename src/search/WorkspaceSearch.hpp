#pragma once

#include "SearchResult.hpp"

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
    bool cancelRequested{false};
};

} // namespace dietcode::search
