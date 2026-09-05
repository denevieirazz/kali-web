#pragma once

#include "protocol_v21.h"

#include <string>
#include <vector>

namespace CloudOS
{

struct MountPointInfo final
{
    std::string id;
    std::string label;
    std::string path;
    std::string platform; // "windows", "linux", "cloudDrive"
    bool is_online{true};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class PathTranslationV21 final
{
public:
    // Windows -> Linux translation
    // e.g. "C:\\Users\\user\\file.txt" -> "/mnt/c/Users/user/file.txt"
    // e.g. "\\\\wsl.localhost\\Ubuntu\\home\\user" -> "/home/user"
    [[nodiscard]] static std::string WindowsToLinux(
        const std::string& win_path,
        const std::string& distro = "");

    // Linux -> Windows translation
    // e.g. "/mnt/c/Users/user/file.txt" -> "C:\\Users\\user\\file.txt"
    // e.g. "/home/user" (distro: "Ubuntu") -> "\\\\wsl.localhost\\Ubuntu\\home\\user"
    [[nodiscard]] static std::string LinuxToWindows(
        const std::string& linux_path,
        const std::string& distro = "");

    // Enumerates system mount points (Windows drives, CloudOS Drive, WSL distros)
    [[nodiscard]] static std::vector<MountPointInfo> GetMountPoints();

    // Verifies path existence safely without blocking if WSL is offline
    [[nodiscard]] static bool PathExists(
        const std::string& path,
        const std::string& distro = "");
};

} // namespace CloudOS
