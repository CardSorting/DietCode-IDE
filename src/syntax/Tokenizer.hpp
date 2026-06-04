#pragma once

#include "Token.hpp"

#include <string>
#include <vector>

namespace dietcode::syntax {

class Tokenizer {
public:
    [[nodiscard]] std::vector<Token> tokenizeLine(const std::string& line) const {
        if (line.empty()) {
            return {};
        }
        return {Token{TokenKind::Text, 0, line.size()}};
    }
};

} // namespace dietcode::syntax
