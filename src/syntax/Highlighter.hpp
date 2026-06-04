#pragma once

#include "Token.hpp"

#include <string>
#include <vector>

namespace dietcode::syntax {

struct HighlightSpan {
    Token token;
    std::string themeRole{"text"};
};

class Highlighter {
public:
    [[nodiscard]] std::vector<HighlightSpan> highlight(const std::vector<Token>& tokens) const {
        std::vector<HighlightSpan> spans;
        spans.reserve(tokens.size());
        for (const Token& token : tokens) {
            spans.push_back(HighlightSpan{token, "text"});
        }
        return spans;
    }
};

} // namespace dietcode::syntax
