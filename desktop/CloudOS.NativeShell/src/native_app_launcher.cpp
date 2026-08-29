#include "native_app_launcher.h"
#include "native_terminal_window.h"
#include "native_files_window.h"
#include "native_notepad_window.h"
#include "native_calculator_window.h"
#include "native_system_monitor_window.h"
#include "native_settings_window.h"
#include "native_apps_window.h"
#include "native_run_window.h"

namespace CloudOS
{

void NativeAppLauncher::Launch(HINSTANCE instance, HWND parent_hwnd, const AppItem& app)
{
    LaunchById(instance, parent_hwnd, app.id);
}

void NativeAppLauncher::LaunchById(HINSTANCE instance, HWND parent_hwnd, const std::wstring& id)
{
    (void)parent_hwnd;

    if (id == L"terminal" || id == L"comms")
    {
        CloudOSNativeTerminalWindow::Open(instance, L"cmd.exe", L"Comms Hub - Terminal ConPTY");
    }
    else if (id == L"projects" || id == L"wsl")
    {
        CloudOSNativeTerminalWindow::Open(instance, L"wsl.exe -d kali-linux", L"Orion Projects - WSL2 Kali Linux");
    }
    else if (id == L"powershell")
    {
        CloudOSNativeTerminalWindow::Open(instance, L"powershell.exe", L"Quantum Shell - PowerShell");
    }
    else if (id == L"files")
    {
        CloudOSNativeFilesWindow::Open(instance);
    }
    else if (id == L"drive")
    {
        ShellExecuteW(nullptr, L"open", L"explorer.exe", L"C:\\", nullptr, SW_SHOWNORMAL);
    }
    else if (id == L"notepad" || id == L"mail")
    {
        CloudOSNativeNotepadWindow::Open(instance);
    }
    else if (id == L"code")
    {
        if (reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", L"code.cmd", L".", nullptr, SW_SHOWNORMAL)) <= 32)
        {
            CloudOSNativeNotepadWindow::Open(instance);
        }
    }
    else if (id == L"calc")
    {
        CloudOSNativeCalculatorWindow::Open(instance);
    }
    else if (id == L"sysmon")
    {
        CloudOSNativeSystemMonitorWindow::Open(instance);
    }
    else if (id == L"settings")
    {
        CloudOSNativeSettingsWindow::Open(instance);
    }
    else if (id == L"apps" || id == L"more")
    {
        CloudOSNativeAppsWindow::Open(instance);
    }
    else if (id == L"run")
    {
        CloudOSNativeRunWindow::Open(instance);
    }
    else if (id == L"browser")
    {
        ShellExecuteW(nullptr, L"open", L"https://google.com", nullptr, nullptr, SW_SHOWNORMAL);
    }
    else if (id == L"paint")
    {
        ShellExecuteW(nullptr, L"open", L"mspaint.exe", nullptr, nullptr, SW_SHOWNORMAL);
    }
    else if (id == L"media")
    {
        ShellExecuteW(nullptr, L"open", L"wmplayer.exe", nullptr, nullptr, SW_SHOWNORMAL);
    }
    else if (id == L"regedit")
    {
        ShellExecuteW(nullptr, L"open", L"regedit.exe", nullptr, nullptr, SW_SHOWNORMAL);
    }
    else if (id == L"snip")
    {
        ShellExecuteW(nullptr, L"open", L"SnippingTool.exe", nullptr, nullptr, SW_SHOWNORMAL);
    }
}

void NativeAppLauncher::ShowQuickPowerMenu(HWND parent_hwnd, POINT screen_pt)
{
    HMENU menu = CreatePopupMenu();
    InsertMenuW(menu, 0, MF_BYPOSITION | MF_STRING, 1001, L"🔒 Bloquear Estação");
    InsertMenuW(menu, 1, MF_BYPOSITION | MF_STRING, 1002, L"⚙ Configurações do Sistema");
    InsertMenuW(menu, 2, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
    InsertMenuW(menu, 3, MF_BYPOSITION | MF_STRING, 1003, L"🔄 Reiniciar Sessão");
    InsertMenuW(menu, 4, MF_BYPOSITION | MF_STRING, 1004, L"⏻ Encerrar CloudOS");

    SetForegroundWindow(parent_hwnd);
    int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_BOTTOMALIGN, screen_pt.x, screen_pt.y, 0, parent_hwnd, nullptr);
    DestroyMenu(menu);

    switch (cmd)
    {
    case 1001: LockWorkStation(); break;
    case 1002: ShellExecuteW(nullptr, L"open", L"control.exe", nullptr, nullptr, SW_SHOWNORMAL); break;
    case 1003: InvalidateRect(parent_hwnd, nullptr, TRUE); break;
    case 1004: PostQuitMessage(0); break;
    default: break;
    }
}

} // namespace CloudOS
