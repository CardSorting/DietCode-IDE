#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace dietcode::lsp {

struct Diagnostic {
    int line; // 1-based
    int column; // 1-based
    std::string message;
    std::string severity; // "error", "warning", "info", "hint"
};

struct CompletionItem {
    std::string label;
    std::string detail;
    std::string insertText;
};

struct DefinitionLocation {
    std::string uri;
    std::string filePath;
    int line; // 1-based
    int column; // 1-based
};

struct DocumentSymbol {
    std::string name;
    std::string kind;
    int line{-1};      // 1-based
    int column{-1};    // 1-based
    int endLine{-1};   // 1-based, end of symbol range
    int endColumn{-1}; // 1-based, end of symbol range
};

class LSPClient {
public:
    LSPClient(const std::string& language, const std::string& serverPath, const std::string& workspacePath,
              std::function<void(const std::string& filePath, const std::vector<Diagnostic>&)> diagnosticCallback,
              std::function<void(const std::string&)> errorCallback);
    ~LSPClient();

    LSPClient(const LSPClient&) = delete;
    LSPClient& operator=(const LSPClient&) = delete;
    LSPClient(LSPClient&&) noexcept;
    LSPClient& operator=(LSPClient&&) noexcept;

    bool start();
    void stop();
    bool isRunning() const;

    // LSP Methods
    void didOpen(const std::string& filePath, const std::string& text);
    void didChange(const std::string& filePath, const std::string& text);
    void didClose(const std::string& filePath);
    void didSave(const std::string& filePath);
    
    std::vector<CompletionItem> getCompletions(const std::string& filePath, int line, int column);
    DefinitionLocation getDefinition(const std::string& filePath, int line, int column);
    std::vector<DocumentSymbol> getDocumentSymbols(const std::string& filePath);
    std::string getHover(const std::string& filePath, int line, int column);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace dietcode::lsp
