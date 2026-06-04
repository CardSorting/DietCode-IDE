#pragma once

#include "EditorDocument.hpp"

#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace dietcode::editor {

class EditorController {
public:
    using DocumentId = std::size_t;

    DocumentId newDocument(std::string text = {}) {
        documents_.emplace_back(std::move(text));
        active_ = documents_.size() - 1;
        return active_.value();
    }

    [[nodiscard]] EditorDocument* activeDocument() noexcept {
        if (!active_ || *active_ >= documents_.size()) {
            return nullptr;
        }
        return &documents_[*active_];
    }

    [[nodiscard]] const EditorDocument* activeDocument() const noexcept {
        if (!active_ || *active_ >= documents_.size()) {
            return nullptr;
        }
        return &documents_[*active_];
    }

    [[nodiscard]] std::size_t documentCount() const noexcept { return documents_.size(); }

private:
    std::vector<EditorDocument> documents_;
    std::optional<DocumentId> active_;
};

} // namespace dietcode::editor
