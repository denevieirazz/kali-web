#pragma once

#include "protocol_v21.h"

#include <string>
#include <vector>

namespace CloudOS
{

struct FileItemV21 final
{
    std::string name;
    std::string path;
    bool is_folder{};
    std::string size_formatted;
    std::string modified_formatted;
    std::string source;
    std::string extension;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class FileServiceV21 final
{
public:
    static FileServiceV21& Instance();

    FileServiceV21(const FileServiceV21&) = delete;
    FileServiceV21& operator=(const FileServiceV21&) = delete;

    bool ListLocation(
        const std::string& location,
        std::vector<FileItemV21>& items,
        std::string& error) const;

    [[nodiscard]] static bool IsAllowedLocation(const std::string& location) noexcept;

private:
    FileServiceV21() = default;
};

} // namespace CloudOS
