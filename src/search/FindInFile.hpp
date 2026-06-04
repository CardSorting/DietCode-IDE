#pragma once

#include "SearchResult.hpp"
#include "editor/TextBuffer.hpp"

#include <string>
#include <vector>

namespace dietcode::search {

struct FindOptions {
    bool caseSensitive{false};
};

std::vector<SearchResult> findInFile(const editor::TextBuffer& buffer,
                                     const std::string& query,
                                     FindOptions options = {});

} // namespace dietcode::search
