#pragma once

#include <cstddef>
#include <string>

namespace dietcode::search {

struct SearchResult {
    std::size_t line{0};
    std::size_t column{0};
    std::size_t length{0};
    std::string lineText;
};

} // namespace dietcode::search
