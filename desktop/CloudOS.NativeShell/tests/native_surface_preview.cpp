// Standalone QA host. Uses production components without starting the shell,
// AppBar, window manager, watchdog or recovery, and never terminates CloudOS.
#include "../src/native_theme.h"
#include "../src/native_flyout_layout.h"
#include "../src/native_notification_center.h"
#include "../src/native_quick_settings_window.h"
#include "../src/native_start_menu_window.h"
#include "../src/native_desktop_window.h"
#include "../src/native_popup_menu.h"
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include "../src/native_render_cache_v12.h"

namespace CloudOS
{
class NativeSurfacePreview
{
    static LRESULT CALLBACK PreviewProc(HWND window, UINT message, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR)
    {
        if (message == WM_ACTIVATE && LOWORD(wp) == WA_INACTIVE) return 0;
        if (message == WM_CLOSE) { DestroyWindow(window); PostQuitMessage(0); return 0; }
        if (message == WM_NCDESTROY) RemoveWindowSubclass(window, PreviewProc, id);
        return DefSubclassProc(window, message, wp, lp);
    }
    static int Assertions()
    {
        int checks = 0;
        for (const RECT work : {RECT{0, 0, 1920, 1040}, RECT{-1920, -200, 0, 880}, RECT{0, 0, 800, 560}})
        for (int dpi : {96, 120, 144, 192, 288})
        for (const SIZE requested : {SIZE{560, 820}, SIZE{720, 660}, SIZE{480, 620}})
        {
            const RECT anchor{work.left, work.bottom, work.right, work.bottom + 64};
            const RECT fit = FitFlyout(anchor, work, Scale(requested.cx, dpi), Scale(requested.cy, dpi), Scale(12, dpi));
            if (fit.left < work.left || fit.top < work.top || fit.right > work.right || fit.bottom > work.bottom || fit.right <= fit.left || fit.bottom <= fit.top) return 1;
            ++checks;
        }
        NativeScrollState scroll;
        scroll.extent = 900; scroll.page = 400; scroll.position = 1000; scroll.Clamp();
        if (scroll.position != 500) return 2;
        scroll.position = -100; scroll.Clamp(); if (scroll.position != 0) return 3;
        scroll.page = 1200; scroll.position = 50; scroll.Clamp(); if (scroll.position != 0) return 4;

        HWND button = CreateWindowW(L"BUTTON", L"Teste", WS_POPUP | BS_OWNERDRAW, 0, 0, 140, 40, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
        HDC screen = GetDC(nullptr), dc = CreateCompatibleDC(screen);
        HBITMAP bitmap = CreateCompatibleBitmap(screen, 140, 40); auto old = SelectObject(dc, bitmap);
        DRAWITEMSTRUCT item{}; item.CtlType = ODT_BUTTON; item.hwndItem = button; item.hDC = dc; item.rcItem = {0,0,140,40};
        for (auto tone : {WebSkin::ButtonTone::Neutral, WebSkin::ButtonTone::Accent, WebSkin::ButtonTone::Danger})
        {
            FillRect(dc, &item.rcItem, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
            const bool painted = WebSkin::PaintOwnerDrawButton(&item, tone);
            if (!painted) return 5;
            for(POINT point : {POINT{0,0},POINT{139,0},POINT{0,39},POINT{139,39}})
                if(GetPixel(dc,point.x,point.y)!=WebSkin::BgPrimary) { std::printf("FAIL button corner color %lu expected %lu\n",GetPixel(dc,point.x,point.y),WebSkin::BgPrimary); return 8; }
        }
        SelectObject(dc, old); DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr, screen); DestroyWindow(button);
        CloudOSNativeNotificationCenter notifications;
        if (!notifications.Create(GetModuleHandleW(nullptr))) return 6;
        CloudOSNativeNotificationCenter::Post(L"Teste de layout", L"Mensagem completa preservada para leitores de tela.");
        notifications.RebuildList();
        RECT row{};
        if (!ListView_GetItemRect(notifications.list_, 0, &row, LVIR_BOUNDS) || row.right <= row.left || row.bottom-row.top < Scale(100,GetDpiForWindow(notifications.window_))) return 7;
        std::printf("Notification row: %ld,%ld,%ld,%ld\n", row.left, row.top, row.right, row.bottom);
        HWND buffer_window=CreateWindowW(L"STATIC",L"V12 buffer fixture",WS_POPUP,0,0,320,240,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
        HDC target=GetDC(buffer_window);
        const auto allocations=PerformanceV12::state->counters[PerformanceV12::BackbufferAllocation];
        HDC first=NativeBackbufferV12::Acquire(buffer_window,target,320,240);
        for(int frame=0;frame<100;++frame) if(NativeBackbufferV12::Acquire(buffer_window,target,320,240)!=first) return 9;
        if(!first || PerformanceV12::state->counters[PerformanceV12::BackbufferAllocation]!=allocations+1) return 14;
        if(!NativeBackbufferV12::Acquire(buffer_window,target,480,300) || PerformanceV12::state->counters[PerformanceV12::BackbufferAllocation]!=allocations+2) return 15;
        ReleaseDC(buffer_window,target); DestroyWindow(buffer_window);
        CloudOSNativeStartMenuWindow start;
        if (!start.Create(GetModuleHandleW(nullptr))) return 23;
        for (int width : {390, 640})
        {
            const UINT dpi = GetDpiForWindow(start.window_);
            SetWindowPos(start.window_, nullptr, 0, 0, Scale(width,dpi), Scale(540,dpi), SWP_NOZORDER|SWP_NOACTIVATE);
            start.Layout();
            RECT command{}, power{}, label{}, overlap{};
            GetWindowRect(start.command_button_, &command); GetWindowRect(start.power_button_, &power);
            GetWindowRect(start.footer_label_, &label);
            if (command.right > power.left || command.right-command.left < Scale(120,dpi)) return 24;
            if ((GetWindowLongPtrW(start.footer_label_,GWL_STYLE)&WS_VISIBLE) && IntersectRect(&overlap,&label,&command)) return 25;
            if (start.HomePointVisibleV12(POINT{Scale(40,dpi),Scale(30,dpi)})) return 26;
        }
        start.Destroy();
        std::printf("PASS: Start footer controls do not overlap at compact/normal widths; clipped grid does not receive header clicks.\n");
        wchar_t temporary[MAX_PATH]{}; GetTempPathW(MAX_PATH,temporary);
        const auto directory=std::filesystem::path(temporary)/(L"CloudOS-V12-fixture-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64()));
        if(!std::filesystem::create_directory(directory)) return 16;
        const auto scans=PerformanceV12::state->counters[PerformanceV12::FilesystemScan];
        NativeDesktopModelV12 model; model.Start(nullptr,directory.wstring());
        auto await=[&](const std::function<bool()>& condition) {
            const auto deadline=GetTickCount64()+5000;
            while(GetTickCount64()<deadline) { if(condition()) return true; Sleep(20); }
            return false;
        };
        if(!await([&]{return PerformanceV12::state->counters[PerformanceV12::FilesystemScan]>scans;})) return 17;
        { std::ofstream file(directory/L"first.txt"); file<<"fixture"; }
        if(!await([&]{return model.Snapshot().size()==1;})) return 18;
        std::filesystem::rename(directory/L"first.txt",directory/L"renamed.txt");
        if(!await([&]{auto items=model.Snapshot();return items.size()==1 && items[0].name==L"renamed.txt";})) return 19;
        std::filesystem::remove(directory/L"renamed.txt");
        if(!await([&]{return model.Snapshot().empty();})) return 21;
        model.Stop(); std::filesystem::remove(directory);
        std::printf("PASS: backbuffer reused 100 times; one resize allocation; Desktop watcher create/rename/delete delivered.\n");
        std::printf("PASS: %d monitor/DPI geometry cases, scroll limits and owner-drawn button corner pixels.\n", checks);
        return 0;
    }
public:
    static int Run(HINSTANCE instance, const std::wstring& command)
    {
        if (command.find(L"--test") != std::wstring::npos) return Assertions();
        if (command.find(L"--benchmark") != std::wstring::npos)
        {
            CloudOSNativeDesktopWindow surface;
            if (!surface.Create(instance, nullptr)) return 20;
            SetWindowPos(surface.hwnd_, HWND_BOTTOM, 0, 0, 3840, 2160, SWP_NOACTIVATE | SWP_SHOWWINDOW);
            surface.Redraw(); UpdateWindow(surface.hwnd_);
            LARGE_INTEGER frequency{}, begin{}, end{};
            QueryPerformanceFrequency(&frequency);
            const DWORD handles = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
            QueryPerformanceCounter(&begin);
            for (int frame = 0; frame < 60; ++frame)
            {
                SendMessageW(surface.hwnd_, WM_TIMER, kMetricsTimer, 0);
                surface.Redraw(); UpdateWindow(surface.hwnd_);
            }
            QueryPerformanceCounter(&end);
            const DWORD final_handles = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
            std::printf("Desktop 3840x2160: 60 forced paint frames, %.2f ms/frame, GDI objects %lu -> %lu. Persistent backbuffer.\n",
                (end.QuadPart - begin.QuadPart) * 1000.0 / frequency.QuadPart / 60.0, handles, final_handles);
            return final_handles <= handles + 4 ? 0 : 22;
        }
        CloudOSNativeNotificationCenter notifications;
        CloudOSNativeQuickSettingsWindow quick;
        CloudOSNativeStartMenuWindow start;
        CloudOSNativeDesktopWindow desktop;
        HWND window{};
        int width = 440, height = 580;
        if (command.find(L"--quick") != std::wstring::npos)
        {
            if (!quick.Create(instance)) return 10;
            window = quick.window_; width = 420; height = 620;
            RECT anchor{0,960,1920,1024}; quick.ShowNear(anchor);
        }
        else if (command.find(L"--start") != std::wstring::npos)
        {
            if (!start.Create(instance)) return 11;
            RECT anchor{0, 960, 1920, 1024}; start.ShowNear(anchor);
            window = start.window_; width = 640; height = 680;
        }
        else if (command.find(L"--desktop") != std::wstring::npos)
        {
            if (!desktop.Create(instance, nullptr)) return 12;
            window = desktop.hwnd_; width = 1800; height = 1000;

        }
        else
        {
            if (!notifications.Create(instance)) return 13;
            CloudOSNativeNotificationCenter::Post(L"CloudOS pronto", L"Seus aplicativos e areas de trabalho estao disponiveis. Abra o Start para continuar.");
            CloudOSNativeNotificationCenter::Post(L"Dispositivo indisponivel", L"O monitor nao oferece controle de brilho por software. Use os botoes do monitor para ajustar a iluminacao.", 1);
            CloudOSNativeNotificationCenter::Post(L"Continuidade restaurada", L"Area 1: suas janelas foram restauradas. Esta mensagem de teste verifica quebra de linha, navegacao por teclado e leitura do conteudo completo.");
            notifications.RebuildList(); window = notifications.window_;
        }
        if (command.find(L"--compact") != std::wstring::npos) { width = 390; height = 540; }
        // Preview-only conversion: these are our own component HWNDs, not apps
        // embedded into the shell. Production retains its popup semantics.
        SetWindowSubclass(window, PreviewProc, 0x515041, 0);
        // An owned test dialog is excluded from normal application tiling by
        // the live shell. Ownership does not embed/reparent its client area.
        HWND owner = CreateWindowW(L"STATIC", L"CloudOS QA host", WS_OVERLAPPEDWINDOW,
            70, 70, 500, 640, nullptr, nullptr, instance, nullptr);
        EnableWindow(owner, FALSE);
        ShowWindow(owner, SW_SHOWNOACTIVATE);
        SetWindowLongPtrW(window, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
        SetWindowLongPtrW(window, GWL_EXSTYLE, 0);
        SetWindowLongPtrW(window, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_VSCROLL);
        SetWindowTextW(window, L"CloudOS - validacao visual nativa");
        const UINT dpi = GetDpiForWindow(window);
        RECT frame{0, 0, Scale(width, dpi), Scale(height, dpi)};
        AdjustWindowRectExForDpi(&frame, static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE)), FALSE, 0, dpi);
        SetWindowPos(window, HWND_NOTOPMOST, 80, 80, frame.right - frame.left, frame.bottom - frame.top, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        ShowWindow(window, SW_SHOWNORMAL);
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0) { if(quick.Translate(&message)) continue; TranslateMessage(&message); DispatchMessageW(&message); }
        return 0;
    }
};
}
int wmain(int argc, wchar_t** argv)
{
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    OleInitialize(nullptr);
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_WIN95_CLASSES}; InitCommonControlsEx(&controls);
    Gdiplus::GdiplusStartupInput input; ULONG_PTR token{}; Gdiplus::GdiplusStartup(&token, &input, nullptr);
    std::wstring command;
    for (int index = 1; index < argc; ++index) { command += argv[index]; command += L' '; }
    const int result = CloudOS::NativeSurfacePreview::Run(GetModuleHandleW(nullptr), command);
    // Production services can own short-lived MTA work; process teardown ends
    // the preview without trying to tear down their static state underneath it.
    ExitProcess(static_cast<UINT>(result));
}
