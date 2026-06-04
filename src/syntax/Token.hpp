#pragma once

#include <cstddef>
#include <string>

namespace dietcode::syntax {

enum class TokenKind {
    Text,
    Keyword,
    String,
    Number,
    Comment,
    Operator
};

struct Token {
    TokenKind kind{TokenKind::Text};
    std::size_t start{0};
    std::size_t length{0};
};

} // namespace dietcode::syntax
