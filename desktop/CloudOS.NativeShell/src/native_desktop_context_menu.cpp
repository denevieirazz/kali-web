#include "native_desktop_context_menu.h"

#include "native_app_launcher.h"
#include "native_file_operations_window.h"
#include "native_files_window.h"
#include "native_notification_center.h"
#include "native_session_continuity_service.h"
#include "native_terminal_window.h"
#include "native_wallpaper_manager.h"
#include "native_workspace_studio_service.h"

#include <shellapi.h>
#include <shlobj.h>

#include <array>
#include <string>

namespace CloudOS
{
namespace
{
constexpr UINT kNewFolder = 9101;
constexpr UINT kNewText = 9102;
constexpr UINT kOpenFiles = 9103;
constexpr UINT kOpenTerminal = 9104;
constexpr UINT kCommandCenter = 9105;
constexpr UINT kRefresh = 9106;
constexpr UINT kWallpaper = 9107;
constexpr UINT kResetWallpaper = 9108;
constexpr UINT kDisplaySettings = 9109;
constexpr UINT kPersonalization = 9110;
constexpr UINT kAutoArrange = 9111;
constexpr UINT kFileOperations = 9112;
constexpr UINT kWorkspaceStudio = 9113;
constexpr UINT kContinuityCenter = 9114;

std::wstring DesktopPath()
{
    PWSTR path = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DEFAULT, nullptr, &path)) || path == nullptr)
    {
        return {};
    }
    std::wstring result(path);
    CoTaskMemFree(path);
    return result;
}

std::wstring Join(const std::wstring& folder, const std::wstring& name)
{
    if (folder.empty())
    {
        return name;
    }
    std::wstring result = folder;
    if (result.back() != L'\\')
    {
        result.push_back(L'\\');
    }
    result += name;
    return result;
}

std::wstring UniquePath(
    const std::wstring& folder,
    const std::wstring& base,
    const std::wstring& extension)
{
    for (unsigned int index = 0; index < 1000; ++index)
    {
        std::wstring name = base;
        if (index != 0)
        {
            name += L" (";
            name += std::to_wstring(index + 1);
            name += L")";
        }
        name += extension;
        const std::wstring candidate = Join(folder, name);
        if (GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES)
        {
            return candidate;
        }
    }
    return {};
}

bool CreateFolder(HWND owner)
{
    const std::wstring desktop = DesktopPath();
    const std::wstring path = UniquePath(desktop, L"Nova pasta", L"");
    if (path.empty() || !CreateDirectoryW(path.c_str(), nullptr))
    {
        MessageBoxW(owner, L"Nao foi possivel criar a pasta na Area de Trabalho.", L"CloudOS", MB_OK | MB_ICONERROR);
        return false;
    }
    SHChangeNotify(SHCNE_MKDIR, SHCNF_PATHW, path.c_str(), nullptr);
    CloudOSNativeNotificationCenter::Post(L"Nova pasta", L"Pasta criada na Area de Trabalho.");
    return true;
}

bool CreateTextFile(HWND owner)
{
    const std::wstring desktop = DesktopPath();
    const std::wstring path = UniquePath(desktop, L"Novo Documento de Texto", L".txt");
    if (path.empty())
    {
        return false;
    }

    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_WRITE,
        FILE_SHARE_READ,
        nullptr,
        CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        MessageBoxW(owner, L"Nao foi possivel criar o arquivo de texto.", L"CloudOS", MB_OK | MB_ICONERROR);
        return false;
    }
    CloseHandle(file);
    SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW, path.c_str(), nullptr);
    CloudOSNativeNotificationCenter::Post(L"Novo arquivo", L"Documento de texto criado na Area de Trabalho.");
    return true;
}

void OpenTerminalAtDesktop(HINSTANCE instance)
{
    const std::wstring desktop = DesktopPath();
    std::wstring command = L"cmd.exe";
    if (!desktop.empty())
    {
        command += L" /K cd /d \"";
        command += desktop;
        command += L"\"";
    }
    CloudOSNativeTerminalWindow::Open(instance, command, L"Desktop - Terminal CloudOS");
}

void OpenSettings(HWND owner, const wchar_t* uri)
{
    (void)ShellExecuteW(owner, L"open", uri, nullptr, nullptr, SW_SHOWNORMAL);
}
}

bool NativeDesktopContextMenu::Show(
    HINSTANCE instance,
    HWND owner,
    POINT screen_point)
{
    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return false;
    }

    InsertMenuW(menu, 0, MF_BYPOSITION | MF_STRING, kNewFolder, L"Nova pasta");
    InsertMenuW(menu, 1, MF_BYPOSITION | MF_STRING, kNewText, L"Novo arquivo de texto");
    InsertMenuW(menu, 2, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
    InsertMenuW(menu, 3, MF_BYPOSITION | MF_STRING, kOpenFiles, L"Abrir Area de Trabalho em Arquivos");
    InsertMenuW(menu, 4, MF_BYPOSITION | MF_STRING, kFileOperations, L"Operacoes de arquivos / ZIP...");
    InsertMenuW(menu, 5, MF_BYPOSITION | MF_STRING, kOpenTerminal, L"Abrir no Terminal");
    InsertMenuW(menu, 6, MF_BYPOSITION | MF_STRING, kCommandCenter, L"Central de Comandos");
    InsertMenuW(menu, 7, MF_BYPOSITION | MF_STRING, kWorkspaceStudio, L"Workspace Studio...");
    InsertMenuW(menu, 8, MF_BYPOSITION | MF_STRING, kContinuityCenter, L"Central de Continuidade...");
    InsertMenuW(menu, 9, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
    InsertMenuW(menu, 10, MF_BYPOSITION | MF_STRING, kWallpaper, L"Mudar wallpaper...");
    InsertMenuW(menu, 11, MF_BYPOSITION | MF_STRING, kResetWallpaper, L"Restaurar wallpaper padrao");
    InsertMenuW(menu, 12, MF_BYPOSITION | MF_STRING, kDisplaySettings, L"Configuracoes de tela");
    InsertMenuW(menu, 13, MF_BYPOSITION | MF_STRING, kPersonalization, L"Personalizacao do Windows");
    InsertMenuW(menu, 14, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
    InsertMenuW(menu, 15, MF_BYPOSITION | MF_STRING | MF_CHECKED, kAutoArrange, L"Organizar icones automaticamente");
    InsertMenuW(menu, 16, MF_BYPOSITION | MF_STRING, kRefresh, L"Atualizar");

    SetForegroundWindow(owner);
    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_TOPALIGN,
        screen_point.x,
        screen_point.y,
        0,
        owner,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case kNewFolder:
        return CreateFolder(owner);
    case kNewText:
        return CreateTextFile(owner);
    case kOpenFiles:
    {
        const std::wstring desktop = DesktopPath();
        if (!desktop.empty())
        {
            CloudOSNativeFilesWindow::Open(instance, desktop);
        }
        return false;
    }
    case kFileOperations:
        CloudOSNativeFileOperationsWindow::Open(instance, DesktopPath());
        return false;
    case kOpenTerminal:
        OpenTerminalAtDesktop(instance);
        return false;
    case kCommandCenter:
        NativeAppLauncher::LaunchById(instance, owner, L"control");
        return false;
    case kWorkspaceStudio:
        NativeWorkspaceStudioService::Open(instance, owner);
        return false;
    case kContinuityCenter:
        NativeSessionContinuityService::Open(instance, owner);
        return false;
    case kWallpaper:
        return NativeWallpaperManager::PickAndApply(owner);
    case kResetWallpaper:
        NativeWallpaperManager::Reset();
        return true;
    case kDisplaySettings:
        OpenSettings(owner, L"ms-settings:display");
        return false;
    case kPersonalization:
        OpenSettings(owner, L"ms-settings:personalization");
        return false;
    case kAutoArrange:
    case kRefresh:
        return true;
    default:
        return false;
    }
}
} // namespace CloudOS
