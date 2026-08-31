#include "native_performance_v12.h"
#include "native_icon_cache_v12.h"
#include "native_window_manager.h"

#include <dwmapi.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <string_view>
#include <utility>
#include <vector>

#pragma comment(lib, "dwmapi.lib")

namespace
{
constexpr int kWorkspaceCount = 4;
constexpr COLORREF kActiveBorder = RGB(91, 140, 255);
constexpr COLORREF kInactiveBorder = 0xFFFFFFFFu;
constexpr DWORD kDwmBorderColorAttribute = 34u;
constexpr DWORD kExcludedStyles = WS_DISABLED;
constexpr wchar_t kWorkspaceHiddenProperty[] = L"CloudOS.Native.WorkspaceHidden.v1";

bool IsCloaked(HWND window) noexcept
{
    DWORD cloaked = 0;
    const HRESULT result = DwmGetWindowAttribute(
        window,
        DWMWA_CLOAKED,
        &cloaked,
        static_cast<DWORD>(sizeof(cloaked)));
    return SUCCEEDED(result) && cloaked != 0;
}

void SetBorderColor(HWND window, COLORREF color) noexcept
{
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }

    (void)DwmSetWindowAttribute(
        window,
        kDwmBorderColorAttribute,
        &color,
        static_cast<DWORD>(sizeof(color)));
}

RECT MonitorWorkArea(HWND reference) noexcept
{
    RECT fallback{};
    (void)SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);

    HMONITOR monitor = MonitorFromWindow(
        reference != nullptr ? reference : GetDesktopWindow(),
        MONITOR_DEFAULTTOPRIMARY);
    if (monitor == nullptr)
    {
        return fallback;
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info))
    {
        return fallback;
    }
    return info.rcWork;
}

int Width(const RECT& rect) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rect.right - rect.left));
}

int Height(const RECT& rect) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rect.bottom - rect.top));
}
}

CloudOSNativeWindowManager::~CloudOSNativeWindowManager()
{
    Shutdown();
}

bool CloudOSNativeWindowManager::Initialize(HWND event_sink)
{
    Shutdown();
    if (event_sink == nullptr || !IsWindow(event_sink))
    {
        SetLastError(ERROR_INVALID_WINDOW_HANDLE);
        return false;
    }

    event_sink_ = event_sink;
    windows_.clear();
    current_workspace_ = 0;
    active_window_ = nullptr;

    if (!cloudos_native_window_enumerate(&RuntimeWindowEnumeration, this))
    {
        event_sink_ = nullptr;
        return false;
    }

    (void)EnumWindows(
        &LocalWindowEnumeration,
        reinterpret_cast<LPARAM>(this));

    if (!cloudos_native_window_events_start(&RuntimeWindowEvent, this, &watcher_))
    {
        windows_.clear();
        event_sink_ = nullptr;
        return false;
    }

    const HWND foreground = GetForegroundWindow();
    if (foreground != nullptr)
    {
        UpdateForeground(foreground);
    }

    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }

    SetLastError(ERROR_SUCCESS);
    return true;
}

void CloudOSNativeWindowManager::Shutdown() noexcept
{
    if (watcher_ != nullptr)
    {
        cloudos_native_window_events_stop(watcher_);
        watcher_ = nullptr;
    }

    for (auto& item : windows_)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }

        if (item.hidden_by_workspace || GetPropW(item.hwnd, kWorkspaceHiddenProperty) != nullptr)
        {
            MarkWorkspaceHidden(item.hwnd, false);
            ShowWindow(item.hwnd, SW_SHOWNA);
        }
        SetBorderColor(item.hwnd, kInactiveBorder);
    }

    windows_.clear();
    event_sink_ = nullptr;
    active_window_ = nullptr;
}

void CloudOSNativeWindowManager::SetReservedBottomPixels(int pixels) noexcept
{
    reserved_bottom_pixels_ = std::max(0, pixels);
}

void CALLBACK CloudOSNativeWindowManager::RuntimeWindowEvent(
    cloudos_native_window_event_kind kind,
    HWND window,
    DWORD,
    void* context)
{
    auto* self = static_cast<CloudOSNativeWindowManager*>(context);
    if (self == nullptr || self->event_sink_ == nullptr)
    {
        return;
    }

    (void)PostMessageW(
        self->event_sink_,
        CLOUDOS_WM_NATIVE_WINDOW_EVENT,
        static_cast<WPARAM>(kind),
        reinterpret_cast<LPARAM>(window));
}

BOOL CALLBACK CloudOSNativeWindowManager::RuntimeWindowEnumeration(
    HWND window,
    DWORD process_id,
    BOOL visible,
    void* context)
{
    auto* self = static_cast<CloudOSNativeWindowManager*>(context);
    if (self == nullptr)
    {
        return FALSE;
    }

    if (!visible && GetPropW(window, kWorkspaceHiddenProperty) != nullptr)
    {
        self->RecoverTaggedWindow(window);
    }
    self->AddOrRefresh(window, process_id);
    return TRUE;
}

BOOL CALLBACK CloudOSNativeWindowManager::LocalWindowEnumeration(
    HWND window,
    LPARAM context)
{
    auto* self = reinterpret_cast<CloudOSNativeWindowManager*>(context);
    if (self == nullptr)
    {
        return FALSE;
    }

    DWORD process_id = 0;
    (void)GetWindowThreadProcessId(window, &process_id);
    if (process_id == GetCurrentProcessId())
    {
        self->AddOrRefresh(window, process_id);
    }
    return TRUE;
}

void CloudOSNativeWindowManager::HandleRuntimeEvent(
    cloudos_native_window_event_kind kind,
    HWND window)
{
    switch (kind)
    {
    case CLOUDOS_NATIVE_WINDOW_DESTROYED:
        Remove(window);
        break;

    case CLOUDOS_NATIVE_WINDOW_FOREGROUND:
        if (window != nullptr && IsWindow(window))
        {
            DWORD process_id = 0;
            (void)GetWindowThreadProcessId(window, &process_id);
            AddOrRefresh(window, process_id);
        }
        UpdateForeground(window);
        break;

    case CLOUDOS_NATIVE_WINDOW_CREATED:
    case CLOUDOS_NATIVE_WINDOW_SHOWN:
    case CLOUDOS_NATIVE_WINDOW_LOCATION_CHANGED:
        if (window != nullptr && IsWindow(window))
        {
            DWORD process_id = 0;
            (void)GetWindowThreadProcessId(window, &process_id);
            AddOrRefresh(window, process_id);
        }
        break;

    case CLOUDOS_NATIVE_WINDOW_HIDDEN:
        if (Find(window)) NotifyChanged();
        break;
    case CLOUDOS_NATIVE_WINDOW_UNKNOWN:
    default:
        break;
    }

    if (tiling_enabled_ &&
        (kind == CLOUDOS_NATIVE_WINDOW_CREATED || kind == CLOUDOS_NATIVE_WINDOW_SHOWN))
    {
        TileCurrentWorkspace();
    }
}

void CloudOSNativeWindowManager::Reconcile()
{
    CloudOS::PerformanceV12::Add(CloudOS::PerformanceV12::Reconcile);
    windows_.erase(
        std::remove_if(
            windows_.begin(),
            windows_.end(),
            [](const CloudOSManagedWindow& item)
            {
                return item.hwnd == nullptr || !IsWindow(item.hwnd);
            }),
        windows_.end());

    (void)cloudos_native_window_enumerate(&RuntimeWindowEnumeration, this);
    (void)EnumWindows(
        &LocalWindowEnumeration,
        reinterpret_cast<LPARAM>(this));

    if (active_window_ != nullptr && !IsWindow(active_window_))
    {
        active_window_ = nullptr;
    }

    const HWND foreground = GetForegroundWindow();
    if (foreground != nullptr)
    {
        UpdateForeground(foreground);
    }
    else
    {
        UpdateBorders();
    }
}

bool CloudOSNativeWindowManager::IsManageable(
    HWND window,
    DWORD process_id,
    bool require_visible) const
{
    if (window == nullptr ||
        !IsWindow(window) ||
        process_id == 0 ||
        window == event_sink_ ||
        GetAncestor(window, GA_ROOT) != window)
    {
        return false;
    }

    if (require_visible && !IsWindowVisible(window))
    {
        return false;
    }

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & kExcludedStyles) != 0 ||
        (extended_style & WS_EX_TOOLWINDOW) != 0 ||
        IsCloaked(window))
    {
        return false;
    }

    const HWND owner = GetWindow(window, GW_OWNER);
    if (owner != nullptr && (extended_style & WS_EX_APPWINDOW) == 0)
    {
        return false;
    }

    if (IsExcludedClass(window))
    {
        return false;
    }

    const std::wstring title = ReadWindowTitle(window);
    if (title.empty())
    {
        return false;
    }

    RECT bounds{};
    if (!GetWindowRect(window, &bounds) || Width(bounds) < 32 || Height(bounds) < 32)
    {
        return false;
    }

    return true;
}

void CloudOSNativeWindowManager::AddOrRefresh(HWND window, DWORD process_id)
{
    if (window == nullptr || process_id == 0)
    {
        return;
    }

    CloudOSManagedWindow* existing = Find(window);
    if (existing != nullptr)
    {
        RECT bounds{}; GetWindowRect(window,&bounds);
        const std::wstring title = ReadWindowTitle(window);
        if (existing->title != title) CloudOS::NativeIconCacheV12::Instance().InvalidateReady(CloudOS::NativeIconCacheV12::WindowKey(window));
        const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
        const bool minimized = IsIconic(window) != FALSE;
        if (existing->title != title || existing->monitor != monitor || existing->minimized != minimized || !EqualRect(&existing->bounds,&bounds))
        { existing->title = title; existing->monitor = monitor; existing->minimized = minimized; existing->bounds=bounds; NotifyChanged(); }
        return;
    }

    if (!IsManageable(window, process_id, true))
    {
        return;
    }

    CloudOSManagedWindow item{};
    CloudOS::NativeIconCacheV12::Instance().InvalidateReady(CloudOS::NativeIconCacheV12::WindowKey(window));
    item.hwnd = window;
    item.process_id = process_id;
    item.workspace = current_workspace_;
    item.floating = false;
    item.hidden_by_workspace = false;
    GetWindowRect(window,&item.bounds);
    item.title = ReadWindowTitle(window);
    item.monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST); item.minimized = IsIconic(window) != FALSE;
    windows_.push_back(std::move(item));
    NotifyChanged();
}

void CloudOSNativeWindowManager::Remove(HWND window)
{
    if (Find(window)) NotifyChanged();
    windows_.erase(
        std::remove_if(
            windows_.begin(),
            windows_.end(),
            [window](const CloudOSManagedWindow& item)
            {
                return item.hwnd == window;
            }),
        windows_.end());

    if (active_window_ == window)
    {
        active_window_ = nullptr;
    }
    UpdateBorders();
}

CloudOSManagedWindow* CloudOSNativeWindowManager::Find(HWND window) noexcept
{
    const auto iterator = std::find_if(
        windows_.begin(),
        windows_.end(),
        [window](const CloudOSManagedWindow& item)
        {
            return item.hwnd == window;
        });
    return iterator == windows_.end() ? nullptr : &(*iterator);
}

const CloudOSManagedWindow* CloudOSNativeWindowManager::Find(HWND window) const noexcept
{
    const auto iterator = std::find_if(
        windows_.cbegin(),
        windows_.cend(),
        [window](const CloudOSManagedWindow& item)
        {
            return item.hwnd == window;
        });
    return iterator == windows_.cend() ? nullptr : &(*iterator);
}

void CloudOSNativeWindowManager::UpdateForeground(HWND window)
{
    const auto* managed = Find(window);
    if (managed != nullptr && managed->workspace == current_workspace_)
    {
        if (active_window_ == window) return;
        NotifyChanged();
        active_window_ = window;
    }
    UpdateBorders();
}

void CloudOSNativeWindowManager::UpdateBorders()
{
    for (const auto& item : windows_)
    {
        const COLORREF color =
            item.hwnd == active_window_ && item.workspace == current_workspace_
            ? kActiveBorder
            : kInactiveBorder;
        SetBorderColor(item.hwnd, color);
    }
}

void CloudOSNativeWindowManager::RecoverTaggedWindow(HWND window)
{
    if (window == nullptr || !IsWindow(window) || GetPropW(window, kWorkspaceHiddenProperty) == nullptr)
    {
        return;
    }

    MarkWorkspaceHidden(window, false);
    ShowWindow(window, SW_SHOWNA);
}

void CloudOSNativeWindowManager::MarkWorkspaceHidden(HWND window, bool hidden) noexcept
{
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }

    if (hidden)
    {
        (void)SetPropW(window, kWorkspaceHiddenProperty, reinterpret_cast<HANDLE>(1));
    }
    else
    {
        (void)RemovePropW(window, kWorkspaceHiddenProperty);
    }
}

std::vector<CloudOSManagedWindow> CloudOSNativeWindowManager::CurrentWorkspaceWindows() const
{
    std::vector<CloudOSManagedWindow> result;
    result.reserve(windows_.size());

    for (const auto& item : windows_)
    {
        if (item.workspace == current_workspace_ &&
            item.hwnd != nullptr &&
            IsWindow(item.hwnd))
        {
            result.push_back(item);
        }
    }
    return result;
}

std::size_t CloudOSNativeWindowManager::ManagedWindowCount() const noexcept
{
    return windows_.size();
}

int CloudOSNativeWindowManager::CurrentWorkspace() const noexcept
{
    return current_workspace_;
}

bool CloudOSNativeWindowManager::TilingEnabled() const noexcept
{
    return tiling_enabled_;
}

HWND CloudOSNativeWindowManager::ActiveManagedWindow() const noexcept
{
    if (active_window_ != nullptr && Find(active_window_) != nullptr)
    {
        return active_window_;
    }

    const HWND foreground = GetForegroundWindow();
    const auto* managed = Find(foreground);
    if (managed != nullptr && managed->workspace == current_workspace_)
    {
        return foreground;
    }
    return nullptr;
}

void CloudOSNativeWindowManager::FocusWindow(HWND window)
{
    auto* item = Find(window);
    if (item == nullptr || item->workspace != current_workspace_ || !IsWindow(window))
    {
        return;
    }

    if (item->hidden_by_workspace)
    {
        item->hidden_by_workspace = false;
        MarkWorkspaceHidden(window, false);
        ShowWindow(window, SW_SHOWNA);
    }
    if (IsIconic(window))
    {
        ShowWindow(window, SW_RESTORE);
    }

    (void)SetForegroundWindow(window);
    (void)BringWindowToTop(window);
    active_window_ = window;
    UpdateBorders();
}

void CloudOSNativeWindowManager::FocusNext(bool reverse)
{
    auto current = CurrentWorkspaceWindows();
    current.erase(
        std::remove_if(
            current.begin(),
            current.end(),
            [](const CloudOSManagedWindow& item)
            {
                return item.hidden_by_workspace || !IsWindowVisible(item.hwnd);
            }),
        current.end());

    if (current.empty())
    {
        return;
    }

    const HWND active = ActiveManagedWindow();
    std::size_t index = 0;
    bool found_active = false;
    for (std::size_t candidate = 0; candidate < current.size(); ++candidate)
    {
        if (current[candidate].hwnd == active)
        {
            index = candidate;
            found_active = true;
            break;
        }
    }

    if (!found_active)
    {
        index = reverse ? current.size() - 1u : 0u;
    }
    else if (reverse)
    {
        index = index == 0 ? current.size() - 1u : index - 1u;
    }
    else
    {
        index = (index + 1u) % current.size();
    }

    FocusWindow(current[index].hwnd);
}

void CloudOSNativeWindowManager::CloseActive()
{
    const HWND active = ActiveManagedWindow();
    if (active != nullptr)
    {
        (void)PostMessageW(active, WM_CLOSE, 0, 0);
    }
}

void CloudOSNativeWindowManager::MinimizeActive()
{
    const HWND active = ActiveManagedWindow();
    if (active != nullptr)
    {
        ShowWindow(active, SW_MINIMIZE);
    }
}

void CloudOSNativeWindowManager::ToggleMaximizeActive()
{
    const HWND active = ActiveManagedWindow();
    if (active != nullptr)
    {
        ShowWindow(active, IsZoomed(active) ? SW_RESTORE : SW_MAXIMIZE);
    }
}

RECT CloudOSNativeWindowManager::WorkAreaFor(HWND reference) const noexcept
{
    RECT area = MonitorWorkArea(reference != nullptr ? reference : event_sink_);
    if (event_sink_ == nullptr || reserved_bottom_pixels_ <= 0)
    {
        return area;
    }

    const HMONITOR shell_monitor = MonitorFromWindow(event_sink_, MONITOR_DEFAULTTOPRIMARY);
    const HMONITOR target_monitor = MonitorFromWindow(
        reference != nullptr ? reference : event_sink_,
        MONITOR_DEFAULTTOPRIMARY);
    if (shell_monitor == target_monitor)
    {
        area.bottom = std::max(area.top, area.bottom - reserved_bottom_pixels_);
    }
    return area;
}

void CloudOSNativeWindowManager::SnapActive(CloudOSSnapDirection direction)
{
    const HWND active = ActiveManagedWindow();
    if (active == nullptr)
    {
        return;
    }

    auto* item = Find(active);
    if (item == nullptr)
    {
        return;
    }

    if (IsZoomed(active))
    {
        ShowWindow(active, SW_RESTORE);
    }

    const RECT area = WorkAreaFor(active);
    const int width = Width(area);
    const int height = Height(area);
    if (width <= 0 || height <= 0)
    {
        return;
    }

    RECT target = area;
    switch (direction)
    {
    case CloudOSSnapDirection::Left:
        target.right = area.left + width / 2;
        break;
    case CloudOSSnapDirection::Right:
        target.left = area.left + width / 2;
        break;
    case CloudOSSnapDirection::Up:
        target.bottom = area.top + height / 2;
        break;
    case CloudOSSnapDirection::Down:
        target.top = area.top + height / 2;
        break;
    }

    item->floating = true;
    (void)SetWindowPos(
        active,
        HWND_TOP,
        target.left,
        target.top,
        Width(target),
        Height(target),
        SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
    FocusWindow(active);
}

void CloudOSNativeWindowManager::ToggleTiling()
{
    tiling_enabled_ = !tiling_enabled_;
    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
}

void CloudOSNativeWindowManager::TileCurrentWorkspace()
{
    if (!tiling_enabled_)
    {
        return;
    }

    struct MonitorGroup final
    {
        HMONITOR monitor{};
        RECT work_area{};
        std::vector<HWND> windows;
    };

    std::vector<MonitorGroup> groups;
    for (auto& item : windows_)
    {
        if (item.workspace != current_workspace_ ||
            item.floating ||
            item.hidden_by_workspace ||
            item.hwnd == nullptr ||
            !IsWindow(item.hwnd) ||
            IsIconic(item.hwnd))
        {
            continue;
        }

        const HMONITOR monitor = MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST);
        auto iterator = std::find_if(
            groups.begin(),
            groups.end(),
            [monitor](const MonitorGroup& group)
            {
                return group.monitor == monitor;
            });

        if (iterator == groups.end())
        {
            MonitorGroup group{};
            group.monitor = monitor;
            group.work_area = WorkAreaFor(item.hwnd);
            group.windows.push_back(item.hwnd);
            groups.push_back(std::move(group));
        }
        else
        {
            iterator->windows.push_back(item.hwnd);
        }
    }

    for (const auto& group : groups)
    {
        const int total_width = Width(group.work_area);
        const int total_height = Height(group.work_area);
        const std::size_t count = group.windows.size();
        if (count == 0 || total_width <= 0 || total_height <= 0)
        {
            continue;
        }

        for (std::size_t index = 0; index < count; ++index)
        {
            HWND window = group.windows[index];
            if (IsZoomed(window))
            {
                ShowWindow(window, SW_RESTORE);
            }

            RECT target = group.work_area;
            if (count == 2)
            {
                const int half = total_width / 2;
                if (index == 0)
                {
                    target.right = target.left + half;
                }
                else
                {
                    target.left += half;
                }
            }
            else if (count >= 3)
            {
                const int master_width = total_width / 2;
                if (index == 0)
                {
                    target.right = target.left + master_width;
                }
                else
                {
                    const std::size_t stack_count = count - 1u;
                    const int stack_height = total_height / static_cast<int>(stack_count);
                    target.left += master_width;
                    target.top += static_cast<int>(index - 1u) * stack_height;
                    target.bottom =
                        index == count - 1u
                        ? group.work_area.bottom
                        : target.top + stack_height;
                }
            }

            (void)SetWindowPos(
                window,
                HWND_TOP,
                target.left,
                target.top,
                Width(target),
                Height(target),
                SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
        }
    }

    if (active_window_ != nullptr)
    {
        FocusWindow(active_window_);
    }
}

void CloudOSNativeWindowManager::ToggleFloatingActive()
{
    const HWND active = ActiveManagedWindow();
    auto* item = Find(active);
    if (item == nullptr)
    {
        return;
    }

    item->floating = !item->floating;
    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
}

void CloudOSNativeWindowManager::SwitchWorkspace(int workspace)
{
    if (workspace < 0 || workspace >= kWorkspaceCount || workspace == current_workspace_)
    {
        return;
    }

    for (auto& item : windows_)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }

        if (item.workspace == current_workspace_ &&
            !IsIconic(item.hwnd) &&
            IsWindowVisible(item.hwnd))
        {
            MarkWorkspaceHidden(item.hwnd, true);
            ShowWindow(item.hwnd, SW_HIDE);
            item.hidden_by_workspace = true;
        }
    }

    current_workspace_ = workspace;
    NotifyChanged();
    active_window_ = nullptr;

    for (auto& item : windows_)
    {
        if (item.workspace == current_workspace_ &&
            item.hidden_by_workspace &&
            IsWindow(item.hwnd))
        {
            item.hidden_by_workspace = false;
            MarkWorkspaceHidden(item.hwnd, false);
            ShowWindow(item.hwnd, SW_SHOWNA);
        }
    }

    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
    UpdateBorders();
}

void CloudOSNativeWindowManager::MoveActiveToWorkspace(int workspace)
{
    if (workspace < 0 || workspace >= kWorkspaceCount)
    {
        return;
    }

    const HWND active = ActiveManagedWindow();
    auto* item = Find(active);
    if (item == nullptr || item->workspace == workspace)
    {
        return;
    }

    item->workspace = workspace;
    NotifyChanged();
    if (workspace != current_workspace_ && IsWindow(item->hwnd))
    {
        MarkWorkspaceHidden(item->hwnd, true);
        ShowWindow(item->hwnd, SW_HIDE);
        item->hidden_by_workspace = true;
        active_window_ = nullptr;
    }

    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
    UpdateBorders();
}

std::wstring CloudOSNativeWindowManager::ReadWindowTitle(HWND window)
{
    const int length = GetWindowTextLengthW(window);
    if (length <= 0)
    {
        return {};
    }

    std::wstring title(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(
        window,
        title.data(),
        static_cast<int>(title.size()));
    if (copied <= 0)
    {
        return {};
    }

    title.resize(static_cast<std::size_t>(copied));
    return title;
}

bool CloudOSNativeWindowManager::IsExcludedClass(HWND window)
{
    std::array<wchar_t, 256> buffer{};
    const int length = GetClassNameW(
        window,
        buffer.data(),
        static_cast<int>(buffer.size()));
    if (length <= 0)
    {
        return false;
    }

    const std::wstring_view class_name(
        buffer.data(),
        static_cast<std::size_t>(length));

    static constexpr std::array<std::wstring_view, 13> excluded{
        L"CloudOS.NativeShell.Desktop.v2",
        L"CloudOS.NativeShell.Taskbar.v2",
        L"CloudOS.NativeShell.Start.v2",
        L"Shell_TrayWnd",
        L"Shell_SecondaryTrayWnd",
        L"Progman",
        L"WorkerW",
        L"DV2ControlHost",
        L"MultitaskingViewFrame",
        L"XamlExplorerHostIslandWindow",
        L"ForegroundStaging",
        L"Shell_InputSwitchTopLevelWindow",
        L"Windows.UI.Core.CoreWindow",
    };

    return std::find(excluded.begin(), excluded.end(), class_name) != excluded.end();
}
