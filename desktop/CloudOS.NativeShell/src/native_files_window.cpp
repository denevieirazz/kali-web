#include "native_files_window.h"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <new>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Files.v2";
constexpr int kPathId = 1201;
constexpr int kGoId = 1202;
constexpr int kUpId = 1203;
constexpr int kWslId = 1204;
constexpr int kListId = 1205;
constexpr int kRefreshId = 1206;
constexpr int kNewFolderId = 1207;
constexpr int kDeleteId = 1208;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeFilesWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring ReadEditText(HWND edit)
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

std::wstring DefaultPath()
{
    std::array<wchar_t, MAX_PATH> windows_directory{};
    if (GetWindowsDirectoryW(
            windows_directory.data(),
            static_cast<UINT>(windows_directory.size())) > 0)
    {
        std::wstring path = windows_directory.data();
        if (path.size() >= 3)
        {
            return path.substr(0, 3);
        }
    }
    return L"C:\\";
}

bool IsSafeLeafName(const wchar_t* text)
{
    if (text == nullptr || *text == L'\0')
    {
        return false;
    }

    std::wstring_view name(text);
    if (name == L"." || name == L"..")
    {
        return false;
    }

    return name.find_first_of(L"\\/:*?\"<>|") == std::wstring_view::npos;
}
}

CloudOSNativeFilesWindow::CloudOSNativeFilesWindow(
    HINSTANCE instance,
    std::wstring initial_path)
    : instance_(instance),
      current_path_(std::move(initial_path))
{
    if (current_path_.empty())
    {
        current_path_ = DefaultPath();
    }
}

void CloudOSNativeFilesWindow::Open(
    HINSTANCE instance,
    const std::wstring& initial_path)
{
    auto* files = new (std::nothrow) CloudOSNativeFilesWindow(instance, initial_path);
    if (files == nullptr || !files->Create())
    {
        delete files;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Arquivos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeFilesWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Arquivos - CloudOS",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1040,
        680,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    path_edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        current_path_.c_str(),
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kPathId),
        instance_,
        nullptr);
    go_button_ = CreateWindowW(
        L"BUTTON",
        L"Ir",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kGoId),
        instance_,
        nullptr);
    up_button_ = CreateWindowW(
        L"BUTTON",
        L"Acima",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kUpId),
        instance_,
        nullptr);
    wsl_button_ = CreateWindowW(
        L"BUTTON",
        L"WSL",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kWslId),
        instance_,
        nullptr);
    refresh_button_ = CreateWindowW(
        L"BUTTON",
        L"Atualizar",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kRefreshId),
        instance_,
        nullptr);
    new_folder_button_ = CreateWindowW(
        L"BUTTON",
        L"Nova pasta",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kNewFolderId),
        instance_,
        nullptr);
    delete_button_ = CreateWindowW(
        L"BUTTON",
        L"Excluir",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kDeleteId),
        instance_,
        nullptr);
    list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_EDITLABELS,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kListId),
        instance_,
        nullptr);

    if (path_edit_ == nullptr || go_button_ == nullptr || up_button_ == nullptr ||
        wsl_button_ == nullptr || refresh_button_ == nullptr ||
        new_folder_button_ == nullptr || delete_button_ == nullptr || list_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.cx = 560;
    column.pszText = const_cast<wchar_t*>(L"Nome");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 130;
    column.pszText = const_cast<wchar_t*>(L"Tipo");
    ListView_InsertColumn(list_, 1, &column);
    column.cx = 150;
    column.pszText = const_cast<wchar_t*>(L"Tamanho");
    ListView_InsertColumn(list_, 2, &column);

    Navigate(current_path_);
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeFilesWindow::Layout()
{
    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int width = client.right - client.left;
    const int height = client.bottom - client.top;

    MoveWindow(up_button_, 12, 12, 72, 30, TRUE);
    MoveWindow(wsl_button_, 90, 12, 58, 30, TRUE);
    MoveWindow(refresh_button_, 154, 12, 82, 30, TRUE);
    MoveWindow(new_folder_button_, 242, 12, 92, 30, TRUE);
    MoveWindow(delete_button_, 340, 12, 72, 30, TRUE);
    MoveWindow(path_edit_, 420, 12, std::max(120, width - 490), 30, TRUE);
    MoveWindow(go_button_, std::max(420, width - 62), 12, 50, 30, TRUE);
    MoveWindow(list_, 12, 52, std::max(100, width - 24), std::max(80, height - 64), TRUE);
}

std::wstring CloudOSNativeFilesWindow::JoinPath(
    const std::wstring& directory,
    const std::wstring& name)
{
    if (directory.empty())
    {
        return name;
    }
    if (directory.back() == L'\\' || directory.back() == L'/')
    {
        return directory + name;
    }
    return directory + L"\\" + name;
}

bool CloudOSNativeFilesWindow::IsWslRootPath(const std::wstring& path)
{
    return _wcsicmp(path.c_str(), L"\\\\wsl$") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl$\\") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl.localhost") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl.localhost\\") == 0;
}

bool CloudOSNativeFilesWindow::IsRootPath(const std::wstring& path)
{
    if (path.size() == 3 && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/'))
    {
        return true;
    }
    return IsWslRootPath(path);
}

std::wstring CloudOSNativeFilesWindow::ParentPath(const std::wstring& path)
{
    if (IsRootPath(path))
    {
        return path;
    }

    std::wstring normalized = path;
    while (normalized.size() > 3 &&
        (normalized.back() == L'\\' || normalized.back() == L'/'))
    {
        normalized.pop_back();
    }

    const std::size_t position = normalized.find_last_of(L"\\/");
    if (position == std::wstring::npos)
    {
        return normalized;
    }

    if (position == 2 && normalized.size() > 2 && normalized[1] == L':')
    {
        return normalized.substr(0, 3);
    }

    if (normalized.rfind(L"\\\\wsl.localhost\\", 0) == 0)
    {
        const std::size_t distro_separator = normalized.find(L'\\', 16);
        if (distro_separator == std::wstring::npos)
        {
            return L"\\\\wsl.localhost\\";
        }
    }
    else if (normalized.rfind(L"\\\\wsl$\\", 0) == 0)
    {
        const std::size_t distro_separator = normalized.find(L'\\', 7);
        if (distro_separator == std::wstring::npos)
        {
            return L"\\\\wsl$\\";
        }
    }

    return position == 0 ? L"\\" : normalized.substr(0, position);
}

std::wstring CloudOSNativeFilesWindow::FormatSize(ULONGLONG size)
{
    wchar_t buffer[64]{};
    if (size >= 1024ull * 1024ull * 1024ull)
    {
        swprintf_s(
            buffer,
            L"%.2f GB",
            static_cast<double>(size) / (1024.0 * 1024.0 * 1024.0));
    }
    else if (size >= 1024ull * 1024ull)
    {
        swprintf_s(buffer, L"%.1f MB", static_cast<double>(size) / (1024.0 * 1024.0));
    }
    else if (size >= 1024ull)
    {
        swprintf_s(buffer, L"%.1f KB", static_cast<double>(size) / 1024.0);
    }
    else
    {
        swprintf_s(buffer, L"%llu B", size);
    }
    return buffer;
}

void CloudOSNativeFilesWindow::Navigate(const std::wstring& path)
{
    if (path.empty())
    {
        return;
    }

    if (!IsWslRootPath(path))
    {
        const DWORD attributes = GetFileAttributesW(path.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
        {
            MessageBoxW(
                window_,
                L"Pasta nao encontrada ou sem acesso.",
                L"CloudOS Arquivos",
                MB_OK | MB_ICONWARNING);
            return;
        }
    }

    current_path_ = path;
    SetWindowTextW(path_edit_, current_path_.c_str());
    PopulateList();
}

void CloudOSNativeFilesWindow::NavigateParent()
{
    const std::wstring parent = ParentPath(current_path_);
    if (!parent.empty())
    {
        Navigate(parent);
    }
}

void CloudOSNativeFilesWindow::NavigateWslRoot()
{
    Navigate(L"\\\\wsl.localhost\\");
    if (entries_.empty())
    {
        Navigate(L"\\\\wsl$\\");
    }
}

void CloudOSNativeFilesWindow::PopulateList()
{
    entries_.clear();
    ListView_DeleteAllItems(list_);

    const std::wstring pattern = JoinPath(current_path_, L"*");
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

        Entry entry{};
        entry.name = find_data.cFileName;
        entry.full_path = JoinPath(current_path_, entry.name);
        entry.directory = (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        entry.size =
            (static_cast<ULONGLONG>(find_data.nFileSizeHigh) << 32u) |
            static_cast<ULONGLONG>(find_data.nFileSizeLow);
        entries_.push_back(std::move(entry));
    }
    while (FindNextFileW(find, &find_data));
    FindClose(find);

    std::sort(
        entries_.begin(),
        entries_.end(),
        [](const Entry& left, const Entry& right)
        {
            if (left.directory != right.directory)
            {
                return left.directory > right.directory;
            }
            return _wcsicmp(left.name.c_str(), right.name.c_str()) < 0;
        });

    for (std::size_t index = 0; index < entries_.size(); ++index)
    {
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = entries_[index].name.data();
        ListView_InsertItem(list_, &item);

        wchar_t type[16]{};
        wcscpy_s(type, entries_[index].directory ? L"Pasta" : L"Arquivo");
        ListView_SetItemText(list_, static_cast<int>(index), 1, type);

        auto size = entries_[index].directory
            ? std::wstring{}
            : FormatSize(entries_[index].size);
        ListView_SetItemText(list_, static_cast<int>(index), 2, size.data());
    }
}

void CloudOSNativeFilesWindow::Refresh()
{
    PopulateList();
}

std::wstring CloudOSNativeFilesWindow::SelectedPath() const
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= entries_.size())
    {
        return {};
    }
    return entries_[static_cast<std::size_t>(selected)].full_path;
}

void CloudOSNativeFilesWindow::ActivateSelection()
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= entries_.size())
    {
        return;
    }

    auto& entry = entries_[static_cast<std::size_t>(selected)];
    if (entry.directory)
    {
        Navigate(entry.full_path);
        return;
    }

    HINSTANCE result = ShellExecuteW(
        window_,
        L"open",
        entry.full_path.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32)
    {
        MessageBoxW(
            window_,
            L"O Windows nao encontrou um aplicativo para abrir este arquivo.",
            L"CloudOS",
            MB_OK | MB_ICONWARNING);
    }
}

void CloudOSNativeFilesWindow::CreateNewFolder()
{
    std::wstring name = L"Nova pasta";
    std::wstring target = JoinPath(current_path_, name);
    unsigned suffix = 2;
    while (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        name = L"Nova pasta (" + std::to_wstring(suffix++) + L")";
        target = JoinPath(current_path_, name);
    }

    if (!CreateDirectoryW(target.c_str(), nullptr))
    {
        MessageBoxW(
            window_,
            L"Nao foi possivel criar a pasta neste local.",
            L"CloudOS Arquivos",
            MB_OK | MB_ICONWARNING);
        return;
    }

    PopulateList();
    for (int row = 0; row < ListView_GetItemCount(list_); ++row)
    {
        wchar_t buffer[MAX_PATH]{};
        ListView_GetItemText(list_, row, 0, buffer, static_cast<int>(std::size(buffer)));
        if (_wcsicmp(buffer, name.c_str()) == 0)
        {
            ListView_SetItemState(list_, row, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
            ListView_EditLabel(list_, row);
            break;
        }
    }
}

void CloudOSNativeFilesWindow::DeleteSelection()
{
    const std::wstring path = SelectedPath();
    if (path.empty())
    {
        return;
    }

    if (MessageBoxW(
            window_,
            L"Excluir o item selecionado?",
            L"CloudOS Arquivos",
            MB_YESNO | MB_ICONWARNING) != IDYES)
    {
        return;
    }

    std::wstring double_null_path = path;
    double_null_path.push_back(L'\0');
    double_null_path.push_back(L'\0');

    SHFILEOPSTRUCTW operation{};
    operation.hwnd = window_;
    operation.wFunc = FO_DELETE;
    operation.pFrom = double_null_path.c_str();
    operation.fFlags = FOF_NOCONFIRMMKDIR | FOF_NOERRORUI;

    const int result = SHFileOperationW(&operation);
    if (result != 0 || operation.fAnyOperationsAborted)
    {
        MessageBoxW(
            window_,
            L"Nao foi possivel excluir o item.",
            L"CloudOS Arquivos",
            MB_OK | MB_ICONWARNING);
    }
    PopulateList();
}

void CloudOSNativeFilesWindow::BeginRename()
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected >= 0)
    {
        ListView_EditLabel(list_, selected);
    }
}

bool CloudOSNativeFilesWindow::CommitRename(int row, const wchar_t* new_name)
{
    if (row < 0 || static_cast<std::size_t>(row) >= entries_.size() || !IsSafeLeafName(new_name))
    {
        return false;
    }

    const std::wstring destination = JoinPath(current_path_, new_name);
    if (_wcsicmp(destination.c_str(), entries_[static_cast<std::size_t>(row)].full_path.c_str()) == 0)
    {
        return true;
    }

    if (!MoveFileW(entries_[static_cast<std::size_t>(row)].full_path.c_str(), destination.c_str()))
    {
        MessageBoxW(
            window_,
            L"Nao foi possivel renomear o item.",
            L"CloudOS Arquivos",
            MB_OK | MB_ICONWARNING);
        return false;
    }

    entries_[static_cast<std::size_t>(row)].name = new_name;
    entries_[static_cast<std::size_t>(row)].full_path = destination;
    return true;
}

LRESULT CloudOSNativeFilesWindow::HandleMessage(
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
        switch (LOWORD(w_param))
        {
        case kGoId:
            Navigate(ReadEditText(path_edit_));
            return 0;
        case kUpId:
            NavigateParent();
            return 0;
        case kWslId:
            NavigateWslRoot();
            return 0;
        case kRefreshId:
            Refresh();
            return 0;
        case kNewFolderId:
            CreateNewFolder();
            return 0;
        case kDeleteId:
            DeleteSelection();
            return 0;
        default:
            break;
        }
        break;

    case WM_NOTIFY:
    {
        auto* header = reinterpret_cast<NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK)
            {
                ActivateSelection();
                return 0;
            }
            if (header->code == LVN_ENDLABELEDITW)
            {
                auto* edit = reinterpret_cast<NMLVDISPINFOW*>(l_param);
                return edit != nullptr && CommitRename(edit->item.iItem, edit->item.pszText)
                    ? TRUE
                    : FALSE;
            }
        }
        break;
    }

    case WM_KEYDOWN:
        switch (w_param)
        {
        case VK_F5:
            Refresh();
            return 0;
        case VK_F2:
            BeginRename();
            return 0;
        case VK_DELETE:
            DeleteSelection();
            return 0;
        case VK_RETURN:
            ActivateSelection();
            return 0;
        case VK_BACK:
            NavigateParent();
            return 0;
        default:
            break;
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

LRESULT CALLBACK CloudOSNativeFilesWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeFilesWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFilesWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeFilesWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
