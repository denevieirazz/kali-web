#include "native_cloudos_trash_window.h"

#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <new>
#include <string>

#pragma comment(lib, "comctl32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.DriveTrash.v1";
constexpr int kListId = 1701;
constexpr int kRestoreId = 1702;
constexpr int kDeleteId = 1703;
constexpr int kEmptyId = 1704;
constexpr int kRefreshId = 1705;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeDriveTrashWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 ||
        GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring FormatSize(unsigned long long size)
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
        swprintf_s(
            buffer,
            L"%.1f MB",
            static_cast<double>(size) / (1024.0 * 1024.0));
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

std::wstring OriginalLocation(const CloudOSDriveTrashEntry& entry)
{
    std::wstring result = L"CloudOS Drive";
    for (const std::wstring& part : entry.original_path)
    {
        result += L"\\";
        result += part;
    }
    return result;
}

void ShowDriveError(HWND owner, const wchar_t* action, const std::wstring& detail)
{
    std::wstring message = action;
    if (!detail.empty())
    {
        message += L"\n\n";
        message += detail;
    }
    MessageBoxW(owner, message.c_str(), L"CloudOS Drive", MB_OK | MB_ICONWARNING);
}
}

CloudOSNativeDriveTrashWindow::CloudOSNativeDriveTrashWindow(
    HINSTANCE instance) noexcept
    : instance_(instance)
{
}

void CloudOSNativeDriveTrashWindow::Open(HINSTANCE instance)
{
    auto* trash = new (std::nothrow) CloudOSNativeDriveTrashWindow(instance);
    if (trash == nullptr || !trash->Create())
    {
        delete trash;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir a Lixeira do CloudOS Drive.",
            L"CloudOS Drive",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeDriveTrashWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Lixeira - CloudOS Drive",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        920,
        560,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }
    DarkWindow(window_);

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
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    restore_button_ = CreateWindowW(
        L"BUTTON",
        L"Restaurar",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRestoreId)),
        instance_,
        nullptr);
    delete_button_ = CreateWindowW(
        L"BUTTON",
        L"Excluir definitivamente",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDeleteId)),
        instance_,
        nullptr);
    empty_button_ = CreateWindowW(
        L"BUTTON",
        L"Esvaziar lixeira",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEmptyId)),
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
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRefreshId)),
        instance_,
        nullptr);

    if (list_ == nullptr || restore_button_ == nullptr || delete_button_ == nullptr ||
        empty_button_ == nullptr || refresh_button_ == nullptr)
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
    column.cx = 230;
    column.pszText = const_cast<wchar_t*>(L"Nome original");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 290;
    column.pszText = const_cast<wchar_t*>(L"Local original");
    ListView_InsertColumn(list_, 1, &column);
    column.cx = 175;
    column.pszText = const_cast<wchar_t*>(L"Excluido em");
    ListView_InsertColumn(list_, 2, &column);
    column.cx = 80;
    column.pszText = const_cast<wchar_t*>(L"Tipo");
    ListView_InsertColumn(list_, 3, &column);
    column.cx = 95;
    column.pszText = const_cast<wchar_t*>(L"Tamanho");
    ListView_InsertColumn(list_, 4, &column);

    Refresh();
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeDriveTrashWindow::Layout()
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
    const int button_height = 32;
    const int bottom = height - margin - button_height;

    MoveWindow(list_, margin, margin, width - margin * 2, std::max(80, bottom - margin * 2), TRUE);
    MoveWindow(restore_button_, margin, bottom, 110, button_height, TRUE);
    MoveWindow(delete_button_, margin + 118, bottom, 170, button_height, TRUE);
    MoveWindow(empty_button_, margin + 296, bottom, 145, button_height, TRUE);
    MoveWindow(refresh_button_, std::max(margin + 450, width - margin - 100), bottom, 100, button_height, TRUE);
}

void CloudOSNativeDriveTrashWindow::Refresh()
{
    std::wstring error;
    std::vector<CloudOSDriveTrashEntry> entries;
    if (!NativeCloudOSDrive::ListTrash(&entries, &error))
    {
        ShowDriveError(window_, L"Nao foi possivel listar a lixeira.", error);
        return;
    }

    entries_ = std::move(entries);
    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < entries_.size(); ++index)
    {
        CloudOSDriveTrashEntry& entry = entries_[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = entry.original_name.data();
        ListView_InsertItem(list_, &item);

        std::wstring location = OriginalLocation(entry);
        ListView_SetItemText(list_, static_cast<int>(index), 1, location.data());
        ListView_SetItemText(list_, static_cast<int>(index), 2, entry.deleted_at.data());
        wchar_t type[16]{};
        wcscpy_s(type, entry.directory ? L"Pasta" : L"Arquivo");
        ListView_SetItemText(list_, static_cast<int>(index), 3, type);
        std::wstring size = entry.directory ? std::wstring{} : FormatSize(entry.size);
        ListView_SetItemText(list_, static_cast<int>(index), 4, size.data());
    }
}

int CloudOSNativeDriveTrashWindow::SelectedIndex() const
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= entries_.size())
    {
        return -1;
    }
    return selected;
}

void CloudOSNativeDriveTrashWindow::RestoreSelected()
{
    const int selected = SelectedIndex();
    if (selected < 0)
    {
        return;
    }
    std::wstring error;
    if (!NativeCloudOSDrive::RestoreTrash(
            entries_[static_cast<std::size_t>(selected)].id,
            &error))
    {
        ShowDriveError(window_, L"Nao foi possivel restaurar o item.", error);
        return;
    }
    Refresh();
}

void CloudOSNativeDriveTrashWindow::DeleteSelected()
{
    const int selected = SelectedIndex();
    if (selected < 0)
    {
        return;
    }
    if (MessageBoxW(
            window_,
            L"Excluir definitivamente o item selecionado? Esta acao nao pode ser desfeita.",
            L"CloudOS Drive",
            MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
    {
        return;
    }

    std::wstring error;
    if (!NativeCloudOSDrive::DeleteTrash(
            entries_[static_cast<std::size_t>(selected)].id,
            &error))
    {
        ShowDriveError(window_, L"Nao foi possivel excluir o item.", error);
        return;
    }
    Refresh();
}

void CloudOSNativeDriveTrashWindow::EmptyTrash()
{
    if (entries_.empty())
    {
        return;
    }
    if (MessageBoxW(
            window_,
            L"Esvaziar toda a Lixeira do CloudOS Drive? Esta acao nao pode ser desfeita.",
            L"CloudOS Drive",
            MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
    {
        return;
    }

    std::wstring error;
    std::size_t deleted = 0u;
    if (!NativeCloudOSDrive::EmptyTrash(&deleted, &error))
    {
        std::wstring detail = error;
        detail += L"\nItens removidos antes da falha: ";
        detail += std::to_wstring(deleted);
        ShowDriveError(window_, L"A lixeira nao foi esvaziada por completo.", detail);
        Refresh();
        return;
    }
    Refresh();
}

LRESULT CloudOSNativeDriveTrashWindow::HandleMessage(
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
        case kRestoreId:
            RestoreSelected();
            return 0;
        case kDeleteId:
            DeleteSelected();
            return 0;
        case kEmptyId:
            EmptyTrash();
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
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_ && header->code == NM_DBLCLK)
        {
            RestoreSelected();
            return 0;
        }
        break;
    }

    case WM_KEYDOWN:
        if (w_param == VK_F5)
        {
            Refresh();
            return 0;
        }
        if (w_param == VK_DELETE)
        {
            DeleteSelected();
            return 0;
        }
        if (w_param == VK_RETURN)
        {
            RestoreSelected();
            return 0;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;

    case WM_NCDESTROY:
        window_ = nullptr;
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
        delete this;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeDriveTrashWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeDriveTrashWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeDriveTrashWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeDriveTrashWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}

} // namespace CloudOS
