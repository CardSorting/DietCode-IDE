#pragma once

#include <string>

namespace dietcode::ui {

struct ErrorDialogCopy {
    std::string title;
    std::string whatHappened;
    std::string nextStep;
    std::string safety;
    std::string details;
};

} // namespace dietcode::ui
