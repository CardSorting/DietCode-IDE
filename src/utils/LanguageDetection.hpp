#pragma once

#include <string>
#include <string_view>

namespace dietcode::utils {

inline std::string detectLanguage(std::string_view path) {
    size_t lastDot = path.find_last_of('.');
    if (lastDot == std::string_view::npos) {
        return "";
    }
    
    std::string_view ext = path.substr(lastDot + 1);
    
    // Convert to lowercase manually to keep it pure C++
    std::string lowerExt;
    lowerExt.reserve(ext.length());
    for (char c : ext) {
        lowerExt += (char)std::tolower((unsigned char)c);
    }
    
    if (lowerExt == "cpp" || lowerExt == "hpp" || lowerExt == "c" || 
        lowerExt == "h" || lowerExt == "cc" || lowerExt == "cxx") {
        return "cpp";
    }
    if (lowerExt == "py") {
        return "python";
    }
    if (lowerExt == "js" || lowerExt == "ts" || lowerExt == "jsx" || lowerExt == "tsx") {
        return "javascript";
    }
    if (lowerExt == "md") {
        return "markdown";
    }
    if (lowerExt == "sh" || lowerExt == "zsh") {
        return "shell";
    }
    
    return "";
}

} // namespace dietcode::utils
