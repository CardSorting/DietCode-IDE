#pragma once

#include <string>
#include <functional>
#include <vector>
#include <memory>

namespace dietcode::filesystem {

struct FileEvent {
    enum class Kind { Created, Modified, Deleted, Renamed };
    Kind kind;
    std::string path;
};

using FileEventCallback = std::function<void(const std::vector<FileEvent>&)>;

class FileWatcher {
public:
    FileWatcher(std::string path, FileEventCallback callback);
    ~FileWatcher();

    bool start();
    void stop();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace dietcode::filesystem
