#include <dwmapi.h>
#include <iostream>
#include <array>
#include <string_view>
#include <algorithm>
#pragma comment(lib, "dwmapi.lib")

constexpr DWORD kExcludedStyles = WS_DISABLED;

bool IsCloaked(HWND window) noexcept {
    DWORD cloaked = 0;
    HRESULT hr = DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
    return SUCCEEDED(hr) && cloaked != 0;
}

bool IsExcludedClass(HWND window) {
    wchar_t buffer[256]{};
    int length = GetClassNameW(window, buffer, 256);
    if (length <= 0) return false;
    std::wstring_view class_name(buffer, length);
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

std::wstring ReadWindowTitle(HWND window) {
    int length = GetWindowTextLengthW(window);
    if (length <= 0) return {};
    std::wstring title(length + 1, L'\0');
    int copied = GetWindowTextW(window, title.data(), (int)title.size());
    if (copied <= 0) return {};
    title.resize(copied);
    return title;
}

bool IsManageable(HWND window, DWORD process_id, bool require_visible, std::string& reason) {
    if (window == nullptr) { reason = "null"; return false; }
    if (!IsWindow(window)) { reason = "!IsWindow"; return false; }
    if (process_id == 0) { reason = "pid 0"; return false; }
    if (GetAncestor(window, GA_ROOT) != window) { reason = "!GA_ROOT"; return false; }
    if (require_visible && !IsWindowVisible(window)) { reason = "!visible"; return false; }

    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & kExcludedStyles) != 0) { reason = "disabled"; return false; }
    if ((extended_style & WS_EX_TOOLWINDOW) != 0) { reason = "toolwindow"; return false; }
    if (IsCloaked(window)) { reason = "cloaked"; return false; }

    HWND owner = GetWindow(window, GW_OWNER);
    if (owner != nullptr && (extended_style & WS_EX_APPWINDOW) == 0) {
        reason = "has_owner_no_appwindow";
        return false;
    }

    if (IsExcludedClass(window)) { reason = "excluded_class"; return false; }

    std::wstring title = ReadWindowTitle(window);
    if (title.empty()) { reason = "empty_title"; return false; }

    RECT bounds{};
    if (!GetWindowRect(window, &bounds) || (bounds.right - bounds.left) < 32 || (bounds.bottom - bounds.top) < 32) {
        reason = "bounds < 32";
        return false;
    }

    reason = "OK";
    return true;
}

BOOL CALLBACK DirectEnum(HWND hwnd, LPARAM lParam) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    wchar_t title[256]{};
    GetWindowTextW(hwnd, title, 256);
    if (title[0] == L'\0') return TRUE;

    std::string reason;
    bool ok = IsManageable(hwnd, pid, true, reason);
    std::wcout << L"HWND=" << hwnd << L" PID=" << pid << L" Result=" << (ok ? L"PASS" : L"FAIL")
               << L" Reason=" << reason.c_str() << L" Title=" << title << std::endl;
    return TRUE;
}

int main() {
    HWND dummy = CreateWindowExW(0, L"STATIC", L"dummy", 0, 0, 0, 0, 0, nullptr, nullptr, nullptr, nullptr);
    std::cout << "Dummy window: " << dummy << std::endl;

    HWINSTA hwinsta = OpenWindowStationW(L"WinSta0", FALSE, MAXIMUM_ALLOWED);
    if (hwinsta) SetProcessWindowStation(hwinsta);
    HDESK hdesk = OpenDesktopW(L"Default", 0, FALSE, MAXIMUM_ALLOWED);
    std::cout << "OpenDesktop: " << hdesk << std::endl;

    if (hdesk) {
        std::cout << "Testing EnumDesktopWindows on Default:" << std::endl;
        EnumDesktopWindows(hdesk, &DirectEnum, 0);
        CloseDesktop(hdesk);
    }
    return 0;
}
