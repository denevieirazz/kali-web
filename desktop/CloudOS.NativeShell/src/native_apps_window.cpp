#include "native_apps_window.h"

#include "native_calculator_window.h"
#include "native_env_doctor_window.h"
#include "native_integration_v16.h"
#include "native_notepad_window.h"
#include "native_settings_window.h"
#include "native_system_monitor_window.h"
#include "native_terminal_window.h"
#include "native_theme.h"

#include <commctrl.h>
#include <knownfolders.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <new>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Apps.v16";
constexpr int kSearchId = 1301;
constexpr int kListId = 1302;
constexpr int kLaunchId = 1303;
constexpr int kInstallId = 1304;
constexpr int kUninstallId = 1305;
constexpr int kRefreshId = 1306;
constexpr UINT kInstallWindows = 1;
constexpr UINT kInstallLinux = 2;

struct ProcessWindowSearch final
{
    DWORD process_id{};
    HWND window{};
};

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeAppsWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = CloudOS::WebSkin::SharedBackgroundBrush();
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring Trim(std::wstring value)
{
    const auto is_space = [](wchar_t ch)
    {
        return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n';
    };
    while (!value.empty() && is_space(value.front())) value.erase(value.begin());
    while (!value.empty() && is_space(value.back())) value.pop_back();
    return value;
}

std::wstring FileNameWithoutExtension(std::wstring path)
{
    const std::size_t separator = path.find_last_of(L"\\/");
    if (separator != std::wstring::npos) path = path.substr(separator + 1);
    const std::size_t extension = path.find_last_of(L'.');
    if (extension != std::wstring::npos) path.resize(extension);
    return path;
}

bool HasExtension(const std::wstring& path, const wchar_t* extension)
{
    const std::size_t extension_length = wcslen(extension);
    return path.size() >= extension_length &&
        _wcsicmp(path.c_str() + path.size() - extension_length, extension) == 0;
}

void AddSearchPathExecutable(
    std::vector<CloudOSNativeAppsWindow::AppEntry>& catalog,
    const wchar_t* executable,
    const wchar_t* display_name)
{
    std::array<wchar_t, 32768> buffer{};
    const DWORD length = SearchPathW(
        nullptr,
        executable,
        nullptr,
        static_cast<DWORD>(buffer.size()),
        buffer.data(),
        nullptr);
    if (length > 0 && length < buffer.size())
    {
        CloudOSNativeAppsWindow::AppEntry app{};
        app.name = display_name;
        app.path = buffer.data();
        app.kind = CloudOSNativeAppsWindow::AppKind::External;
        app.platform = L"Windows";
        app.source = L"Windows · PATH";
        app.can_launch = true;
        catalog.push_back(std::move(app));
    }
}

void ShowInternalLaunchError(HWND owner, const wchar_t* app_name)
{
    std::wstring message = L"O aplicativo nativo ";
    message += app_name;
    message += L" nao pode ser aberto.";
    MessageBoxW(owner, message.c_str(), L"CloudOS", MB_OK | MB_ICONERROR);
}

BOOL CALLBACK FindProcessWindow(HWND window, LPARAM parameter)
{
    auto* search = reinterpret_cast<ProcessWindowSearch*>(parameter);
    if (search == nullptr || search->window != nullptr) return FALSE;

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (process_id != search->process_id || !IsWindowVisible(window) || GetAncestor(window, GA_ROOT) != window)
        return TRUE;

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & WS_DISABLED) != 0 || (extended_style & WS_EX_TOOLWINDOW) != 0) return TRUE;

    RECT bounds{};
    if (!GetWindowRect(window, &bounds) || bounds.right - bounds.left < 32 || bounds.bottom - bounds.top < 32)
        return TRUE;

    search->window = window;
    return FALSE;
}

HWND FindTopLevelWindowForProcess(DWORD process_id)
{
    if (process_id == 0) return nullptr;
    ProcessWindowSearch search{};
    search.process_id = process_id;
    EnumWindows(&FindProcessWindow, reinterpret_cast<LPARAM>(&search));
    return search.window;
}

bool LaunchExternalApplication(HWND launcher, const std::wstring& path)
{
    if (path.empty()) return false;
    ShowWindow(launcher, SW_HIDE);

    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI | SEE_MASK_ASYNCOK;
    execution.hwnd = nullptr;
    execution.lpVerb = L"open";
    execution.lpFile = path.c_str();
    execution.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&execution))
    {
        ShowWindow(launcher, SW_SHOW);
        SetForegroundWindow(launcher);
        return false;
    }

    HWND target = nullptr;
    if (execution.hProcess != nullptr)
    {
        const DWORD process_id = GetProcessId(execution.hProcess);
        (void)WaitForInputIdle(execution.hProcess, 1500);
        for (int attempt = 0; attempt < 30 && target == nullptr; ++attempt)
        {
            target = FindTopLevelWindowForProcess(process_id);
            if (target == nullptr) Sleep(100);
        }
        CloseHandle(execution.hProcess);
    }

    if (target != nullptr)
    {
        ShowWindow(target, IsIconic(target) ? SW_RESTORE : SW_SHOW);
        BringWindowToTop(target);
        SetForegroundWindow(target);
    }
    return true;
}

CloudOS::UnifiedAppV16 ToUnified(const CloudOSNativeAppsWindow::AppEntry& app)
{
    CloudOS::UnifiedAppV16 result{};
    result.name = app.name;
    result.launch_target = app.path;
    result.source = app.source;
    result.uninstall_command = app.uninstall_command;
    result.distro = app.distro;
    result.desktop_id = app.desktop_id;
    result.package_manager = app.package_manager;
    result.package_id = app.package_id;
    result.platform = app.kind == CloudOSNativeAppsWindow::AppKind::LinuxGui
        ? CloudOS::UnifiedAppPlatformV16::Linux
        : CloudOS::UnifiedAppPlatformV16::Windows;
    result.can_launch = app.can_launch;
    result.can_uninstall = app.can_uninstall;
    return result;
}

bool SameName(const std::wstring& left, const std::wstring& right)
{
    return _wcsicmp(left.c_str(), right.c_str()) == 0;
}
} // namespace

CloudOSNativeAppsWindow::CloudOSNativeAppsWindow(HINSTANCE instance)
    : instance_(instance)
{
}

void CloudOSNativeAppsWindow::Open(HINSTANCE instance)
{
    auto* apps = new (std::nothrow) CloudOSNativeAppsWindow(instance);
    if (apps == nullptr || !apps->Create())
    {
        delete apps;
        MessageBoxW(nullptr, L"Nao foi possivel abrir Aplicativos.", L"CloudOS", MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeAppsWindow::Create()
{
    if (!RegisterWindowClass(instance_)) return false;

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Aplicativos - Windows + Linux - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT, CW_USEDEFAULT, 1040, 690,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    search_edit_ = CreateWindowExW(
        0, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSearchId)), instance_, nullptr);
    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)), instance_, nullptr);
    launch_button_ = CreateWindowExW(0, L"BUTTON", L"Abrir",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kLaunchId)), instance_, nullptr);
    install_button_ = CreateWindowExW(0, L"BUTTON", L"Instalar...",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kInstallId)), instance_, nullptr);
    uninstall_button_ = CreateWindowExW(0, L"BUTTON", L"Remover",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kUninstallId)), instance_, nullptr);
    refresh_button_ = CreateWindowExW(0, L"BUTTON", L"Atualizar",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRefreshId)), instance_, nullptr);

    if (search_edit_ == nullptr || list_ == nullptr || launch_button_ == nullptr ||
        install_button_ == nullptr || uninstall_button_ == nullptr || refresh_button_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    SendMessageW(search_edit_, EM_SETCUEBANNER, TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar app instalado ou digitar pacote para instalar..."));
    ListView_SetExtendedListViewStyle(list_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    CloudOS::WebSkin::ApplyUxTheme(list_);

    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.cx = 340;
    column.pszText = const_cast<wchar_t*>(L"Aplicativo");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 140;
    column.pszText = const_cast<wchar_t*>(L"Plataforma");
    ListView_InsertColumn(list_, 1, &column);
    column.cx = 500;
    column.pszText = const_cast<wchar_t*>(L"Origem / destino");
    ListView_InsertColumn(list_, 2, &column);

    CloudOS::ApplyWebWindowMaterial(window_);
    CloudOS::WebSkin::PrepareEdit(search_edit_);
    for (HWND button : {launch_button_, install_button_, uninstall_button_, refresh_button_})
        CloudOS::WebSkin::PrepareButton(button);

    LoadCatalog();
    ApplyFilter();
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetFocus(search_edit_);
    return true;
}

void CloudOSNativeAppsWindow::Layout()
{
    RECT client{};
    if (!GetClientRect(window_, &client)) return;

    const UINT dpi = GetDpiForWindow(window_);
    const int margin = CloudOS::Scale(14, dpi);
    const int gap = CloudOS::Scale(8, dpi);
    const int row = CloudOS::Scale(34, dpi);
    const int button = CloudOS::Scale(104, dpi);
    const int width = static_cast<int>(client.right - client.left);
    const int height = static_cast<int>(client.bottom - client.top);
    const int controls_width = button * 4 + gap * 4;
    MoveWindow(search_edit_, margin, margin,
        std::max(140, width - margin * 2 - controls_width), row, TRUE);

    int x = width - margin - button * 4 - gap * 3;
    MoveWindow(launch_button_, x, margin, button, row, TRUE); x += button + gap;
    MoveWindow(install_button_, x, margin, button, row, TRUE); x += button + gap;
    MoveWindow(uninstall_button_, x, margin, button, row, TRUE); x += button + gap;
    MoveWindow(refresh_button_, x, margin, button, row, TRUE);
    MoveWindow(list_, margin, margin + row + gap,
        std::max(100, width - margin * 2),
        std::max(80, height - (margin * 2 + row + gap)), TRUE);
}

std::wstring CloudOSNativeAppsWindow::ReadText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    if (length <= 0) return {};
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(edit, text.data(), length + 1);
    text.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return text;
}

bool CloudOSNativeAppsWindow::ContainsInsensitive(
    std::wstring_view text,
    std::wstring_view query)
{
    if (query.empty()) return true;
    std::wstring normalized_text(text);
    std::wstring normalized_query(query);
    std::transform(normalized_text.begin(), normalized_text.end(), normalized_text.begin(),
        [](wchar_t character) { return static_cast<wchar_t>(towlower(character)); });
    std::transform(normalized_query.begin(), normalized_query.end(), normalized_query.begin(),
        [](wchar_t character) { return static_cast<wchar_t>(towlower(character)); });
    return normalized_text.find(normalized_query) != std::wstring::npos;
}

void CloudOSNativeAppsWindow::EnumerateFolder(const std::wstring& folder, int depth)
{
    if (depth > 12) return;
    const std::wstring pattern = folder + (folder.empty() || folder.back() == L'\\' ? L"*" : L"\\*");
    WIN32_FIND_DATAW find_data{};
    HANDLE find = FindFirstFileW(pattern.c_str(), &find_data);
    if (find == INVALID_HANDLE_VALUE) return;

    do
    {
        if (wcscmp(find_data.cFileName, L".") == 0 || wcscmp(find_data.cFileName, L"..") == 0) continue;
        const std::wstring path = folder +
            (folder.empty() || folder.back() == L'\\' ? L"" : L"\\") + find_data.cFileName;
        if ((find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        {
            EnumerateFolder(path, depth + 1);
        }
        else if (HasExtension(path, L".lnk") || HasExtension(path, L".url") || HasExtension(path, L".exe"))
        {
            AppEntry app{};
            app.name = FileNameWithoutExtension(find_data.cFileName);
            app.path = path;
            app.kind = AppKind::External;
            app.platform = L"Windows";
            app.source = L"Windows · Menu Iniciar";
            app.can_launch = true;
            catalog_.push_back(std::move(app));
        }
    }
    while (FindNextFileW(find, &find_data));
    FindClose(find);
}

void CloudOSNativeAppsWindow::LoadCatalog()
{
    catalog_.clear();
    const auto add_internal = [&](const wchar_t* name, const wchar_t* uri, AppKind kind)
    {
        AppEntry app{};
        app.name = name;
        app.path = uri;
        app.kind = kind;
        app.platform = L"CloudOS";
        app.source = L"CloudOS · nativo";
        app.can_launch = true;
        catalog_.push_back(std::move(app));
    };
    add_internal(L"Bloco de Notas do CloudOS", L"cloudos://notepad", AppKind::Notepad);
    add_internal(L"Calculadora do CloudOS", L"cloudos://calculator", AppKind::Calculator);
    add_internal(L"Configuracoes do CloudOS", L"cloudos://settings", AppKind::Settings);
    add_internal(L"Saude do Sistema", L"cloudos://env-doctor", AppKind::EnvDoctor);
    add_internal(L"System Monitor", L"cloudos://system-monitor", AppKind::SystemMonitor);

    const std::array<KNOWNFOLDERID, 2> folders{FOLDERID_Programs, FOLDERID_CommonPrograms};
    for (const auto& folder_id : folders)
    {
        PWSTR folder_path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &folder_path)) && folder_path != nullptr)
        {
            EnumerateFolder(folder_path, 0);
            CoTaskMemFree(folder_path);
        }
    }

    AddSearchPathExecutable(catalog_, L"explorer.exe", L"Explorador do Windows");
    AddSearchPathExecutable(catalog_, L"cmd.exe", L"Prompt de Comando");
    AddSearchPathExecutable(catalog_, L"powershell.exe", L"Windows PowerShell");
    AddSearchPathExecutable(catalog_, L"taskmgr.exe", L"Gerenciador de Tarefas");
    AddSearchPathExecutable(catalog_, L"control.exe", L"Painel de Controle");
    AddSearchPathExecutable(catalog_, L"notepad.exe", L"Bloco de Notas do Windows");
    AddSearchPathExecutable(catalog_, L"wsl.exe", L"WSL");
    AddSearchPathExecutable(catalog_, L"wt.exe", L"Windows Terminal");

    for (const CloudOS::UnifiedAppV16& installed : CloudOS::NativeIntegrationV16::EnumerateWindowsInstalledApps())
    {
        auto existing = std::find_if(catalog_.begin(), catalog_.end(), [&](const AppEntry& app)
        {
            return app.platform == L"Windows" && SameName(app.name, installed.name);
        });
        if (existing != catalog_.end())
        {
            if (!installed.uninstall_command.empty())
            {
                existing->uninstall_command = installed.uninstall_command;
                existing->can_uninstall = true;
            }
            continue;
        }

        AppEntry app{};
        app.name = installed.name;
        app.path = installed.launch_target;
        app.kind = AppKind::InstalledWindows;
        app.platform = L"Windows";
        app.source = installed.source;
        app.uninstall_command = installed.uninstall_command;
        app.can_launch = installed.can_launch;
        app.can_uninstall = installed.can_uninstall;
        catalog_.push_back(std::move(app));
    }

    for (const CloudOS::UnifiedAppV16& linux : CloudOS::NativeIntegrationV16::EnumerateLinuxGuiApps())
    {
        AppEntry app{};
        app.name = linux.name;
        app.path = linux.launch_target;
        app.kind = AppKind::LinuxGui;
        app.platform = L"Linux / WSL";
        app.source = linux.source;
        app.distro = linux.distro;
        app.desktop_id = linux.desktop_id;
        app.package_manager = linux.package_manager;
        app.package_id = linux.package_id;
        app.can_launch = linux.can_launch;
        app.can_uninstall = linux.can_uninstall;
        catalog_.push_back(std::move(app));
    }

    std::sort(catalog_.begin(), catalog_.end(), [](const AppEntry& left, const AppEntry& right)
    {
        const int name = _wcsicmp(left.name.c_str(), right.name.c_str());
        if (name != 0) return name < 0;
        const int platform = _wcsicmp(left.platform.c_str(), right.platform.c_str());
        if (platform != 0) return platform < 0;
        return _wcsicmp(left.path.c_str(), right.path.c_str()) < 0;
    });

    catalog_.erase(std::unique(catalog_.begin(), catalog_.end(), [](const AppEntry& left, const AppEntry& right)
    {
        if (left.kind == AppKind::LinuxGui || right.kind == AppKind::LinuxGui)
            return left.kind == right.kind && _wcsicmp(left.distro.c_str(), right.distro.c_str()) == 0 &&
                _wcsicmp(left.desktop_id.c_str(), right.desktop_id.c_str()) == 0;
        return left.kind == right.kind && !left.path.empty() && !right.path.empty() &&
            _wcsicmp(left.path.c_str(), right.path.c_str()) == 0;
    }), catalog_.end());
}

void CloudOSNativeAppsWindow::ApplyFilter()
{
    const std::wstring query = ReadText(search_edit_);
    visible_indices_.clear();
    ListView_DeleteAllItems(list_);

    for (std::size_t index = 0; index < catalog_.size(); ++index)
    {
        const AppEntry& app = catalog_[index];
        if (!ContainsInsensitive(app.name, query) && !ContainsInsensitive(app.path, query) &&
            !ContainsInsensitive(app.platform, query) && !ContainsInsensitive(app.source, query))
            continue;

        visible_indices_.push_back(index);
        const int row = static_cast<int>(visible_indices_.size() - 1u);
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = row;
        item.pszText = app.name.data();
        ListView_InsertItem(list_, &item);
        ListView_SetItemText(list_, row, 1, const_cast<wchar_t*>(app.platform.c_str()));
        std::wstring source = app.source;
        if (source.empty()) source = app.path;
        ListView_SetItemText(list_, row, 2, source.data());
    }
    UpdateActionState();
}

void CloudOSNativeAppsWindow::UpdateActionState()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    const bool selected = row >= 0 && static_cast<std::size_t>(row) < visible_indices_.size();
    bool can_launch = false;
    bool can_uninstall = false;
    if (selected)
    {
        const AppEntry& app = catalog_[visible_indices_[static_cast<std::size_t>(row)]];
        can_launch = app.can_launch;
        can_uninstall = app.can_uninstall ||
            (app.platform == L"Windows" && app.kind != AppKind::Calculator && app.kind != AppKind::Notepad &&
             app.kind != AppKind::Settings && app.kind != AppKind::SystemMonitor && app.kind != AppKind::EnvDoctor);
    }
    EnableWindow(launch_button_, can_launch ? TRUE : FALSE);
    EnableWindow(uninstall_button_, can_uninstall ? TRUE : FALSE);
}

void CloudOSNativeAppsWindow::LaunchSelection()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= visible_indices_.size()) return;
    const AppEntry& app = catalog_[visible_indices_[static_cast<std::size_t>(row)]];

    switch (app.kind)
    {
    case AppKind::Calculator:
        if (CloudOSNativeCalculatorWindow::Open(instance_) == nullptr) ShowInternalLaunchError(window_, L"Calculadora");
        return;
    case AppKind::Notepad:
        if (CloudOSNativeNotepadWindow::Open(instance_) == nullptr) ShowInternalLaunchError(window_, L"Bloco de Notas");
        return;
    case AppKind::Settings:
        CloudOSNativeSettingsWindow::Open(instance_);
        return;
    case AppKind::SystemMonitor:
        if (CloudOSNativeSystemMonitorWindow::Open(instance_) == nullptr) ShowInternalLaunchError(window_, L"System Monitor");
        return;
    case AppKind::EnvDoctor:
        if (CloudOSNativeEnvDoctorWindow::Open(instance_) == nullptr) ShowInternalLaunchError(window_, L"Saude do Sistema");
        return;
    case AppKind::LinuxGui:
        if (!CloudOS::NativeIntegrationV16::LaunchLinuxApp(window_, ToUnified(app)))
            MessageBoxW(window_, L"O aplicativo Linux nao pode ser iniciado pelo WSLg.", L"CloudOS", MB_OK | MB_ICONERROR);
        return;
    case AppKind::InstalledWindows:
    case AppKind::External:
        break;
    }

    if (!app.can_launch || !LaunchExternalApplication(window_, app.path))
    {
        MessageBoxW(window_, L"O aplicativo nao possui um destino inicializavel conhecido.",
            L"CloudOS", MB_OK | MB_ICONWARNING);
        ShowWindow(window_, SW_SHOW);
        SetForegroundWindow(window_);
        return;
    }
    PostMessageW(window_, WM_CLOSE, 0, 0);
}

void CloudOSNativeAppsWindow::InstallFromSearch()
{
    const std::wstring query = Trim(ReadText(search_edit_));
    if (query.empty())
    {
        MessageBoxW(window_, L"Digite no campo de pesquisa o nome exato do aplicativo Windows ou o nome do pacote Linux.",
            L"Instalar - CloudOS", MB_OK | MB_ICONINFORMATION);
        SetFocus(search_edit_);
        return;
    }

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr) return;
    AppendMenuW(menu, MF_STRING | (CloudOS::NativeIntegrationV16::IsWinGetAvailable() ? 0 : MF_GRAYED),
        kInstallWindows, L"Instalar no Windows via WinGet");
    const auto distros = CloudOS::NativeIntegrationV16::EnumerateWslDistributions();
    AppendMenuW(menu, MF_STRING | (!distros.empty() ? 0 : MF_GRAYED),
        kInstallLinux, L"Instalar no Linux via apt / WSL");

    RECT button{};
    GetWindowRect(install_button_, &button);
    const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        button.left, button.bottom, 0, window_, nullptr);
    DestroyMenu(menu);

    if (command == kInstallWindows)
    {
        const std::wstring command_line = CloudOS::NativeIntegrationV16::BuildWingetInstallCommand(query);
        if (command_line.empty()) return;
        std::wstring prompt = L"Instalar '" + query + L"' no Windows usando WinGet?\n\nA instalacao sera executada dentro do Terminal do CloudOS e podera solicitar elevacao.";
        if (MessageBoxW(window_, prompt.c_str(), L"Instalar Windows - CloudOS", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
        CloudOSNativeTerminalWindow::Open(instance_, command_line, L"Instalacao Windows - CloudOS");
        return;
    }

    if (command == kInstallLinux)
    {
        std::wstring distro = CloudOSNativeSettingsWindow::Load().default_wsl_distribution;
        auto found = std::find_if(distros.begin(), distros.end(), [&](const std::wstring& item)
        {
            return _wcsicmp(item.c_str(), distro.c_str()) == 0;
        });
        if (found == distros.end()) distro = distros.front();
        const std::wstring command_line = CloudOS::NativeIntegrationV16::BuildLinuxInstallCommand(distro, query);
        if (command_line.empty())
        {
            MessageBoxW(window_, L"O nome do pacote Linux contem caracteres que nao sao aceitos pelo instalador seguro do CloudOS.",
                L"CloudOS", MB_OK | MB_ICONWARNING);
            return;
        }
        std::wstring prompt = L"Instalar o pacote Linux '" + query + L"' em " + distro +
            L"?\n\nO Terminal do CloudOS executara apt e o Linux podera solicitar sua senha sudo.";
        if (MessageBoxW(window_, prompt.c_str(), L"Instalar Linux - CloudOS", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
        CloudOSNativeTerminalWindow::Open(instance_, command_line, L"Instalacao Linux - CloudOS");
    }
}

void CloudOSNativeAppsWindow::UninstallSelection()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= visible_indices_.size()) return;
    const AppEntry& app = catalog_[visible_indices_[static_cast<std::size_t>(row)]];

    if (app.kind == AppKind::LinuxGui)
    {
        std::wstring command_line;
        std::wstring package;
        if (!CloudOS::NativeIntegrationV16::ResolveLinuxRemovalCommand(ToUnified(app), &command_line, &package))
        {
            MessageBoxW(window_, L"O CloudOS encontrou o aplicativo Linux, mas nao conseguiu mapear com seguranca o arquivo .desktop para um pacote apt/snap/flatpak.",
                L"Remover Linux - CloudOS", MB_OK | MB_ICONWARNING);
            return;
        }
        std::wstring prompt = L"Remover '" + app.name + L"' (" + package + L") de " + app.distro + L"?";
        if (MessageBoxW(window_, prompt.c_str(), L"Remover Linux - CloudOS", MB_YESNO | MB_ICONWARNING) != IDYES) return;
        CloudOSNativeTerminalWindow::Open(instance_, command_line, L"Remocao Linux - CloudOS");
        return;
    }

    if (app.platform != L"Windows") return;
    std::wstring prompt = L"Remover '" + app.name + L"' do Windows?";
    if (MessageBoxW(window_, prompt.c_str(), L"Remover Windows - CloudOS", MB_YESNO | MB_ICONWARNING) != IDYES) return;

    if (!app.uninstall_command.empty())
    {
        if (!CloudOS::NativeIntegrationV16::LaunchWindowsUninstaller(window_, ToUnified(app)))
            MessageBoxW(window_, L"O desinstalador registrado pelo Windows nao pode ser iniciado.", L"CloudOS", MB_OK | MB_ICONERROR);
        return;
    }

    const std::wstring command_line = CloudOS::NativeIntegrationV16::BuildWingetUninstallCommand(app.name);
    if (!command_line.empty())
    {
        CloudOSNativeTerminalWindow::Open(instance_, command_line, L"Remocao Windows - CloudOS");
        return;
    }

    MessageBoxW(window_, L"Este aplicativo nao publicou um desinstalador e o WinGet nao esta disponivel.",
        L"CloudOS", MB_OK | MB_ICONWARNING);
}

void CloudOSNativeAppsWindow::RefreshCatalog()
{
    const std::wstring query = ReadText(search_edit_);
    LoadCatalog();
    SetWindowTextW(search_edit_, query.c_str());
    ApplyFilter();
}

LRESULT CloudOSNativeAppsWindow::HandleMessage(
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchId && HIWORD(w_param) == EN_CHANGE)
        {
            ApplyFilter();
            return 0;
        }
        if (HIWORD(w_param) == BN_CLICKED)
        {
            switch (LOWORD(w_param))
            {
            case kLaunchId: LaunchSelection(); return 0;
            case kInstallId: InstallFromSearch(); return 0;
            case kUninstallId: UninstallSelection(); return 0;
            case kRefreshId: RefreshCatalog(); return 0;
            default: break;
            }
        }
        break;
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK)
            {
                LaunchSelection();
                return 0;
            }
            if (header->code == LVN_ITEMCHANGED)
            {
                UpdateActionState();
                return 0;
            }
        }
        break;
    }
    case WM_KEYDOWN:
        if (w_param == VK_RETURN)
        {
            LaunchSelection();
            return 0;
        }
        if (w_param == VK_F5)
        {
            RefreshCatalog();
            return 0;
        }
        break;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr && draw->CtlType == ODT_BUTTON)
        {
            const CloudOS::ButtonTone tone = draw->CtlID == kUninstallId
                ? CloudOS::ButtonTone::Danger
                : (draw->CtlID == kInstallId ? CloudOS::ButtonTone::Accent : CloudOS::ButtonTone::Neutral);
            if (CloudOS::WebSkin::PaintOwnerDrawButton(draw, tone)) return TRUE;
        }
        break;
    }
    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
        window_ = nullptr;
        delete this;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeAppsWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeAppsWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeAppsWindow*>(create->lpCreateParams);
        if (self == nullptr) return FALSE;
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeAppsWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }
    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
