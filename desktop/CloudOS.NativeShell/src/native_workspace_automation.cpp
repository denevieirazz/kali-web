#include "native_workspace_automation.h"

#include "native_app_launcher.h"
#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_wallpaper_manager.h"
#include "native_window_manager.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cwctype>
#include <shellapi.h>
#include <string_view>
#include <unordered_set>
#include <utility>

namespace CloudOS
{
namespace
{
constexpr LONG kNormalizedScale = 10000;

std::uint64_t FileTimeNow()
{
    FILETIME value{};
    GetSystemTimeAsFileTime(&value);
    ULARGE_INTEGER raw{};
    raw.LowPart = value.dwLowDateTime;
    raw.HighPart = value.dwHighDateTime;
    return raw.QuadPart;
}

std::wstring Lower(std::wstring value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t character)
        {
            return static_cast<wchar_t>(std::towlower(character));
        });
    return value;
}

std::wstring BaseName(const std::wstring& path)
{
    const std::size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

bool WildcardMatch(std::wstring_view pattern, std::wstring_view value)
{
    std::size_t pattern_index = 0;
    std::size_t value_index = 0;
    std::size_t star_index = std::wstring_view::npos;
    std::size_t retry_value = 0;

    while (value_index < value.size())
    {
        if (pattern_index < pattern.size() &&
            (pattern[pattern_index] == L'?' || pattern[pattern_index] == value[value_index]))
        {
            ++pattern_index;
            ++value_index;
            continue;
        }
        if (pattern_index < pattern.size() && pattern[pattern_index] == L'*')
        {
            star_index = pattern_index++;
            retry_value = value_index;
            continue;
        }
        if (star_index != std::wstring_view::npos)
        {
            pattern_index = star_index + 1;
            value_index = ++retry_value;
            continue;
        }
        return false;
    }

    while (pattern_index < pattern.size() && pattern[pattern_index] == L'*')
    {
        ++pattern_index;
    }
    return pattern_index == pattern.size();
}

std::wstring MonitorDeviceName(HMONITOR monitor)
{
    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        return info.szDevice;
    }
    return {};
}

RECT MonitorWorkAreaByDevice(const std::wstring& device, HWND fallback_window)
{
    if (!device.empty())
    {
        const auto monitors = NativeMonitorManager::Enumerate();
        for (const auto& monitor : monitors)
        {
            if (_wcsicmp(monitor.device.c_str(), device.c_str()) == 0)
            {
                return monitor.work;
            }
        }
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const HMONITOR monitor = MonitorFromWindow(
        fallback_window != nullptr ? fallback_window : GetDesktopWindow(),
        MONITOR_DEFAULTTOPRIMARY);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        return info.rcWork;
    }
    RECT fallback{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
    return fallback;
}

RECT NormalizeBounds(const RECT& bounds, const RECT& work)
{
    RECT result{};
    const LONG width = std::max<LONG>(1, work.right - work.left);
    const LONG height = std::max<LONG>(1, work.bottom - work.top);
    result.left = ((bounds.left - work.left) * kNormalizedScale) / width;
    result.top = ((bounds.top - work.top) * kNormalizedScale) / height;
    result.right = ((bounds.right - work.left) * kNormalizedScale) / width;
    result.bottom = ((bounds.bottom - work.top) * kNormalizedScale) / height;
    result.left = std::clamp<LONG>(result.left, -kNormalizedScale, kNormalizedScale * 2);
    result.top = std::clamp<LONG>(result.top, -kNormalizedScale, kNormalizedScale * 2);
    result.right = std::clamp<LONG>(result.right, -kNormalizedScale, kNormalizedScale * 2);
    result.bottom = std::clamp<LONG>(result.bottom, -kNormalizedScale, kNormalizedScale * 2);
    return result;
}

RECT DenormalizeBounds(const RECT& normalized, const RECT& work)
{
    const LONG width = std::max<LONG>(1, work.right - work.left);
    const LONG height = std::max<LONG>(1, work.bottom - work.top);
    RECT result{};
    result.left = work.left + (normalized.left * width) / kNormalizedScale;
    result.top = work.top + (normalized.top * height) / kNormalizedScale;
    result.right = work.left + (normalized.right * width) / kNormalizedScale;
    result.bottom = work.top + (normalized.bottom * height) / kNormalizedScale;
    if (result.right - result.left < 160)
    {
        result.right = result.left + 160;
    }
    if (result.bottom - result.top < 120)
    {
        result.bottom = result.top + 120;
    }
    return result;
}

bool IdentityMatchesSnapshot(
    const WorkspaceWindowIdentity& identity,
    const WorkspaceLayoutWindow& layout)
{
    if (!layout.process_name.empty() &&
        _wcsicmp(identity.process_name.c_str(), layout.process_name.c_str()) != 0)
    {
        return false;
    }
    if (!layout.window_class.empty() &&
        _wcsicmp(identity.window_class.c_str(), layout.window_class.c_str()) != 0)
    {
        return false;
    }
    if (!layout.title_hint.empty())
    {
        const std::wstring title = Lower(identity.window_title);
        const std::wstring hint = Lower(layout.title_hint);
        if (title.find(hint) == std::wstring::npos && hint.find(title) == std::wstring::npos)
        {
            return false;
        }
    }
    return true;
}

std::vector<CloudOSManagedWindow> WindowsForWorkspace(
    CloudOSNativeWindowManager& manager,
    int workspace)
{
    std::vector<CloudOSManagedWindow> result;
    for (const auto& item : manager.AllManagedWindows())
    {
        if (item.workspace == workspace && item.hwnd != nullptr && IsWindow(item.hwnd))
        {
            result.push_back(item);
        }
    }
    return result;
}

void PositionWindow(HWND window, const RECT& target)
{
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }
    if (IsZoomed(window))
    {
        ShowWindow(window, SW_RESTORE);
    }
    SetWindowPos(
        window,
        HWND_TOP,
        target.left,
        target.top,
        std::max<LONG>(160, target.right - target.left),
        std::max<LONG>(120, target.bottom - target.top),
        SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
}

void LaunchExternal(HWND owner, const WorkspaceLaunchEntry& entry)
{
    if (entry.target.empty())
    {
        return;
    }
    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_ASYNCOK | SEE_MASK_FLAG_NO_UI;
    execution.hwnd = owner;
    execution.lpVerb = L"open";
    execution.lpFile = entry.target.c_str();
    execution.lpParameters = entry.arguments.empty() ? nullptr : entry.arguments.c_str();
    execution.nShow = SW_SHOWNORMAL;
    (void)ShellExecuteExW(&execution);
    if (execution.hProcess != nullptr)
    {
        CloseHandle(execution.hProcess);
    }
}
}

WorkspaceSnapshot NativeWorkspaceLayoutEngine::Capture(
    CloudOSNativeWindowManager& manager,
    NativeWorkspaceStudioStore& store,
    int workspace,
    const std::wstring& name)
{
    WorkspaceSnapshot snapshot{};
    snapshot.id = store.NextSnapshotId();
    snapshot.workspace = std::clamp(workspace, 0, kWorkspaceStudioCount - 1);
    snapshot.name = name.empty()
        ? L"Layout " + std::to_wstring(snapshot.id)
        : name;
    snapshot.created_filetime = FileTimeNow();

    for (const auto& item : WindowsForWorkspace(manager, snapshot.workspace))
    {
        RECT bounds{};
        if (!GetWindowRect(item.hwnd, &bounds))
        {
            continue;
        }
        const HMONITOR monitor = MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO info{};
        info.cbSize = sizeof(info);
        if (monitor == nullptr || !GetMonitorInfoW(monitor, &info))
        {
            continue;
        }

        const WorkspaceWindowIdentity identity =
            NativeWorkspaceAutomationEngine::IdentifyWindow(item.hwnd, item.process_id);
        WorkspaceLayoutWindow saved{};
        saved.process_name = identity.process_name;
        saved.window_class = identity.window_class;
        saved.title_hint = identity.window_title.substr(0, std::min<std::size_t>(identity.window_title.size(), 48));
        saved.monitor_device = MonitorDeviceName(monitor);
        saved.normalized_bounds = NormalizeBounds(bounds, info.rcWork);
        saved.floating = item.floating;

        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        if (GetWindowPlacement(item.hwnd, &placement))
        {
            saved.show_command = placement.showCmd;
        }
        snapshot.windows.push_back(std::move(saved));
    }
    return snapshot;
}

bool NativeWorkspaceLayoutEngine::Restore(
    CloudOSNativeWindowManager& manager,
    const WorkspaceSnapshot& snapshot)
{
    if (snapshot.workspace < 0 || snapshot.workspace >= kWorkspaceStudioCount ||
        snapshot.workspace != manager.CurrentWorkspace())
    {
        return false;
    }

    auto windows = WindowsForWorkspace(manager, snapshot.workspace);
    std::unordered_set<HWND> consumed;
    std::size_t restored = 0;

    for (const auto& saved : snapshot.windows)
    {
        HWND match = nullptr;
        for (const auto& candidate : windows)
        {
            if (consumed.contains(candidate.hwnd))
            {
                continue;
            }
            const auto identity =
                NativeWorkspaceAutomationEngine::IdentifyWindow(candidate.hwnd, candidate.process_id);
            if (IdentityMatchesSnapshot(identity, saved))
            {
                match = candidate.hwnd;
                break;
            }
        }
        if (match == nullptr)
        {
            continue;
        }

        consumed.insert(match);
        const RECT work = MonitorWorkAreaByDevice(saved.monitor_device, match);
        const RECT target = DenormalizeBounds(saved.normalized_bounds, work);
        manager.SetWindowFloating(match, saved.floating);
        PositionWindow(match, target);
        if (saved.show_command == SW_SHOWMAXIMIZED || saved.show_command == SW_MAXIMIZE)
        {
            ShowWindow(match, SW_MAXIMIZE);
        }
        else if (saved.show_command == SW_SHOWMINIMIZED || saved.show_command == SW_MINIMIZE)
        {
            ShowWindow(match, SW_MINIMIZE);
        }
        ++restored;
    }
    return restored != 0;
}

void NativeWorkspaceLayoutEngine::ApplyPreset(
    CloudOSNativeWindowManager& manager,
    int workspace,
    WorkspaceLayoutPreset preset)
{
    workspace = std::clamp(workspace, 0, kWorkspaceStudioCount - 1);
    if (workspace != manager.CurrentWorkspace())
    {
        return;
    }

    auto windows = WindowsForWorkspace(manager, workspace);
    if (windows.empty())
    {
        return;
    }

    if (preset == WorkspaceLayoutPreset::Free)
    {
        manager.SetTilingEnabled(false);
        return;
    }

    if (preset == WorkspaceLayoutPreset::MasterStack)
    {
        for (const auto& item : windows)
        {
            manager.SetWindowFloating(item.hwnd, false);
        }
        manager.SetTilingEnabled(true);
        manager.TileCurrentWorkspace();
        return;
    }

    manager.SetTilingEnabled(false);
    for (const auto& item : windows)
    {
        manager.SetWindowFloating(item.hwnd, true);
    }

    const RECT work = MonitorWorkAreaByDevice({}, windows.front().hwnd);
    const LONG width = std::max<LONG>(1, work.right - work.left);
    const LONG height = std::max<LONG>(1, work.bottom - work.top);
    const std::size_t count = windows.size();

    if (preset == WorkspaceLayoutPreset::Focus)
    {
        for (std::size_t index = 0; index < count; ++index)
        {
            RECT target = work;
            if (index == 0)
            {
                const LONG inset_x = width / 12;
                const LONG inset_y = height / 12;
                target.left += inset_x;
                target.right -= inset_x;
                target.top += inset_y;
                target.bottom -= inset_y;
                PositionWindow(windows[index].hwnd, target);
            }
            else
            {
                ShowWindow(windows[index].hwnd, SW_MINIMIZE);
            }
        }
        return;
    }

    if (preset == WorkspaceLayoutPreset::Columns)
    {
        const LONG column_width = width / static_cast<LONG>(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            RECT target = work;
            target.left = work.left + static_cast<LONG>(index) * column_width;
            target.right = index + 1 == count ? work.right : target.left + column_width;
            PositionWindow(windows[index].hwnd, target);
        }
        return;
    }

    const std::size_t columns = count <= 2
        ? count
        : static_cast<std::size_t>(std::ceil(std::sqrt(static_cast<double>(count))));
    const std::size_t rows = (count + columns - 1) / columns;
    const LONG cell_width = width / static_cast<LONG>(std::max<std::size_t>(1, columns));
    const LONG cell_height = height / static_cast<LONG>(std::max<std::size_t>(1, rows));
    for (std::size_t index = 0; index < count; ++index)
    {
        const std::size_t column = index % columns;
        const std::size_t row = index / columns;
        RECT target{};
        target.left = work.left + static_cast<LONG>(column) * cell_width;
        target.top = work.top + static_cast<LONG>(row) * cell_height;
        target.right = column + 1 == columns ? work.right : target.left + cell_width;
        target.bottom = row + 1 == rows ? work.bottom : target.top + cell_height;
        PositionWindow(windows[index].hwnd, target);
    }
}

void NativeWorkspaceAutomationEngine::ResetRuntimeState()
{
    processed_windows_.clear();
    focus_history_.clear();
    startup_launched_.fill(false);
    last_workspace_ = -1;
    last_foreground_ = nullptr;
}

void NativeWorkspaceAutomationEngine::Tick(
    HINSTANCE instance,
    HWND owner,
    CloudOSNativeWindowManager& manager,
    NativeWorkspaceStudioStore& store)
{
    // The event-driven manager already owns the current window model.
    ApplyRulesToNewWindows(manager, store);
    TrackFocus(manager);

    const int workspace = manager.CurrentWorkspace();
    if (workspace != last_workspace_)
    {
        HandleWorkspaceTransition(instance, owner, manager, store, workspace);
        last_workspace_ = workspace;
    }

    std::unordered_set<HWND> live;
    for (const auto& item : manager.AllManagedWindows())
    {
        if (item.hwnd != nullptr && IsWindow(item.hwnd))
        {
            live.insert(item.hwnd);
        }
    }
    for (auto iterator = processed_windows_.begin(); iterator != processed_windows_.end();)
    {
        if (!live.contains(iterator->first))
        {
            iterator = processed_windows_.erase(iterator);
        }
        else
        {
            ++iterator;
        }
    }
}

void NativeWorkspaceAutomationEngine::ReapplyAllRules(
    CloudOSNativeWindowManager& manager,
    NativeWorkspaceStudioStore& store)
{
    processed_windows_.clear();
    ApplyRulesToNewWindows(manager, store);
}

void NativeWorkspaceAutomationEngine::LaunchWorkspaceEntries(
    HINSTANCE instance,
    HWND owner,
    int workspace,
    NativeWorkspaceStudioStore& store)
{
    for (const auto& entry : store.LaunchEntries())
    {
        if (!entry.enabled || entry.workspace != workspace || entry.target.empty())
        {
            continue;
        }
        if (entry.cloudos_app)
        {
            NativeAppLauncher::LaunchById(instance, owner, entry.target);
        }
        else
        {
            LaunchExternal(owner, entry);
        }
    }
}

const std::vector<WorkspaceFocusRecord>& NativeWorkspaceAutomationEngine::FocusHistory() const noexcept
{
    return focus_history_;
}

void NativeWorkspaceAutomationEngine::ClearFocusHistory() noexcept
{
    focus_history_.clear();
}

bool NativeWorkspaceAutomationEngine::FocusHistoryItem(
    CloudOSNativeWindowManager& manager,
    std::size_t index)
{
    if (index >= focus_history_.size())
    {
        return false;
    }
    const WorkspaceFocusRecord record = focus_history_[index];
    if (record.hwnd == nullptr || !IsWindow(record.hwnd))
    {
        return false;
    }
    if (manager.CurrentWorkspace() != record.workspace)
    {
        manager.SwitchWorkspace(record.workspace);
    }
    manager.FocusWindow(record.hwnd);
    return true;
}

WorkspaceWindowIdentity NativeWorkspaceAutomationEngine::IdentifyWindow(HWND window, DWORD process_id)
{
    WorkspaceWindowIdentity identity{};
    identity.hwnd = window;
    identity.process_id = process_id;
    if (window == nullptr || !IsWindow(window))
    {
        return identity;
    }
    if (identity.process_id == 0)
    {
        GetWindowThreadProcessId(window, &identity.process_id);
    }

    wchar_t title[1024]{};
    GetWindowTextW(window, title, static_cast<int>(std::size(title)));
    identity.window_title = title;

    wchar_t class_name[256]{};
    GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
    identity.window_class = class_name;

    if (identity.process_id != 0)
    {
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, identity.process_id);
        if (process != nullptr)
        {
            std::array<wchar_t, 32768> path{};
            DWORD length = static_cast<DWORD>(path.size());
            if (QueryFullProcessImageNameW(process, 0, path.data(), &length))
            {
                identity.process_name = BaseName(std::wstring(path.data(), length));
            }
            CloseHandle(process);
        }
    }
    return identity;
}

bool NativeWorkspaceAutomationEngine::RuleMatches(
    const WorkspaceRule& rule,
    const WorkspaceWindowIdentity& identity)
{
    if (!rule.enabled || rule.pattern.empty())
    {
        return false;
    }

    std::wstring candidate;
    switch (rule.field)
    {
    case WorkspaceMatchField::WindowTitle:
        candidate = identity.window_title;
        break;
    case WorkspaceMatchField::WindowClass:
        candidate = identity.window_class;
        break;
    case WorkspaceMatchField::ProcessName:
    default:
        candidate = identity.process_name;
        break;
    }

    const std::wstring pattern = Lower(rule.pattern);
    candidate = Lower(candidate);
    switch (rule.mode)
    {
    case WorkspaceMatchMode::Exact:
        return candidate == pattern;
    case WorkspaceMatchMode::Prefix:
        return candidate.size() >= pattern.size() && candidate.compare(0, pattern.size(), pattern) == 0;
    case WorkspaceMatchMode::Wildcard:
        return WildcardMatch(pattern, candidate);
    case WorkspaceMatchMode::Contains:
    default:
        return candidate.find(pattern) != std::wstring::npos;
    }
}

void NativeWorkspaceAutomationEngine::ApplyRulesToNewWindows(
    CloudOSNativeWindowManager& manager,
    NativeWorkspaceStudioStore& store)
{
    const std::uint64_t now = FileTimeNow();
    for (const auto& item : manager.AllManagedWindows())
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd) || processed_windows_.contains(item.hwnd))
        {
            continue;
        }
        const auto identity = IdentifyWindow(item.hwnd, item.process_id);
        for (const auto& rule : store.Rules())
        {
            if (RuleMatches(rule, identity))
            {
                ApplyRule(manager, rule, identity);
                break;
            }
        }
        processed_windows_[item.hwnd] = now;
    }
}

void NativeWorkspaceAutomationEngine::HandleWorkspaceTransition(
    HINSTANCE instance,
    HWND owner,
    CloudOSNativeWindowManager& manager,
    NativeWorkspaceStudioStore& store,
    int workspace)
{
    if (workspace < 0 || workspace >= kWorkspaceStudioCount)
    {
        return;
    }
    const WorkspaceProfile& profile = store.Profiles()[static_cast<std::size_t>(workspace)];
    if (profile.apply_wallpaper && !profile.wallpaper_path.empty())
    {
        (void)NativeWallpaperManager::Apply(profile.wallpaper_path);
    }

    if (profile.auto_tile || profile.layout != WorkspaceLayoutPreset::Free)
    {
        NativeWorkspaceLayoutEngine::ApplyPreset(manager, workspace, profile.layout);
    }
    else
    {
        manager.SetTilingEnabled(false);
    }

    if (profile.auto_launch && !startup_launched_[static_cast<std::size_t>(workspace)])
    {
        startup_launched_[static_cast<std::size_t>(workspace)] = true;
        LaunchWorkspaceEntries(instance, owner, workspace, store);
    }
}

void NativeWorkspaceAutomationEngine::TrackFocus(CloudOSNativeWindowManager& manager)
{
    const HWND foreground = GetForegroundWindow();
    if (foreground == nullptr || foreground == last_foreground_)
    {
        return;
    }
    last_foreground_ = foreground;
    const int workspace = manager.WorkspaceFor(foreground);
    if (workspace < 0)
    {
        return;
    }

    DWORD process_id = 0;
    GetWindowThreadProcessId(foreground, &process_id);
    const auto identity = IdentifyWindow(foreground, process_id);
    focus_history_.erase(
        std::remove_if(
            focus_history_.begin(),
            focus_history_.end(),
            [foreground](const WorkspaceFocusRecord& record)
            {
                return record.hwnd == foreground;
            }),
        focus_history_.end());

    WorkspaceFocusRecord record{};
    record.hwnd = foreground;
    record.process_id = process_id;
    record.workspace = workspace;
    record.process_name = identity.process_name;
    record.title = identity.window_title;
    record.touched_filetime = FileTimeNow();
    focus_history_.insert(focus_history_.begin(), std::move(record));
    if (focus_history_.size() > 64)
    {
        focus_history_.resize(64);
    }
}

void NativeWorkspaceAutomationEngine::ApplyRule(
    CloudOSNativeWindowManager& manager,
    const WorkspaceRule& rule,
    const WorkspaceWindowIdentity& identity)
{
    if (identity.hwnd == nullptr || !IsWindow(identity.hwnd))
    {
        return;
    }
    const int workspace = std::clamp(rule.workspace, 0, kWorkspaceStudioCount - 1);
    manager.SetWindowFloating(identity.hwnd, rule.floating);
    manager.MoveWindowToWorkspace(identity.hwnd, workspace);
    if (rule.maximize && workspace == manager.CurrentWorkspace() && IsWindow(identity.hwnd))
    {
        ShowWindow(identity.hwnd, SW_MAXIMIZE);
    }
}
} // namespace CloudOS
