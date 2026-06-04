#pragma once

#include <string>
#include <vector>
#include <functional>

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
    int line; // 1-based
    int column; // 1-based
};

class LSPClient {
public:
    LSPClient(const std::string& language, const std::string& serverPath, const std::string& workspacePath,
              std::function<void(const std::string& filePath, const std::vector<Diagnostic>&)> diagnosticCallback,
              std::function<void(const std::string&)> errorCallback);
    ~LSPClient();

    bool start();
    void stop();
    bool isRunning() const;

    // LSP Methods
    void didOpen(const std::string& filePath, const std::string& text);
    void didChange(const std::string& filePath, const std::string& text);
    void didSave(const std::string& filePath);
    
    std::vector<CompletionItem> getCompletions(const std::string& filePath, int line, int column);
    DefinitionLocation getDefinition(const std::string& filePath, int line, int column);
    std::vector<DocumentSymbol> getDocumentSymbols(const std::string& filePath);
    std::string getHover(const std::string& filePath, int line, int column);

private:
    class Impl;
    Impl* impl_;
};

} // namespace dietcode::lsp
