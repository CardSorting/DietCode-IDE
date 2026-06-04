#pragma once

#include "../Clipboard.hpp"

namespace dietcode::platform::macos {

class MacClipboard final : public Clipboard {
public:
    void setText(const std::string& text) override;
    std::string text() const override;
};

} // namespace dietcode::platform::macos
