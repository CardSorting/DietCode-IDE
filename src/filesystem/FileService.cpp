#include "filesystem/FileService.hpp"

#include <fstream>
#include <iterator>
#include <system_error>
#include <utility>
#include <chrono>

namespace dietcode::filesystem {

FileReadResult FileService::readTextFile(const std::filesystem::path& path) const {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return FileReadResult{false, {}, "Could not open the file for reading."};
    }

    std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (file.bad()) {
        return FileReadResult{false, {}, "The file could not be read completely."};
    }

    return FileReadResult{true, std::move(contents), {}};
}

FileWriteResult FileService::writeTextFile(const std::filesystem::path& path, const std::string& contents) const {
    auto timestamp = std::chrono::steady_clock::now().time_since_epoch().count();
    std::filesystem::path tempPath = path.parent_path() / (path.filename().string() + ".tmp." + std::to_string(timestamp));

    std::ofstream file(tempPath, std::ios::binary | std::ios::trunc);
    if (!file) {
        return FileWriteResult{false, "Could not open the temporary file for writing."};
    }

    file.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!file) {
        file.close();
        std::error_code ec;
        std::filesystem::remove(tempPath, ec);
        return FileWriteResult{false, "The file could not be written completely."};
    }
    file.close();

    std::error_code ec;
    std::filesystem::rename(tempPath, path, ec);
    if (ec) {
        std::error_code remove_ec;
        std::filesystem::remove(tempPath, remove_ec);
        return FileWriteResult{false, "Could not replace the original file atomically: " + ec.message()};
    }

    return FileWriteResult{true, {}};
}

bool FileService::exists(const std::filesystem::path& path) const {
    std::error_code error;
    return std::filesystem::exists(path, error);
}

} // namespace dietcode::filesystem
