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
constexpr wchar_t kStartClass[] = L"CloudOS.NativeShell.Start.v3";
constexpr int kSearchId = 9001;
constexpr int kListId = 9002;
constexpr int kCommandId = 9003;
constexpr int kPowerId = 9004;
constexpr int kRefreshId = 9005;
constexpr UINT_PTR kSearchSubclass = 9006;
constexpr UINT_PTR kIndexTimer = 9007;

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
        720,
        690,
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
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -20, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    search_edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSearchId)),
        instance_,
        nullptr);
    refresh_button_ = CreateWindowW(
        L"BUTTON",
        L"Reindexar",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRefreshId)),
        instance_,
        nullptr);
    app_list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    command_button_ = CreateWindowW(
        L"BUTTON",
        L"Central de Comandos",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCommandId)),
        instance_,
        nullptr);
    power_button_ = CreateWindowW(
        L"BUTTON",
        L"Energia",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
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

    if (search_edit_ == nullptr || refresh_button_ == nullptr || app_list_ == nullptr ||
        command_button_ == nullptr || power_button_ == nullptr || footer_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    for (HWND child : {search_edit_, refresh_button_, app_list_, command_button_, power_button_, footer_label_})
    {
        SetControlFont(child, font_);
    }

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar CloudOS, Menu Iniciar e aplicativos instalados"));

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
    app_column.cx = 270;
    ListView_InsertColumn(app_list_, 0, &app_column);

    LVCOLUMNW description_column{};
    description_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    description_column.pszText = const_cast<LPWSTR>(L"Origem / descricao");
    description_column.cx = 385;
    description_column.iSubItem = 1;
    ListView_InsertColumn(app_list_, 1, &description_column);

    DarkWindow(window_);
    Layout();
    NativeStartIndex::Instance().StartAsync();
    last_index_count_ = NativeStartIndex::Instance().Count();
    RefreshResults();
    SetTimer(window_, kIndexTimer, 750, nullptr);
    return true;
}

void CloudOSNativeStartMenuWindow::Destroy()
{
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kIndexTimer);
    }
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
    refresh_button_ = nullptr;
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
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));
    const int search_height = Scale(40, dpi);
    const int refresh_width = Scale(92, dpi);
    const int footer_height = Scale(52, dpi);

    MoveWindow(
        search_edit_,
        margin,
        margin,
        std::max(80, width - margin * 3 - refresh_width),
        search_height,
        TRUE);
    MoveWindow(
        refresh_button_,
        width - margin - refresh_width,
        margin,
        refresh_width,
        search_height,
        TRUE);

    const int list_y = margin + search_height + Scale(14, dpi);
    const int footer_y = height - margin - footer_height;
    MoveWindow(
        app_list_,
        margin,
        list_y,
        width - margin * 2,
        std::max(80, footer_y - list_y - Scale(10, dpi)),
        TRUE);

    MoveWindow(footer_label_, margin, footer_y + Scale(9, dpi), std::max(100, width - Scale(380, dpi)), Scale(34, dpi), TRUE);
    MoveWindow(command_button_, width - margin - Scale(270, dpi), footer_y + Scale(6, dpi), Scale(176, dpi), Scale(36, dpi), TRUE);
    MoveWindow(power_button_, width - margin - Scale(86, dpi), footer_y + Scale(6, dpi), Scale(86, dpi), Scale(36, dpi), TRUE);

    ListView_SetColumnWidth(app_list_, 0, std::max(180, (width - margin * 2) * 42 / 100));
    ListView_SetColumnWidth(app_list_, 1, LVSCW_AUTOSIZE_USEHEADER);
}

void CloudOSNativeStartMenuWindow::RefreshResults()
{
    if (app_list_ == nullptr)
    {
        return;
    }

    const std::wstring query = SearchText(search_edit_);
    results_.clear();
    ListView_DeleteAllItems(app_list_);

    const std::vector<int> cloud_results = NativeSearchEngine::FilterApps(query);
    const std::size_t cloud_limit = query.empty() ? 12u : 24u;
    for (std::size_t index = 0; index < cloud_results.size() && index < cloud_limit; ++index)
    {
        const int app_index = cloud_results[index];
        if (app_index < 0 || app_index >= static_cast<int>(kAllApps.size()))
        {
            continue;
        }
        ResultRow row{};
        row.kind = ResultKind::CloudOSApp;
        row.cloud_app_index = app_index;
        results_.push_back(std::move(row));
    }

    const std::size_t windows_limit = query.empty() ? 28u : 60u;
    const auto indexed_results = NativeStartIndex::Instance().Query(query, windows_limit);
    for (const auto& indexed : indexed_results)
    {
        ResultRow row{};
        row.kind = ResultKind::IndexedWindowsApp;
        row.indexed = indexed;
        results_.push_back(std::move(row));
    }

    for (std::size_t row_index = 0; row_index < results_.size(); ++row_index)
    {
        const ResultRow& result = results_[row_index];
        std::wstring title;
        std::wstring description;
        if (result.kind == ResultKind::CloudOSApp)
        {
            const AppItem& app = kAllApps[static_cast<std::size_t>(result.cloud_app_index)];
            title = app.name;
            description = L"CloudOS  •  ";
            description += app.desc;
        }
        else
        {
            title = result.indexed.title;
            description = result.indexed.subtitle;
        }

        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(row_index);
        item.pszText = title.data();
        ListView_InsertItem(app_list_, &item);
        ListView_SetItemText(app_list_, static_cast<int>(row_index), 1, description.data());
    }

    if (!results_.empty())
    {
        ListView_SetItemState(app_list_, 0, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    }

    const auto recent = StartMenuMRUTracker::Instance().GetTopApps(3);
    std::wstring footer;
    if (NativeStartIndex::Instance().Indexing())
    {
        footer = L"Indexando aplicativos do Windows...";
    }
    else
    {
        footer = std::to_wstring(kAllApps.size());
        footer += L" apps CloudOS  •  ";
        footer += std::to_wstring(NativeStartIndex::Instance().Count());
        footer += L" apps Windows";
    }
    if (!recent.empty())
    {
        footer += L"  •  Recentes: ";
        for (std::size_t index = 0; index < recent.size(); ++index)
        {
            if (index != 0)
            {
                footer += L", ";
            }
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

    const ResultRow result = results_[static_cast<std::size_t>(selected)];
    Hide();
    if (result.kind == ResultKind::CloudOSApp)
    {
        if (result.cloud_app_index >= 0 && result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            NativeAppLauncher::Launch(instance_, nullptr, kAllApps[static_cast<std::size_t>(result.cloud_app_index)]);
        }
        return;
    }

    if (!NativeStartIndex::Instance().Launch(nullptr, result.indexed))
    {
        MessageBoxW(
            nullptr,
            L"O Windows nao conseguiu abrir este aplicativo indexado.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

void CloudOSNativeStartMenuWindow::MoveSelection(int delta)
{
    if (app_list_ == nullptr || results_.empty())
    {
        return;
    }
    int selected = ListView_GetNextItem(app_list_, -1, LVNI_SELECTED);
    if (selected < 0)
    {
        selected = 0;
    }
    selected = std::clamp(selected + delta, 0, static_cast<int>(results_.size()) - 1);
    ListView_SetItemState(app_list_, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_SetItemState(app_list_, selected, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_EnsureVisible(app_list_, selected, FALSE);
}

void CloudOSNativeStartMenuWindow::RefreshIndexer()
{
    NativeStartIndex::Instance().RefreshAsync();
    last_index_count_ = 0;
    RefreshResults();
}

void CloudOSNativeStartMenuWindow::ShowNear(const RECT& taskbar_bounds)
{
    if (window_ == nullptr)
    {
        return;
    }

    NativeStartIndex::Instance().StartAsync();
    SetWindowTextW(search_edit_, L"");
    RefreshResults();

    HMONITOR monitor = MonitorFromRect(&taskbar_bounds, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(720, dpi);
    const int height = Scale(690, dpi);
    int x = taskbar_bounds.left + (taskbar_bounds.right - taskbar_bounds.left - width) / 2;
    int y = taskbar_bounds.top - height - Scale(8, dpi);
    x = std::clamp<int>(x, static_cast<int>(info.rcWork.left), std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(y, static_cast<int>(info.rcWork.top), std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));

    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    FocusSearch();
}

void CloudOSNativeStartMenuWindow::ToggleNear(const RECT& taskbar_bounds)
{
    if (window_ != nullptr)
    {
        IsWindowVisible(window_) ? Hide() : ShowNear(taskbar_bounds);
    }
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
    case WM_TIMER:
        if (w_param == kIndexTimer)
        {
            const std::size_t count = NativeStartIndex::Instance().Count();
            if (count != last_index_count_ || NativeStartIndex::Instance().Indexing())
            {
                last_index_count_ = count;
                RefreshResults();
            }
            return 0;
        }
        break;
    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchId && HIWORD(w_param) == EN_CHANGE)
        {
            RefreshResults();
            return 0;
        }
        if (LOWORD(w_param) == kRefreshId)
        {
            RefreshIndexer();
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
        if (w_param == VK_F5)
        {
            RefreshIndexer();
            return 0;
        }
        break;
    case WM_CTLCOLOREDIT:
        SetTextColor(reinterpret_cast<HDC>(w_param), RGB(240, 244, 248));
        SetBkColor(reinterpret_cast<HDC>(w_param), RGB(34, 37, 44));
        return reinterpret_cast<LRESULT>(edit_background_);
    case WM_CTLCOLORSTATIC:
        SetTextColor(reinterpret_cast<HDC>(w_param), RGB(184, 191, 203));
        SetBkColor(reinterpret_cast<HDC>(w_param), RGB(24, 26, 31));
        return reinterpret_cast<LRESULT>(background_);
    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(window_, &client);
        FillRect(reinterpret_cast<HDC>(w_param), &client, background_);
        return 1;
    }
    case WM_CLOSE:
        Hide();
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
    UINT_PTR subclass_id,
    DWORD_PTR reference_data)
{
    auto* self = reinterpret_cast<CloudOSNativeStartMenuWindow*>(reference_data);
    if (message == WM_KEYDOWN && self != nullptr)
    {
        switch (w_param)
        {
        case VK_DOWN:
            self->MoveSelection(1);
            SetFocus(self->app_list_);
            return 0;
        case VK_UP:
            self->MoveSelection(-1);
            SetFocus(self->app_list_);
            return 0;
        case VK_RETURN:
            self->ExecuteSelection();
            return 0;
        case VK_ESCAPE:
            self->Hide();
            return 0;
        case VK_F5:
            self->RefreshIndexer();
            return 0;
        default:
            break;
        }
    }
    if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, SearchSubclass, subclass_id);
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeStartMenuWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeStartMenuWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeStartMenuWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeStartMenuWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    if (message == WM_NCDESTROY)
    {
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    }

    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
