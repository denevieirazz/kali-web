#include "native_apps_window.h"

#include <commctrl.h>
#include <knownfolders.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <new>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Apps.v2";
constexpr int kSearchId = 1301;
constexpr int kListId = 1302;
constexpr int kLaunchId = 1303;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeAppsWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring FileNameWithoutExtension(std::wstring path)
{
    const std::size_t separator = path.find_last_of(L"\\/");
    if (separator != std::wstring::npos)
    {
        path = path.substr(separator + 1);
    }

    const std::size_t extension = path.find_last_of(L'.');
    if (extension != std::wstring::npos)
    {
        path.resize(extension);
    }
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
        catalog.push_back({display_name, buffer.data()});
    }
}
}

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
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Aplicativos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeAppsWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Aplicativos - CloudOS",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        840,
        620,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    search_edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kSearchId),
        instance_,
        nullptr);
    list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kListId),
        instance_,
        nullptr);
    launch_button_ = CreateWindowW(
        L"BUTTON",
        L"Abrir",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kLaunchId),
        instance_,
        nullptr);

    if (search_edit_ == nullptr || list_ == nullptr || launch_button_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar aplicativos..."));
    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.cx = 300;
    column.pszText = const_cast<wchar_t*>(L"Aplicativo");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 450;
    column.pszText = const_cast<wchar_t*>(L"Origem");
    ListView_InsertColumn(list_, 1, &column);

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
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    MoveWindow(search_edit_, 12, 12, std::max(100, width - 126), 30, TRUE);
    MoveWindow(launch_button_, std::max(12, width - 102), 12, 90, 30, TRUE);
    MoveWindow(list_, 12, 52, std::max(100, width - 24), std::max(80, height - 64), TRUE);
}

std::wstring CloudOSNativeAppsWindow::ReadText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    if (length <= 0)
    {
        return {};
    }

    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    GetWindowTextW(edit, text.data(), length + 1);
    text.resize(static_cast<std::size_t>(length));
    return text;
}

bool CloudOSNativeAppsWindow::ContainsInsensitive(
    std::wstring_view text,
    std::wstring_view query)
{
    if (query.empty())
    {
        return true;
    }

    std::wstring normalized_text(text);
    std::wstring normalized_query(query);
    std::transform(
        normalized_text.begin(),
        normalized_text.end(),
        normalized_text.begin(),
        [](wchar_t character)
        {
            return static_cast<wchar_t>(towlower(character));
        });
    std::transform(
        normalized_query.begin(),
        normalized_query.end(),
        normalized_query.begin(),
        [](wchar_t character)
        {
            return static_cast<wchar_t>(towlower(character));
        });
    return normalized_text.find(normalized_query) != std::wstring::npos;
}

void CloudOSNativeAppsWindow::EnumerateFolder(const std::wstring& folder, int depth)
{
    if (depth > 12)
    {
        return;
    }

    const std::wstring pattern =
        folder + (folder.empty() || folder.back() == L'\\' ? L"*" : L"\\*");
    WIN32_FIND_DATAW find_data{};
    HANDLE find = FindFirstFileW(pattern.c_str(), &find_data);
    if (find == INVALID_HANDLE_VALUE)
    {
        return;
    }

    do
    {
        if (wcscmp(find_data.cFileName, L".") == 0 ||
            wcscmp(find_data.cFileName, L"..") == 0)
        {
            continue;
        }

        const std::wstring path =
            folder + (folder.empty() || folder.back() == L'\\' ? L"" : L"\\") + find_data.cFileName;
        if ((find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        {
            EnumerateFolder(path, depth + 1);
        }
        else if (HasExtension(path, L".lnk") ||
            HasExtension(path, L".url") ||
            HasExtension(path, L".exe"))
        {
            catalog_.push_back({FileNameWithoutExtension(find_data.cFileName), path});
        }
    }
    while (FindNextFileW(find, &find_data));
    FindClose(find);
}

void CloudOSNativeAppsWindow::LoadCatalog()
{
    catalog_.clear();

    const std::array<KNOWNFOLDERID, 2> folders{
        FOLDERID_Programs,
        FOLDERID_CommonPrograms,
    };
    for (const auto& folder_id : folders)
    {
        PWSTR folder_path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(
                folder_id,
                KF_FLAG_DEFAULT,
                nullptr,
                &folder_path)) &&
            folder_path != nullptr)
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
    AddSearchPathExecutable(catalog_, L"notepad.exe", L"Bloco de Notas");
    AddSearchPathExecutable(catalog_, L"wsl.exe", L"WSL");
    AddSearchPathExecutable(catalog_, L"wt.exe", L"Windows Terminal");

    std::sort(
        catalog_.begin(),
        catalog_.end(),
        [](const AppEntry& left, const AppEntry& right)
        {
            const int name_compare = _wcsicmp(left.name.c_str(), right.name.c_str());
            if (name_compare != 0)
            {
                return name_compare < 0;
            }
            return _wcsicmp(left.path.c_str(), right.path.c_str()) < 0;
        });

    catalog_.erase(
        std::unique(
            catalog_.begin(),
            catalog_.end(),
            [](const AppEntry& left, const AppEntry& right)
            {
                return _wcsicmp(left.path.c_str(), right.path.c_str()) == 0;
            }),
        catalog_.end());
}

void CloudOSNativeAppsWindow::ApplyFilter()
{
    const std::wstring query = ReadText(search_edit_);
    visible_indices_.clear();
    ListView_DeleteAllItems(list_);

    for (std::size_t index = 0; index < catalog_.size(); ++index)
    {
        if (!ContainsInsensitive(catalog_[index].name, query) &&
            !ContainsInsensitive(catalog_[index].path, query))
        {
            continue;
        }

        visible_indices_.push_back(index);
        const int row = static_cast<int>(visible_indices_.size() - 1u);
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = row;
        item.pszText = catalog_[index].name.data();
        ListView_InsertItem(list_, &item);
        ListView_SetItemText(list_, row, 1, catalog_[index].path.data());
    }
}

void CloudOSNativeAppsWindow::LaunchSelection()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= visible_indices_.size())
    {
        return;
    }

    const auto& app = catalog_[visible_indices_[static_cast<std::size_t>(row)]];
    HINSTANCE result = ShellExecuteW(
        window_,
        L"open",
        app.path.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32)
    {
        MessageBoxW(
            window_,
            L"O aplicativo nao pode ser iniciado.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
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
        if (LOWORD(w_param) == kLaunchId)
        {
            LaunchSelection();
            return 0;
        }
        break;

    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_ && header->code == NM_DBLCLK)
        {
            LaunchSelection();
            return 0;
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
            LoadCatalog();
            ApplyFilter();
            return 0;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;

    case WM_NCDESTROY:
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
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeAppsWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
