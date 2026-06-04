#pragma once

#include "../FileDialog.hpp"

namespace dietcode::platform::macos {

class MacFileDialog final : public FileDialog {
public:
    std::optional<std::filesystem::path> openFile() override;
    std::optional<std::filesystem::path> saveFile() override;
};

} // namespace dietcode::platform::macos
