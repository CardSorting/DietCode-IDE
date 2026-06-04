#pragma once

#include <string>
#include <vector>

namespace dietcode::syntax {

struct LanguageDefinition {
    std::string id{"plain-text"};
    std::string displayName{"Plain Text"};
    std::vector<std::string> extensions;
};

} // namespace dietcode::syntax
