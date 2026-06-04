#pragma once

#include <string>
#include <unordered_map>

namespace dietcode::syntax {

struct Theme {
    std::string name{"DietCode System"};
    std::unordered_map<std::string, std::string> colors;
};

} // namespace dietcode::syntax
