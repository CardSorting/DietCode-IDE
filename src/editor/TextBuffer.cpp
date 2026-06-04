#include "editor/TextBuffer.hpp"

#include <algorithm>
#include <stdexcept>

namespace dietcode::editor {

namespace {

std::vector<std::string> splitLines(std::string_view text) {
    std::vector<std::string> lines;
    std::string current;

    for (char ch : text) {
        if (ch == '\n') {
            if (!current.empty() && current.back() == '\r') {
                current.pop_back();
            }
            lines.push_back(current);
            current.clear();
        } else {
            current.push_back(ch);
        }
    }

    if (!current.empty() && current.back() == '\r') {
        current.pop_back();
    }
    lines.push_back(current);

    if (lines.empty()) {
        lines.push_back(std::string{});
    }

    return lines;
}

} // namespace

TextBuffer::TextBuffer() : lines_{std::string{}} {}

TextBuffer::TextBuffer(std::string_view text) : lines_(splitLines(text)) {}

TextBuffer TextBuffer::fromString(std::string_view text) {
    return TextBuffer{text};
}

std::size_t TextBuffer::lineCount() const noexcept {
    return lines_.size();
}

const std::string& TextBuffer::line(std::size_t index) const {
    if (index >= lines_.size()) {
        throw std::out_of_range("TextBuffer line index is out of range");
    }
    return lines_[index];
}

const std::vector<std::string>& TextBuffer::lines() const noexcept {
    return lines_;
}

std::string TextBuffer::toString() const {
    std::string output;
    for (std::size_t i = 0; i < lines_.size(); ++i) {
        output += lines_[i];
        if (i + 1 < lines_.size()) {
            output += '\n';
        }
    }
    return output;
}

CursorPosition TextBuffer::clamp(CursorPosition position) const noexcept {
    if (lines_.empty()) {
        return {};
    }

    const std::size_t lineIndex = std::min(position.line, lines_.size() - 1);
    const std::size_t columnIndex = std::min(position.column, lines_[lineIndex].size());
    return CursorPosition{lineIndex, columnIndex};
}

std::string TextBuffer::textInRange(TextRange range) const {
    const TextRange normalized = range.normalized();
    const CursorPosition start = clamp(normalized.start);
    const CursorPosition end = clamp(normalized.end);

    if (end < start || start == end) {
        return {};
    }

    if (start.line == end.line) {
        return lines_[start.line].substr(start.column, end.column - start.column);
    }

    std::string output = lines_[start.line].substr(start.column);
    output += '\n';

    for (std::size_t i = start.line + 1; i < end.line; ++i) {
        output += lines_[i];
        output += '\n';
    }

    output += lines_[end.line].substr(0, end.column);
    return output;
}

CursorPosition TextBuffer::insert(CursorPosition position, std::string_view text) {
    const CursorPosition safePosition = clamp(position);
    std::vector<std::string> insertedLines = splitLines(text);

    std::string& targetLine = lines_[safePosition.line];
    const std::string before = targetLine.substr(0, safePosition.column);
    const std::string after = targetLine.substr(safePosition.column);

    if (insertedLines.size() == 1) {
        targetLine = before + insertedLines.front() + after;
        return CursorPosition{safePosition.line, safePosition.column + insertedLines.front().size()};
    }

    insertedLines.front() = before + insertedLines.front();
    insertedLines.back() += after;

    lines_.erase(lines_.begin() + static_cast<std::ptrdiff_t>(safePosition.line));
    lines_.insert(lines_.begin() + static_cast<std::ptrdiff_t>(safePosition.line), insertedLines.begin(), insertedLines.end());

    return CursorPosition{safePosition.line + insertedLines.size() - 1, insertedLines.back().size() - after.size()};
}

void TextBuffer::erase(TextRange range) {
    const TextRange normalized = range.normalized();
    const CursorPosition start = clamp(normalized.start);
    const CursorPosition end = clamp(normalized.end);

    if (end < start || start == end) {
        return;
    }

    if (start.line == end.line) {
        lines_[start.line].erase(start.column, end.column - start.column);
        return;
    }

    const std::string merged = lines_[start.line].substr(0, start.column) + lines_[end.line].substr(end.column);
    lines_.erase(lines_.begin() + static_cast<std::ptrdiff_t>(start.line),
                 lines_.begin() + static_cast<std::ptrdiff_t>(end.line + 1));
    lines_.insert(lines_.begin() + static_cast<std::ptrdiff_t>(start.line), merged);

    if (lines_.empty()) {
        lines_.push_back(std::string{});
    }
}

void TextBuffer::replace(TextRange range, std::string_view text) {
    const TextRange normalized = range.normalized();
    erase(normalized);
    insert(normalized.start, text);
}

void TextBuffer::setText(std::string_view text) {
    lines_ = splitLines(text);
}

} // namespace dietcode::editor
