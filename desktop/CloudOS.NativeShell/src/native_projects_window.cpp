#include "native_projects_window.h"

#include "native_files_window.h"
#include "native_terminal_window.h"
#include "native_theme.h"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <new>
#include <string>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Projects.v1";
constexpr int kListId = 1801;
constexpr int kNewId = 1802;
constexpr int kFilesId = 1803;
constexpr int kTerminalId = 1804;
constexpr int kCodeId = 1805;
constexpr int kTrashId = 1806;
constexpr int kRefreshId = 1807;
constexpr int kRootLabelId = 1808;

const std::vector<std::wstring> kProjectsSegments{L"Home", L"Projects"};

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeProjectsWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 ||
        GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool IsSafeProjectName(const wchar_t* value)
{
    if (value == nullptr || *value == L'\0')
    {
        return false;
    }
    const std::wstring_view name(value);
    if (name == L"." || name == L".." || name.size() > 120u)
    {
        return false;
    }
    return name.find_first_of(L"\\/:*?\"<>|") == std::wstring_view::npos;
}

std::wstring FormatFileTime(const FILETIME& value)
{
    FILETIME local{};
    SYSTEMTIME system{};
    if (!FileTimeToLocalFileTime(&value, &local) ||
        !FileTimeToSystemTime(&local, &system))
    {
        return {};
    }

    wchar_t date[64]{};
    wchar_t time[64]{};
    if (GetDateFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            DATE_SHORTDATE,
            &system,
            nullptr,
            date,
            static_cast<int>(std::size(date)),
            nullptr) == 0)
    {
        return {};
    }
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            TIME_NOSECONDS,
            &system,
            nullptr,
            time,
            static_cast<int>(std::size(time))) == 0)
    {
        return date;
    }
    std::wstring result = date;
    result += L" ";
    result += time;
    return result;
}

void ShowProjectError(HWND owner, const wchar_t* action, const std::wstring& detail = {})
{
    std::wstring message(action);
    if (!detail.empty())
    {
        message += L"\n\n";
        message += detail;
    }
    MessageBoxW(owner, message.c_str(), L"Projetos - CloudOS", MB_OK | MB_ICONWARNING);
}

bool LaunchCode(HWND owner, const std::wstring& directory)
{
    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI | SEE_MASK_ASYNCOK;
    execution.hwnd = nullptr;
    execution.lpVerb = L"open";
    execution.lpFile = L"code.cmd";
    execution.lpParameters = L".";
    execution.lpDirectory = directory.c_str();
    execution.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&execution))
    {
        ShowProjectError(owner, L"VS Code nao foi encontrado neste computador.");
        return false;
    }
    if (execution.hProcess != nullptr)
    {
        CloseHandle(execution.hProcess);
    }
    return true;
}
}

CloudOSNativeProjectsWindow::CloudOSNativeProjectsWindow(HINSTANCE instance) noexcept
    : instance_(instance)
{
}

void CloudOSNativeProjectsWindow::Open(HINSTANCE instance)
{
    auto* projects = new (std::nothrow) CloudOSNativeProjectsWindow(instance);
    if (projects == nullptr || !projects->Create())
    {
        delete projects;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Projetos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeProjectsWindow::Create()
{
    std::wstring drive_error;
    if (!NativeCloudOSDrive::EnsureReady(&drive_error))
    {
        ShowProjectError(nullptr, L"CloudOS Drive indisponivel.", drive_error);
        return false;
    }
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Projetos - CloudOS",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        930,
        590,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }
    DarkWindow(window_);

    root_label_ = CreateWindowW(
        L"STATIC",
        NativeCloudOSDrive::ProjectsRoot().c_str(),
        WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRootLabelId)),
        instance_,
        nullptr);
    list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_EDITLABELS,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    new_button_ = CreateWindowW(L"BUTTON", L"Novo projeto", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNewId)), instance_, nullptr);
    files_button_ = CreateWindowW(L"BUTTON", L"Abrir arquivos", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFilesId)), instance_, nullptr);
    terminal_button_ = CreateWindowW(L"BUTTON", L"Terminal", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTerminalId)), instance_, nullptr);
    code_button_ = CreateWindowW(L"BUTTON", L"VS Code", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCodeId)), instance_, nullptr);
    trash_button_ = CreateWindowW(L"BUTTON", L"Mover p/ lixeira", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTrashId)), instance_, nullptr);
    refresh_button_ = CreateWindowW(L"BUTTON", L"Atualizar", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRefreshId)), instance_, nullptr);

    if (root_label_ == nullptr || list_ == nullptr || new_button_ == nullptr ||
        files_button_ == nullptr || terminal_button_ == nullptr || code_button_ == nullptr ||
        trash_button_ == nullptr || refresh_button_ == nullptr)
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
    column.cx = 500;
    column.pszText = const_cast<wchar_t*>(L"Projeto");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 220;
    column.pszText = const_cast<wchar_t*>(L"Modificado");
    ListView_InsertColumn(list_, 1, &column);
    column.cx = 130;
    column.pszText = const_cast<wchar_t*>(L"Armazenamento");
    ListView_InsertColumn(list_, 2, &column);

    Refresh();
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeProjectsWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(1, client.right - client.left);
    const int height = std::max(1, client.bottom - client.top);
    const int margin = 12;
    const int label_height = 22;
    const int button_height = 32;
    const int bottom = height - margin - button_height;

    MoveWindow(root_label_, margin, margin, width - margin * 2, label_height, TRUE);
    MoveWindow(list_, margin, margin + label_height + 6, width - margin * 2, std::max(80, bottom - (margin + label_height + 18)), TRUE);

    int x = margin;
    const auto place = [&](HWND button, int button_width)
    {
        MoveWindow(button, x, bottom, button_width, button_height, TRUE);
        x += button_width + 8;
    };
    place(new_button_, 110);
    place(files_button_, 115);
    place(terminal_button_, 90);
    place(code_button_, 85);
    place(trash_button_, 135);
    MoveWindow(refresh_button_, std::max(x, width - margin - 100), bottom, 100, button_height, TRUE);
}

void CloudOSNativeProjectsWindow::Refresh()
{
    std::wstring error;
    std::vector<CloudOSDriveEntry> all_entries;
    if (!NativeCloudOSDrive::List(kProjectsSegments, &all_entries, &error))
    {
        ShowProjectError(window_, L"Nao foi possivel listar os projetos.", error);
        return;
    }

    entries_.clear();
    for (CloudOSDriveEntry& entry : all_entries)
    {
        if (entry.directory && !entry.reparse_point)
        {
            entries_.push_back(std::move(entry));
        }
    }

    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < entries_.size(); ++index)
    {
        CloudOSDriveEntry& entry = entries_[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = entry.name.data();
        ListView_InsertItem(list_, &item);

        std::wstring modified = FormatFileTime(entry.modified);
        ListView_SetItemText(list_, static_cast<int>(index), 1, modified.data());
        wchar_t storage[] = L"CloudOS Drive";
        ListView_SetItemText(list_, static_cast<int>(index), 2, storage);
    }
}

int CloudOSNativeProjectsWindow::SelectedIndex() const
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= entries_.size())
    {
        return -1;
    }
    return selected;
}

std::wstring CloudOSNativeProjectsWindow::SelectedProjectName() const
{
    const int selected = SelectedIndex();
    return selected < 0
        ? std::wstring{}
        : entries_[static_cast<std::size_t>(selected)].name;
}

std::wstring CloudOSNativeProjectsWindow::SelectedProjectPath() const
{
    const std::wstring name = SelectedProjectName();
    if (name.empty())
    {
        return {};
    }
    std::vector<std::wstring> segments = kProjectsSegments;
    segments.push_back(name);
    return NativeCloudOSDrive::AbsolutePath(segments);
}

void CloudOSNativeProjectsWindow::CreateProject()
{
    std::wstring name = L"Novo Projeto";
    unsigned suffix = 2u;
    while (true)
    {
        std::vector<std::wstring> segments = kProjectsSegments;
        segments.push_back(name);
        const std::wstring candidate = NativeCloudOSDrive::AbsolutePath(segments);
        if (candidate.empty() || GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES)
        {
            break;
        }
        name = L"Novo Projeto (" + std::to_wstring(suffix++) + L")";
    }

    std::vector<std::wstring> segments = kProjectsSegments;
    segments.push_back(name);
    std::wstring error;
    if (!NativeCloudOSDrive::Mkdir(segments, &error))
    {
        ShowProjectError(window_, L"Nao foi possivel criar o projeto.", error);
        return;
    }

    Refresh();
    for (int row = 0; row < ListView_GetItemCount(list_); ++row)
    {
        wchar_t buffer[260]{};
        ListView_GetItemText(list_, row, 0, buffer, static_cast<int>(std::size(buffer)));
        if (_wcsicmp(buffer, name.c_str()) == 0)
        {
            ListView_SetItemState(
                list_,
                row,
                LVIS_SELECTED | LVIS_FOCUSED,
                LVIS_SELECTED | LVIS_FOCUSED);
            ListView_EditLabel(list_, row);
            break;
        }
    }
}

void CloudOSNativeProjectsWindow::OpenSelectedFiles()
{
    const std::wstring path = SelectedProjectPath();
    if (!path.empty())
    {
        CloudOSNativeFilesWindow::Open(instance_, path);
    }
}

void CloudOSNativeProjectsWindow::OpenSelectedTerminal()
{
    const std::wstring path = SelectedProjectPath();
    if (path.empty())
    {
        return;
    }
    std::wstring command = L"cmd.exe /K cd /d \"";
    command += path;
    command += L"\"";
    std::wstring title = SelectedProjectName();
    title += L" - Terminal CloudOS";
    CloudOSNativeTerminalWindow::Open(instance_, command, title);
}

void CloudOSNativeProjectsWindow::OpenSelectedCode()
{
    const std::wstring path = SelectedProjectPath();
    if (!path.empty())
    {
        (void)LaunchCode(window_, path);
    }
}

void CloudOSNativeProjectsWindow::TrashSelected()
{
    const std::wstring name = SelectedProjectName();
    if (name.empty())
    {
        return;
    }
    if (MessageBoxW(
            window_,
            L"Mover o projeto selecionado para a Lixeira do CloudOS Drive?",
            L"Projetos - CloudOS",
            MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
    {
        return;
    }

    std::vector<std::wstring> segments = kProjectsSegments;
    segments.push_back(name);
    std::wstring error;
    if (!NativeCloudOSDrive::Trash(segments, nullptr, &error))
    {
        ShowProjectError(window_, L"Nao foi possivel mover o projeto para a lixeira.", error);
        return;
    }
    Refresh();
}

void CloudOSNativeProjectsWindow::BeginRename()
{
    const int selected = SelectedIndex();
    if (selected >= 0)
    {
        ListView_EditLabel(list_, selected);
    }
}

bool CloudOSNativeProjectsWindow::CommitRename(int row, const wchar_t* new_name)
{
    if (row < 0 || static_cast<std::size_t>(row) >= entries_.size() ||
        !IsSafeProjectName(new_name))
    {
        return false;
    }

    const std::wstring old_name = entries_[static_cast<std::size_t>(row)].name;
    if (_wcsicmp(old_name.c_str(), new_name) == 0)
    {
        return true;
    }

    std::vector<std::wstring> source = kProjectsSegments;
    source.push_back(old_name);
    std::vector<std::wstring> destination = kProjectsSegments;
    destination.emplace_back(new_name);
    std::wstring error;
    if (!NativeCloudOSDrive::Move(source, destination, &error))
    {
        ShowProjectError(window_, L"Nao foi possivel renomear o projeto.", error);
        return false;
    }

    entries_[static_cast<std::size_t>(row)].name = new_name;
    return true;
}

LRESULT CloudOSNativeProjectsWindow::HandleMessage(
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
        case kNewId:
            CreateProject();
            return 0;
        case kFilesId:
            OpenSelectedFiles();
            return 0;
        case kTerminalId:
            OpenSelectedTerminal();
            return 0;
        case kCodeId:
            OpenSelectedCode();
            return 0;
        case kTrashId:
            TrashSelected();
            return 0;
        case kRefreshId:
            Refresh();
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
                OpenSelectedFiles();
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
        if (w_param == VK_F5)
        {
            Refresh();
            return 0;
        }
        if (w_param == VK_F2)
        {
            BeginRename();
            return 0;
        }
        if (w_param == VK_DELETE)
        {
            TrashSelected();
            return 0;
        }
        if (w_param == VK_RETURN)
        {
            OpenSelectedFiles();
            return 0;
        }
        break;

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

LRESULT CALLBACK CloudOSNativeProjectsWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeProjectsWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeProjectsWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeProjectsWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}

} // namespace CloudOS
