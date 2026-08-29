#include <windows.h>
#include <gdiplus.h>
#include <commctrl.h>
#include <string>

#include "native_theme.h"
#include "native_window_manager.h"
#include "native_desktop_window.h"
#include "native_app_launcher.h"

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "comctl32.lib")

namespace CloudOS
{
class CloudOSApplication final
{
public:
    explicit CloudOSApplication(HINSTANCE instance) : instance_(instance) {}
    ~CloudOSApplication()
    {
        desktop_.Destroy();
        if (gdiplus_token_ != 0) Gdiplus::GdiplusShutdown(gdiplus_token_);
    }

    bool Initialize()
    {
        Gdiplus::GdiplusStartupInput gdiInput;
        Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiInput, nullptr);

        if (!desktop_.Create(instance_, &window_manager_)) return false;

        SetupCallbacks();
        Layout();

        window_manager_.SetReservedBottomPixels(Scale(kBottomBarHeight, 96) + 8);
        if (!window_manager_.Initialize(desktop_.Hwnd())) return false;

        RegisterHotKeys();
        SetTimer(desktop_.Hwnd(), kReconcileTimer, 1000, nullptr);
        SetTimer(desktop_.Hwnd(), kMetricsTimer, 1000, nullptr);
        desktop_.Redraw();

        return true;
    }

    int Run()
    {
        MSG msg{};
        while (GetMessageW(&msg, nullptr, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        return static_cast<int>(msg.wParam);
    }

private:
    void SetupCallbacks()
    {
        desktop_.SetActionCallback([this](int action_id) {
            if (action_id >= 1 && action_id <= static_cast<int>(kAllApps.size()))
            {
                NativeAppLauncher::Launch(instance_, desktop_.Hwnd(), kAllApps[static_cast<std::size_t>(action_id - 1)]);
            }
        });

        desktop_.SetHotKeyCallback([this](int hotkey_id) {
            HandleHotKey(hotkey_id);
        });

        desktop_.SetTimerCallback([this]() {
            window_manager_.Reconcile();
        });
    }

    void Layout()
    {
        RECT work_area{};
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
        desktop_.UpdateLayout(work_area);
    }

    void HandleHotKey(int id)
    {
        switch (id)
        {
        case HotTerminal: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"terminal"); break;
        case HotWslTerminal: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"projects"); break;
        case HotFiles: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"files"); break;
        case HotApps: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"apps"); break;
        case HotProcesses: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"sysmon"); break;
        case HotRun: NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"run"); break;
        case HotFocusNext: window_manager_.FocusNext(true); break;
        case HotClose: window_manager_.CloseActive(); break;
        case HotMinimize: window_manager_.MinimizeActive(); break;
        case HotExit: PostQuitMessage(0); break;
        default:
            if (id >= HotWorkspace1 && id <= HotWorkspace4)
            {
                window_manager_.SwitchWorkspace(id - HotWorkspace1);
            }
            break;
        }
    }

    void RegisterHotKeys()
    {
        HWND hwnd = desktop_.Hwnd();
        RegisterHotKey(hwnd, HotTerminal, MOD_ALT | MOD_NOREPEAT, 'T');
        RegisterHotKey(hwnd, HotWslTerminal, MOD_ALT | MOD_NOREPEAT, 'K');
        RegisterHotKey(hwnd, HotFiles, MOD_ALT | MOD_NOREPEAT, 'F');
        RegisterHotKey(hwnd, HotApps, MOD_ALT | MOD_NOREPEAT, 'A');
        RegisterHotKey(hwnd, HotProcesses, MOD_ALT | MOD_NOREPEAT, 'P');
        RegisterHotKey(hwnd, HotRun, MOD_ALT | MOD_NOREPEAT, 'R');
        RegisterHotKey(hwnd, HotFocusNext, MOD_ALT | MOD_NOREPEAT, 'J');
        RegisterHotKey(hwnd, HotClose, MOD_ALT | MOD_NOREPEAT, 'Q');
        RegisterHotKey(hwnd, HotMinimize, MOD_ALT | MOD_NOREPEAT, 'M');
        RegisterHotKey(hwnd, HotExit, MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'Q');

        RegisterHotKey(hwnd, HotWorkspace1, MOD_CONTROL | MOD_NOREPEAT, '1');
        RegisterHotKey(hwnd, HotWorkspace2, MOD_CONTROL | MOD_NOREPEAT, '2');
        RegisterHotKey(hwnd, HotWorkspace3, MOD_CONTROL | MOD_NOREPEAT, '3');
        RegisterHotKey(hwnd, HotWorkspace4, MOD_CONTROL | MOD_NOREPEAT, '4');
    }

    HINSTANCE instance_{};
    ULONG_PTR gdiplus_token_{0};
    CloudOSNativeWindowManager window_manager_;
    CloudOSNativeDesktopWindow desktop_;
};

} // namespace CloudOS

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool uninitialize_com = SUCCEEDED(hr);

    INITCOMMONCONTROLSEX icex{};
    icex.dwSize = sizeof(icex);
    icex.dwICC = ICC_WIN95_CLASSES | ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icex);

    CloudOS::CloudOSApplication app(instance);
    if (!app.Initialize())
    {
        if (uninitialize_com) CoUninitialize();
        MessageBoxW(nullptr, L"O CloudOS Native nao conseguiu inicializar o shell Win32.", L"CloudOS Native", MB_OK | MB_ICONERROR);
        return 1;
    }

    const int exit_code = app.Run();
    if (uninitialize_com) CoUninitialize();
    return exit_code;
}
