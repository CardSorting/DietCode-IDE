#pragma once

#include "Token.hpp"

#include <string>
#include <vector>

namespace dietcode::syntax {

enum class Language {
    PlainText,
    Cpp,
    Python
};

class Tokenizer {
public:
    explicit Tokenizer(Language lang = Language::PlainText);
    [[nodiscard]] std::vector<Token> tokenizeLine(const std::string& line) const;

private:
    Language language_;
};

} // namespace dietcode::syntax
