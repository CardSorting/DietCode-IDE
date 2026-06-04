#pragma once

#include <cstddef>
#include <string>

namespace dietcode::core {

enum class ThemeMode {
    System,
    Light,
    Dark,
    HighContrast
};

enum class LayoutDensity {
    Comfortable,
    Compact
};

struct Config {
    ThemeMode theme{ThemeMode::System};
    LayoutDensity density{LayoutDensity::Comfortable};
    std::string fontFamily{"Menlo"};
    double fontSize{14.0};
    std::size_t tabSize{4};
    bool softTabs{true};
    bool wordWrap{false};
    bool autoSave{false};
    bool beginnerMode{true};
    bool showBeginnerTips{true};
};

} // namespace dietcode::core
