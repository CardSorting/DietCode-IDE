#include "filesystem/FileService.hpp"

#include <fstream>
#include <iterator>
#include <system_error>
#include <utility>

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
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file) {
        return FileWriteResult{false, "Could not open the file for writing."};
    }

    file.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!file) {
        return FileWriteResult{false, "The file could not be written completely."};
    }

    return FileWriteResult{true, {}};
}

bool FileService::exists(const std::filesystem::path& path) const {
    std::error_code error;
    return std::filesystem::exists(path, error);
}

} // namespace dietcode::filesystem
