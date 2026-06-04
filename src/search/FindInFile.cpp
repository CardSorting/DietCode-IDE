#include "search/FindInFile.hpp"

#include <algorithm>
#include <cctype>

namespace dietcode::search {

namespace {

std::string lowerCopy(const std::string& value) {
    std::string lowered = value;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return lowered;
}

} // namespace

std::vector<SearchResult> findInFile(const editor::TextBuffer& buffer,
                                     const std::string& query,
                                     FindOptions options) {
    std::vector<SearchResult> results;
    if (query.empty()) {
        return results;
    }

    const std::string needle = options.caseSensitive ? query : lowerCopy(query);

    for (std::size_t lineIndex = 0; lineIndex < buffer.lineCount(); ++lineIndex) {
        const std::string& originalLine = buffer.line(lineIndex);
        const std::string haystack = options.caseSensitive ? originalLine : lowerCopy(originalLine);

        std::size_t offset = 0;
        while (true) {
            const std::size_t found = haystack.find(needle, offset);
            if (found == std::string::npos) {
                break;
            }

            results.push_back(SearchResult{lineIndex, found, query.size(), originalLine});
            offset = found + needle.size();
        }
    }

    return results;
}

} // namespace dietcode::search
