#pragma once

#include <string>
#include <string_view>
#include <cstdint>
#include <cstdio>

namespace dietcode::utils {

inline std::string stableMessageHash(std::string_view value) {
    uint64_t hash = 1469598103934665603ULL;
    for (unsigned char c : value) {
        hash ^= c;
        hash *= 1099511628211ULL;
    }
    char buffer[17];
    snprintf(buffer, sizeof(buffer), "%016llx", (unsigned long long)hash);
    return std::string(buffer);
}

inline std::string stableDiagnosticId(std::string_view source, 
                                      std::string_view path, 
                                      int line, 
                                      int column, 
                                      std::string_view message) {
    char buffer[64];
    snprintf(buffer, sizeof(buffer), ":%d:%d:", line, column);
    
    std::string result;
    result += source.empty() ? "unknown" : source;
    result += ":";
    result += path;
    result += buffer;
    result += stableMessageHash(message);
    return result;
}

} // namespace dietcode::utils
