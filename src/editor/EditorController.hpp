#pragma once

#include "EditorDocument.hpp"

#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace dietcode::editor {

class EditorController {
public:
    using DocumentId = std::size_t;

    DocumentId newDocument(std::string text = {}) {
        const DocumentId id = nextId_++;
        documents_.emplace(id, EditorDocument{std::move(text)});
        active_ = id;
        return id;
    }

    bool closeDocument(DocumentId id) {
        auto it = documents_.find(id);
        if (it == documents_.end()) {
            return false;
        }
        documents_.erase(it);
        if (active_ && *active_ == id) {
            active_ = documents_.empty() ? std::nullopt
                                          : std::optional<DocumentId>{documents_.begin()->first};
        }
        return true;
    }

    void setActive(DocumentId id) {
        if (documents_.count(id)) {
            active_ = id;
        }
    }

    [[nodiscard]] EditorDocument* activeDocument() noexcept {
        if (!active_) return nullptr;
        auto it = documents_.find(*active_);
        return it == documents_.end() ? nullptr : &it->second;
    }

    [[nodiscard]] const EditorDocument* activeDocument() const noexcept {
        if (!active_) return nullptr;
        auto it = documents_.find(*active_);
        return it == documents_.end() ? nullptr : &it->second;
    }

    [[nodiscard]] EditorDocument* documentById(DocumentId id) noexcept {
        auto it = documents_.find(id);
        return it == documents_.end() ? nullptr : &it->second;
    }

    [[nodiscard]] std::size_t documentCount() const noexcept { return documents_.size(); }
    [[nodiscard]] std::optional<DocumentId> activeId() const noexcept { return active_; }

private:
    std::unordered_map<DocumentId, EditorDocument> documents_;
    std::optional<DocumentId> active_;
    DocumentId nextId_{0};
};

} // namespace dietcode::editor
