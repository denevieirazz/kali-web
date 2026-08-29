#include "native_start_menu_window.h"

#include "native_app_launcher.h"
#include "native_search_engine.h"
#include "native_start_menu_mru.h"
#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <array>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kStartClass[] = L"CloudOS.NativeShell.Start.v2";
constexpr int kSearchId = 9001;
constexpr int kListId = 9002;
constexpr int kCommandId = 9003;
constexpr int kPowerId = 9004;
constexpr UINT_PTR kSearchSubclass = 9005;

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

std::wstring SearchText(HWND edit)
{
    if (edit == nullptr)
    {
        return {};
    }
    const int length = GetWindowTextLengthW(edit);
    if (length <= 0)
    {
        return {};
    }
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(edit, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return value;
}
}

CloudOSNativeStartMenuWindow::~CloudOSNativeStartMenuWindow()
{
    Destroy();
}

bool CloudOSNativeStartMenuWindow::Create(HINSTANCE instance)
{
    instance_ = instance;

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeStartMenuWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kStartClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kStartClass,
        L"Iniciar - CloudOS",
        WS_POPUP | WS_BORDER | WS_CLIPCHILDREN,
        0,
        0,
        620,
        650,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    background_ = CreateSolidBrush(RGB(24, 26, 31));
    edit_background_ = CreateSolidBrush(RGB(34, 37, 44));
    font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    title_font_ = CreateFontW(
        -20, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    search_edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSearchId)),
        instance_,
        nullptr);
    app_list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    command_button_ = CreateWindowW(
        L"BUTTON",
        L"Central de Comandos",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCommandId)),
        instance_,
        nullptr);
    power_button_ = CreateWindowW(
        L"BUTTON",
        L"Energia",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPowerId)),
        instance_,
        nullptr);
    footer_label_ = CreateWindowW(
        L"STATIC",
        L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0,
        window_,
        nullptr,
        instance_,
        nullptr);

    if (search_edit_ == nullptr || app_list_ == nullptr || command_button_ == nullptr ||
        power_button_ == nullptr || footer_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    SetControlFont(search_edit_, font_);
    SetControlFont(app_list_, font_);
    SetControlFont(command_button_, font_);
    SetControlFont(power_button_, font_);
    SetControlFont(footer_label_, font_);

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar aplicativos do CloudOS"));

    if (!SetWindowSubclass(
            search_edit_,
            &CloudOSNativeStartMenuWindow::SearchSubclass,
            kSearchSubclass,
            reinterpret_cast<DWORD_PTR>(this)))
    {
        Destroy();
        return false;
    }

    ListView_SetExtendedListViewStyle(
        app_list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    LVCOLUMNW app_column{};
    app_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    app_column.pszText = const_cast<LPWSTR>(L"Aplicativo");
    app_column.cx = 190;
    ListView_InsertColumn(app_list_, 0, &app_column);

    LVCOLUMNW description_column{};
    description_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    description_column.pszText = const_cast<LPWSTR>(L"Descricao");
    description_column.cx = 370;
    description_column.iSubItem = 1;
    ListView_InsertColumn(app_list_, 1, &description_column);

    DarkWindow(window_);
    Layout();
    RefreshResults();
    return true;
}

void CloudOSNativeStartMenuWindow::Destroy()
{
    if (search_edit_ != nullptr && IsWindow(search_edit_))
    {
        RemoveWindowSubclass(search_edit_, &CloudOSNativeStartMenuWindow::SearchSubclass, kSearchSubclass);
    }
    if (window_ != nullptr && IsWindow(window_))
    {
        DestroyWindow(window_);
    }
    window_ = nullptr;
    search_edit_ = nullptr;
    app_list_ = nullptr;
    command_button_ = nullptr;
    power_button_ = nullptr;
    footer_label_ = nullptr;
    results_.clear();

    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (title_font_ != nullptr)
    {
        DeleteObject(title_font_);
        title_font_ = nullptr;
    }
    if (background_ != nullptr)
    {
        DeleteObject(background_);
        background_ = nullptr;
    }
    if (edit_background_ != nullptr)
    {
        DeleteObject(edit_background_);
        edit_background_ = nullptr;
    }
}

void CloudOSNativeStartMenuWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(18, dpi);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    const int search_height = Scale(40, dpi);
    const int footer_height = Scale(48, dpi);

    MoveWindow(search_edit_, margin, margin, width - margin * 2, search_height, TRUE);
    MoveWindow(
        app_list_,
        margin,
        margin + search_height + Scale(14, dpi),
        width - margin * 2,
        std::max(1, height - margin * 3 - search_height - footer_height - Scale(14, dpi)),
        TRUE);

    const int footer_y = height - margin - footer_height;
    MoveWindow(footer_label_, margin, footer_y + Scale(10, dpi), Scale(180, dpi), Scale(28, dpi), TRUE);
    MoveWindow(command_button_, width - margin - Scale(260, dpi), footer_y + Scale(6, dpi), Scale(170, dpi), Scale(34, dpi), TRUE);
    MoveWindow(power_button_, width - margin - Scale(82, dpi), footer_y + Scale(6, dpi), Scale(82, dpi), Scale(34, dpi), TRUE);
}

void CloudOSNativeStartMenuWindow::RefreshResults()
{
    if (app_list_ == nullptr)
    {
        return;
    }

    results_ = NativeSearchEngine::FilterApps(SearchText(search_edit_));
    ListView_DeleteAllItems(app_list_);

    for (std::size_t row = 0; row < results_.size(); ++row)
    {
        const int app_index = results_[row];
        if (app_index < 0 || app_index >= static_cast<int>(kAllApps.size()))
        {
            continue;
        }
        const AppItem& app = kAllApps[static_cast<std::size_t>(app_index)];

        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(row);
        item.pszText = const_cast<LPWSTR>(app.name);
        ListView_InsertItem(app_list_, &item);
        ListView_SetItemText(app_list_, static_cast<int>(row), 1, const_cast<LPWSTR>(app.desc));
    }

    if (!results_.empty())
    {
        ListView_SetItemState(app_list_, 0, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    }

    const std::vector<std::wstring> recent = StartMenuMRUTracker::Instance().GetTopApps(3);
    std::wstring footer = L"Recentes: ";
    if (recent.empty())
    {
        footer += L"nenhum";
    }
    else
    {
        for (std::size_t index = 0; index < recent.size(); ++index)
        {
            if (index != 0) footer += L", ";
            footer += recent[index];
        }
    }
    SetWindowTextW(footer_label_, footer.c_str());
}

void CloudOSNativeStartMenuWindow::ExecuteSelection()
{
    if (app_list_ == nullptr)
    {
        return;
    }
    const int selected = ListView_GetNextItem(app_list_, -1, LVNI_SELECTED);
    if (selected < 0 || selected >= static_cast<int>(results_.size()))
    {
        return;
    }
    const int app_index = results_[static_cast<std::size_t>(selected)];
    if (app_index < 0 || app_index >= static_cast<int>(kAllApps.size()))
    {
        return;
    }

    Hide();
    NativeAppLauncher::Launch(instance_, nullptr, kAllApps[static_cast<std::size_t>(app_index)]);
}

void CloudOSNativeStartMenuWindow::MoveSelection(int delta)
{
    if (app_list_ == nullptr || results_.empty())
    {
        return;
    }
    int selected = ListView_GetNextItem(app_list_, -1, LVNI_SELECTED);
    if (selected < 0) selected = 0;
    selected = std::clamp(selected + delta, 0, static_cast<int>(results_.size()) - 1);
    ListView_SetItemState(app_list_, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_SetItemState(app_list_, selected, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_EnsureVisible(app_list_, selected, FALSE);
}

void CloudOSNativeStartMenuWindow::ShowNear(const RECT& taskbar_bounds)
{
    if (window_ == nullptr)
    {
        return;
    }

    SetWindowTextW(search_edit_, L"");
    RefreshResults();

    HMONITOR monitor = MonitorFromRect(&taskbar_bounds, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(620, dpi);
    const int height = Scale(650, dpi);
    int x = taskbar_bounds.left + (taskbar_bounds.right - taskbar_bounds.left - width) / 2;
    int y = taskbar_bounds.top - height - Scale(8, dpi);
    x = std::clamp(x, info.rcWork.left, std::max(info.rcWork.left, info.rcWork.right - width));
    y = std::clamp(y, info.rcWork.top, std::max(info.rcWork.top, info.rcWork.bottom - height));

    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    FocusSearch();
}

void CloudOSNativeStartMenuWindow::ToggleNear(const RECT& taskbar_bounds)
{
    if (window_ == nullptr)
    {
        return;
    }
    IsWindowVisible(window_) ? Hide() : ShowNear(taskbar_bounds);
}

void CloudOSNativeStartMenuWindow::Hide()
{
    if (window_ != nullptr)
    {
        ShowWindow(window_, SW_HIDE);
    }
}

void CloudOSNativeStartMenuWindow::FocusSearch()
{
    if (search_edit_ != nullptr)
    {
        SetFocus(search_edit_);
        SendMessageW(search_edit_, EM_SETSEL, 0, -1);
    }
}

LRESULT CloudOSNativeStartMenuWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE)
        {
            Hide();
        }
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchId && HIWORD(w_param) == EN_CHANGE)
        {
            RefreshResults();
            return 0;
        }
        if (LOWORD(w_param) == kCommandId)
        {
            Hide();
            NativeAppLauncher::LaunchById(instance_, nullptr, L"control");
            return 0;
        }
        if (LOWORD(w_param) == kPowerId)
        {
            POINT point{};
            RECT rect{};
            GetWindowRect(power_button_, &rect);
            point.x = rect.right;
            point.y = rect.top;
            NativeAppLauncher::ShowQuickPowerMenu(window_, point);
            return 0;
        }
        break;
    case WM_NOTIFY:
    {
        const auto* notification = reinterpret_cast<const NMHDR*>(l_param);
        if (notification != nullptr && notification->hwndFrom == app_list_ &&
            (notification->code == NM_DBLCLK || notification->code == NM_RETURN))
        {
            ExecuteSelection();
            return 0;
        }
        break;
    }
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE)
        {
            Hide();
            return 0;
        }
        break;
    case WM_CTLCOLOREDIT:
        if (reinterpret_cast<HWND>(l_param) == search_edit_)
        {
            HDC dc = reinterpret_cast<HDC>(w_param);
            SetTextColor(dc, RGB(244, 247, 251));
            SetBkColor(dc, RGB(34, 37, 44));
            return reinterpret_cast<LRESULT>(edit_background_);
        }
        break;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, RGB(236, 240, 247));
        SetBkColor(dc, RGB(24, 26, 31));
        return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(window_, &client);
        FillRect(reinterpret_cast<HDC>(w_param), &client, background_);
        return 1;
    }
    case WM_DESTROY:
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeStartMenuWindow::SearchSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR,
    DWORD_PTR reference_data)
{
    auto* self = reinterpret_cast<CloudOSNativeStartMenuWindow*>(reference_data);
    if (self != nullptr && message == WM_KEYDOWN)
    {
        switch (w_param)
        {
        case VK_ESCAPE:
            self->Hide();
            return 0;
        case VK_RETURN:
            self->ExecuteSelection();
            return 0;
        case VK_DOWN:
            self->MoveSelection(1);
            SetFocus(self->app_list_);
            return 0;
        case VK_UP:
            self->MoveSelection(-1);
            return 0;
        default:
            break;
        }
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeStartMenuWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeStartMenuWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeStartMenuWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
