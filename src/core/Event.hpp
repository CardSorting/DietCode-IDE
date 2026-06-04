#pragma once

#include <string>

namespace dietcode::core {

enum class EventType {
    DocumentOpened,
    DocumentSaved,
    DocumentChanged,
    ActivityChanged,
    SettingsChanged
};

struct Event {
    EventType type;
    std::string detail;
};

} // namespace dietcode::core
