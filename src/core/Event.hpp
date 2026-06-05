#pragma once

#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace dietcode::core {

enum class EventType {
    DocumentOpened,
    DocumentClosed,
    DocumentSaved,
    DocumentChanged,
    ActivityChanged,
    SettingsChanged
};

struct Event {
    EventType type;
    std::string detail;
};

using EventHandler = std::function<void(const Event&)>;

class EventBus {
public:
    using SubscriptionId = std::size_t;

    SubscriptionId subscribe(EventType type, EventHandler handler) {
        std::lock_guard<std::mutex> lock(mutex_);
        const SubscriptionId id = nextId_++;
        handlers_[type].push_back({id, std::move(handler)});
        return id;
    }

    void unsubscribe(SubscriptionId id) {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& [type, entries] : handlers_) {
            entries.erase(
                std::remove_if(entries.begin(), entries.end(),
                    [id](const Entry& e) { return e.id == id; }),
                entries.end());
        }
    }

    void emit(const Event& event) {
        std::vector<EventHandler> snapshot;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = handlers_.find(event.type);
            if (it != handlers_.end()) {
                snapshot.reserve(it->second.size());
                for (const auto& entry : it->second) {
                    snapshot.push_back(entry.handler);
                }
            }
        }
        for (const auto& handler : snapshot) {
            handler(event);
        }
    }

private:
    struct Entry {
        SubscriptionId id;
        EventHandler handler;
    };

    std::mutex mutex_;
    std::unordered_map<EventType, std::vector<Entry>> handlers_;
    SubscriptionId nextId_{0};
};

} // namespace dietcode::core
