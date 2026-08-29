#pragma once

#include <windows.h>

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace CloudOS
{
enum class ShellActionCategory : int
{
    All = 0,
    CloudOS,
    System,
    Network,
    Personalization,
    Privacy,
    Apps,
    Session,
};

enum class ShellActionKind : int
{
    CloudOSApp = 0,
    SettingsUri,
    ShellTarget,
    Lock,
    RestartCloudOS,
    ExitCloudOS,
    PowerCommand,
};

struct ShellAction final
{
    const wchar_t* id;
    const wchar_t* title;
    const wchar_t* description;
    const wchar_t* keywords;
    const wchar_t* target;
    const wchar_t* parameters;
    ShellActionCategory category;
    ShellActionKind kind;
};

class NativeShellActions final
{
public:
    static const std::vector<ShellAction>& All();
    static const ShellAction* Find(std::wstring_view id) noexcept;
    static std::vector<std::size_t> Filter(
        std::wstring_view query,
        ShellActionCategory category = ShellActionCategory::All);
    static bool Execute(
        HINSTANCE instance,
        HWND owner,
        const ShellAction& action);
    static const wchar_t* CategoryLabel(ShellActionCategory category) noexcept;
};
} // namespace CloudOS
