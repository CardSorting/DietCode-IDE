#include "editor/EditorDocument.hpp"
#include "editor/TextBuffer.hpp"
#include "search/FindInFile.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

int failures = 0;

void expect(bool condition, const std::string& message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

void testTextBufferBasics() {
    dietcode::editor::TextBuffer buffer;
    expect(buffer.lineCount() == 1, "empty buffer has one line");
    expect(buffer.line(0).empty(), "empty buffer first line is empty");

    buffer.insert({0, 0}, "hello");
    expect(buffer.toString() == "hello", "insert text into empty buffer");

    buffer.insert({0, 5}, "\nworld");
    expect(buffer.lineCount() == 2, "multi-line insert creates second line");
    expect(buffer.toString() == "hello\nworld", "multi-line insert content");

    buffer.erase({{0, 2}, {1, 3}});
    expect(buffer.toString() == "held", "cross-line erase merges remaining text");
}

void testDocumentDirtyUndoRedo() {
    dietcode::editor::EditorDocument document{"one"};
    expect(!document.dirty(), "new loaded document starts clean");

    document.insert({0, 3}, " two");
    expect(document.text() == "one two", "document insert updates text");
    expect(document.dirty(), "document insert marks dirty");

    expect(document.undo(), "undo succeeds");
    expect(document.text() == "one", "undo restores previous text");

    expect(document.redo(), "redo succeeds");
    expect(document.text() == "one two", "redo restores next text");

    document.markSaved();
    expect(!document.dirty(), "markSaved clears dirty state");
}

void testFindInFile() {
    dietcode::editor::TextBuffer buffer{"Hello\nhello again\nquiet tools"};
    const auto results = dietcode::search::findInFile(buffer, "hello");
    expect(results.size() == 2, "case-insensitive find returns two matches");
    expect(results[0].line == 0 && results[0].column == 0, "first match location");
    expect(results[1].line == 1 && results[1].column == 0, "second match location");

    const auto sensitive = dietcode::search::findInFile(buffer, "hello", {.caseSensitive = true});
    expect(sensitive.size() == 1, "case-sensitive find returns one match");
}

} // namespace

int main() {
    testTextBufferBasics();
    testDocumentDirtyUndoRedo();
    testFindInFile();

    if (failures == 0) {
        std::cout << "All DietCode editor tests passed.\n";
        return EXIT_SUCCESS;
    }

    std::cerr << failures << " test expectation(s) failed.\n";
    return EXIT_FAILURE;
}
