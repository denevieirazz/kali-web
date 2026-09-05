#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <sstream>
#include <iomanip>

namespace CloudOS::WindowRegistryV23
{
inline constexpr std::uint32_t kSchema = 23;
inline constexpr std::uintptr_t kWindowCommandCopyDataTag = static_cast<std::uintptr_t>(0x434F535743323300ull); // COSWC23
inline constexpr std::uintptr_t kWindowSnapshotCopyDataTag = static_cast<std::uintptr_t>(0x434F535753323300ull); // COSWS23
inline constexpr wchar_t kWindowServerClass[] = L"CloudOS.NativeShell.Activation.v21";

struct WindowBounds final
{
    std::int32_t x{0};
    std::int32_t y{0};
    std::int32_t width{0};
    std::int32_t height{0};

    [[nodiscard]] bool Equals(const WindowBounds& other) const noexcept
    {
        return x == other.x && y == other.y && width == other.width && height == other.height;
    }
};

struct CloudWindowRecordV23 final
{
    std::string id;
    std::string platform; // "cloudos", "windows", "linux"
    std::uint32_t pid{0};
    std::uint64_t hwnd{0};
    std::string title;
    std::string app_id;
    std::string state{"normal"}; // "normal", "minimized", "maximized", "fullscreen"
    WindowBounds bounds{};
    bool minimized{false};
    bool maximized{false};
    bool fullscreen{false};
    bool visible{true};
    bool focused{false};
    std::string monitor_id;
    std::int32_t workspace_id{1}; // 1-based (1..4)
    std::string parent_window_id;
    std::string owner_window_id;
    std::vector<std::string> capabilities;

    [[nodiscard]] std::string ToJson() const
    {
        std::ostringstream ss;
        ss << "{"
           << "\"id\":\"" << EscapeJson(id) << "\","
           << "\"platform\":\"" << EscapeJson(platform) << "\","
           << "\"pid\":" << pid << ","
           << "\"hwnd\":" << hwnd << ","
           << "\"title\":\"" << EscapeJson(title) << "\","
           << "\"appId\":\"" << EscapeJson(app_id) << "\","
           << "\"state\":\"" << EscapeJson(state) << "\","
           << "\"bounds\":{"
               << "\"x\":" << bounds.x << ","
               << "\"y\":" << bounds.y << ","
               << "\"width\":" << bounds.width << ","
               << "\"height\":" << bounds.height << "},"
           << "\"minimized\":" << (minimized ? "true" : "false") << ","
           << "\"maximized\":" << (maximized ? "true" : "false") << ","
           << "\"fullscreen\":" << (fullscreen ? "true" : "false") << ","
           << "\"visible\":" << (visible ? "true" : "false") << ","
           << "\"focused\":" << (focused ? "true" : "false") << ","
           << "\"monitorId\":\"" << EscapeJson(monitor_id) << "\","
           << "\"workspaceId\":" << workspace_id << ","
           << "\"parentWindowId\":\"" << EscapeJson(parent_window_id) << "\","
           << "\"ownerWindowId\":\"" << EscapeJson(owner_window_id) << "\","
           << "\"capabilities\":[";
        for (std::size_t i = 0; i < capabilities.size(); ++i)
        {
            if (i > 0) ss << ",";
            ss << "\"" << EscapeJson(capabilities[i]) << "\"";
        }
        ss << "]}";
        return ss.str();
    }

private:
    static std::string EscapeJson(std::string_view s)
    {
        std::ostringstream ss;
        for (char c : s)
        {
            switch (c)
            {
            case '"': ss << "\\\""; break;
            case '\\': ss << "\\\\"; break;
            case '\b': ss << "\\b"; break;
            case '\f': ss << "\\f"; break;
            case '\n': ss << "\\n"; break;
            case '\r': ss << "\\r"; break;
            case '\t': ss << "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20)
                {
                    ss << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<int>(static_cast<unsigned char>(c));
                }
                else
                {
                    ss << c;
                }
                break;
            }
        }
        return ss.str();
    }
};

struct CloudMonitorRecordV23 final
{
    std::string id;
    std::string device_name;
    WindowBounds bounds{};
    WindowBounds work_area{};
    std::uint32_t dpi{96};
    double scale{1.0};
    bool primary{false};

    [[nodiscard]] std::string ToJson() const
    {
        std::ostringstream ss;
        ss << "{"
           << "\"id\":\"" << id << "\","
           << "\"deviceName\":\"" << device_name << "\","
           << "\"bounds\":{\"x\":" << bounds.x << ",\"y\":" << bounds.y
               << ",\"width\":" << bounds.width << ",\"height\":" << bounds.height << "},"
           << "\"workArea\":{\"x\":" << work_area.x << ",\"y\":" << work_area.y
               << ",\"width\":" << work_area.width << ",\"height\":" << work_area.height << "},"
           << "\"dpi\":" << dpi << ","
           << "\"scale\":" << scale << ","
           << "\"primary\":" << (primary ? "true" : "false")
           << "}";
        return ss.str();
    }
};

struct CloudWindowEventV23 final
{
    std::uint64_t sequence{0};
    std::uint64_t timestamp_ms{0};
    std::string event_type; // e.g., "window.created", "window.focused"
    std::string window_id;
    CloudWindowRecordV23 window;

    [[nodiscard]] std::string ToJson() const
    {
        std::ostringstream ss;
        ss << "{"
           << "\"sequence\":" << sequence << ","
           << "\"timestamp\":" << timestamp_ms << ","
           << "\"eventType\":\"" << event_type << "\","
           << "\"windowId\":\"" << window_id << "\","
           << "\"window\":" << window.ToJson()
           << "}";
        return ss.str();
    }
};

struct CloudWindowSnapshotV23 final
{
    std::uint64_t sequence{0};
    std::uint64_t timestamp_ms{0};
    std::vector<CloudWindowRecordV23> windows;
    std::string focused_window_id;
    std::int32_t current_workspace{1};
    std::vector<CloudMonitorRecordV23> monitors;

    [[nodiscard]] std::string ToJson() const
    {
        std::ostringstream ss;
        ss << "{"
           << "\"sequence\":" << sequence << ","
           << "\"timestamp\":" << timestamp_ms << ","
           << "\"currentWorkspace\":" << current_workspace << ","
           << "\"focusedWindowId\":\"" << focused_window_id << "\","
           << "\"windows\":[";
        for (std::size_t i = 0; i < windows.size(); ++i)
        {
            if (i > 0) ss << ",";
            ss << windows[i].ToJson();
        }
        ss << "],"
           << "\"monitors\":[";
        for (std::size_t i = 0; i < monitors.size(); ++i)
        {
            if (i > 0) ss << ",";
            ss << monitors[i].ToJson();
        }
        ss << "]}";
        return ss.str();
    }
};

enum class WindowCommandAction : std::uint32_t
{
    Focus = 1,
    Minimize = 2,
    Maximize = 3,
    Restore = 4,
    Close = 5,
    Move = 6,
    Resize = 7,
    SetBounds = 8,
    Snap = 9,
    MoveToWorkspace = 10,
    SetFullscreen = 11,
};

enum class SnapTarget : std::uint32_t
{
    None = 0,
    Left = 1,
    Right = 2,
    Top = 3,
    Maximize = 4,
    Restore = 5,
    TopLeft = 6,
    TopRight = 7,
    BottomLeft = 8,
    BottomRight = 9,
};

struct WindowCommandPayload final
{
    std::uint32_t schema{kSchema};
    WindowCommandAction action{WindowCommandAction::Focus};
    std::uint64_t hwnd{0};
    std::int32_t x{0};
    std::int32_t y{0};
    std::int32_t width{0};
    std::int32_t height{0};
    std::int32_t workspace{1};
    SnapTarget snap{SnapTarget::None};
};

} // namespace CloudOS::WindowRegistryV23
