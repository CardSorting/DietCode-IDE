#include "syntax/Tokenizer.hpp"
#include <regex>
#include <set>

namespace dietcode::syntax {

Tokenizer::Tokenizer(Language lang) : language_(lang) {}

std::vector<Token> Tokenizer::tokenizeLine(const std::string& line) const {
    if (line.empty()) {
        return {};
    }

    if (language_ == Language::PlainText) {
        return {Token{TokenKind::Text, 0, line.size()}};
    }

    std::vector<Token> tokens;
    
    // Simple state-less regex-based tokenizer for C++/Python
    static const std::set<std::string> cppKeywords = {
        "if", "else", "for", "while", "do", "return", "switch", "case", "default",
        "break", "continue", "int", "float", "double", "char", "void", "bool",
        "class", "struct", "namespace", "using", "public", "private", "protected",
        "static", "const", "virtual", "override", "template", "typename"
    };

    static const std::set<std::string> pyKeywords = {
        "if", "else", "elif", "for", "while", "def", "class", "return", "import",
        "from", "as", "try", "except", "finally", "with", "yield", "lambda", "not", "and", "or"
    };

    const std::set<std::string>& keywords = (language_ == Language::Cpp) ? cppKeywords : pyKeywords;

    std::regex wordRegex("[a-zA-Z_][a-zA-Z0-9_]*");
    std::regex numRegex("[0-9]+(\\.[0-9]*)?");
    std::regex stringRegex("\"[^\"]*\"|'[^']*'");
    std::regex commentRegex("//.*|#.*");

    std::size_t pos = 0;
    while (pos < line.size()) {
        std::smatch match;
        std::string suffix = line.substr(pos);

        if (std::regex_search(suffix, match, commentRegex, std::regex_constants::match_continuous)) {
            tokens.push_back({TokenKind::Comment, pos, static_cast<std::size_t>(match.length())});
            pos += match.length();
        } else if (std::regex_search(suffix, match, stringRegex, std::regex_constants::match_continuous)) {
            tokens.push_back({TokenKind::String, pos, static_cast<std::size_t>(match.length())});
            pos += match.length();
        } else if (std::regex_search(suffix, match, wordRegex, std::regex_constants::match_continuous)) {
            std::string word = match.str();
            TokenKind kind = keywords.count(word) ? TokenKind::Keyword : TokenKind::Text;
            tokens.push_back({kind, pos, static_cast<std::size_t>(match.length())});
            pos += match.length();
        } else if (std::regex_search(suffix, match, numRegex, std::regex_constants::match_continuous)) {
            tokens.push_back({TokenKind::Number, pos, static_cast<std::size_t>(match.length())});
            pos += match.length();
        } else if (isspace(line[pos])) {
            pos++;
        } else {
            tokens.push_back({TokenKind::Operator, pos, 1});
            pos++;
        }
    }

    return tokens;
}

} // namespace dietcode::syntax
