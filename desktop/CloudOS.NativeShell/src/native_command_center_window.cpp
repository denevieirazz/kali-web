#include "native_command_center_window.h"

#include "native_system_stats.h"
#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <new>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kCommandCenterClass[] =
    L"CloudOS.NativeShell.CommandCenter.v1";

constexpr int kSearchId = 8301;
constexpr int kCategoryId = 8302;
constexpr int kListId = 8303;
constexpr int kExecuteId = 8304;
constexpr int kStatusId = 8305;
constexpr UINT_PTR kSearchSubclass = 8306;
constexpr UINT_PTR kListSubclass = 8307;
constexpr UINT_PTR kStatsTimer = 8308;

std::wstring Percent(bool available, int value)
{
    return available ? std::to_wstring(value) + L"%" : L"--";
}

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(
            control,
            WM_SETFONT,
            reinterpret_cast<WPARAM>(font),
            TRUE);
    }
}
} // namespace

CloudOSNativeCommandCenterWindow::CloudOSNativeCommandCenterWindow(
    HINSTANCE instance,
    HWND owner)
    : instance_(instance),
      owner_(owner)
{
}

CloudOSNativeCommandCenterWindow::~CloudOSNativeCommandCenterWindow()
{
    if (search_edit_ != nullptr && IsWindow(search_edit_))
    {
        RemoveWindowSubclass(
            search_edit_,
            &CloudOSNativeCommandCenterWindow::ChildSubclass,
            kSearchSubclass);
    }
    if (result_list_ != nullptr && IsWindow(result_list_))
    {
        RemoveWindowSubclass(
            result_list_,
            &CloudOSNativeCommandCenterWindow::ChildSubclass,
            kListSubclass);
    }
    if (ui_font_ != nullptr)
    {
        DeleteObject(ui_font_);
        ui_font_ = nullptr;
    }
    if (background_brush_ != nullptr)
    {
        DeleteObject(background_brush_);
        background_brush_ = nullptr;
    }
    if (edit_brush_ != nullptr)
    {
        DeleteObject(edit_brush_);
        edit_brush_ = nullptr;
    }
}

void CloudOSNativeCommandCenterWindow::Open(
    HINSTANCE instance,
    HWND owner)
{
    auto* window =
        new (std::nothrow) CloudOSNativeCommandCenterWindow(instance, owner);
    if (window == nullptr || !window->Create())
    {
        delete window;
        MessageBoxW(
            owner,
            L"Nao foi possivel abrir a Central de Comandos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeCommandCenterWindow::Create()
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc =
        &CloudOSNativeCommandCenterWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground =
        reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kCommandCenterClass;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kCommandCenterClass,
        L"Central de Comandos - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1040,
        720,
        owner_,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    background_brush_ = CreateSolidBrush(RGB(22, 24, 29));
    edit_brush_ = CreateSolidBrush(RGB(33, 36, 43));
    ui_font_ = CreateFontW(
        -16,
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI");

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
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kSearchId)),
        instance_,
        nullptr);

    category_combo_ = CreateWindowExW(
        0,
        WC_COMBOBOXW,
        L"",
        WS_CHILD |
            WS_VISIBLE |
            CBS_DROPDOWNLIST |
            WS_VSCROLL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kCategoryId)),
        instance_,
        nullptr);

    result_list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD |
            WS_VISIBLE |
            LVS_REPORT |
            LVS_SINGLESEL |
            LVS_SHOWSELALWAYS |
            LVS_NOSORTHEADER,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);

    execute_button_ = CreateWindowExW(
        0,
        L"BUTTON",
        L"Executar",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kExecuteId)),
        instance_,
        nullptr);

    status_label_ = CreateWindowExW(
        0,
        L"STATIC",
        L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kStatusId)),
        instance_,
        nullptr);

    if (search_edit_ == nullptr ||
        category_combo_ == nullptr ||
        result_list_ == nullptr ||
        execute_button_ == nullptr ||
        status_label_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    for (HWND child : {
             search_edit_,
             category_combo_,
             result_list_,
             execute_button_,
             status_label_})
    {
        SetControlFont(child, ui_font_);
    }

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(
            L"Pesquisar comandos, configuracoes e ferramentas"));

    for (int index = 0;
         index <= static_cast<int>(ShellActionCategory::Session);
         ++index)
    {
        const auto category =
            static_cast<ShellActionCategory>(index);
        SendMessageW(
            category_combo_,
            CB_ADDSTRING,
            0,
            reinterpret_cast<LPARAM>(
                NativeShellActions::CategoryLabel(category)));
    }
    SendMessageW(category_combo_, CB_SETCURSEL, 0, 0);

    ListView_SetExtendedListViewStyle(
        result_list_,
        LVS_EX_FULLROWSELECT |
            LVS_EX_DOUBLEBUFFER |
            LVS_EX_LABELTIP);

    LVCOLUMNW title_column{};
    title_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    title_column.pszText = const_cast<LPWSTR>(L"Acao");
    title_column.cx = 280;
    title_column.iSubItem = 0;
    ListView_InsertColumn(result_list_, 0, &title_column);

    LVCOLUMNW description_column{};
    description_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    description_column.pszText = const_cast<LPWSTR>(L"Descricao");
    description_column.cx = 610;
    description_column.iSubItem = 1;
    ListView_InsertColumn(result_list_, 1, &description_column);

    if (!SetWindowSubclass(
            search_edit_,
            &CloudOSNativeCommandCenterWindow::ChildSubclass,
            kSearchSubclass,
            reinterpret_cast<DWORD_PTR>(this)) ||
        !SetWindowSubclass(
            result_list_,
            &CloudOSNativeCommandCenterWindow::ChildSubclass,
            kListSubclass,
            reinterpret_cast<DWORD_PTR>(this)))
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    DarkWindow(window_);
    Layout();
    RefreshResults();
    auto_delete_ = true;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetForegroundWindow(window_);
    SetFocus(search_edit_);
    SetTimer(window_, kStatsTimer, 1000, nullptr);
    return true;
}

std::wstring CloudOSNativeCommandCenterWindow::SearchText() const
{
    if (search_edit_ == nullptr)
    {
        return {};
    }

    const int length = GetWindowTextLengthW(search_edit_);
    if (length <= 0)
    {
        return {};
    }

    std::wstring text(
        static_cast<std::size_t>(length) + 1u,
        L'\0');
    const int copied = GetWindowTextW(
        search_edit_,
        text.data(),
        length + 1);
    text.resize(
        copied > 0
            ? static_cast<std::size_t>(copied)
            : 0u);
    return text;
}

ShellActionCategory
CloudOSNativeCommandCenterWindow::SelectedCategory() const noexcept
{
    if (category_combo_ == nullptr)
    {
        return ShellActionCategory::All;
    }

    const LRESULT selection =
        SendMessageW(category_combo_, CB_GETCURSEL, 0, 0);
    if (selection < 0 ||
        selection >
            static_cast<LRESULT>(
                ShellActionCategory::Session))
    {
        return ShellActionCategory::All;
    }
    return static_cast<ShellActionCategory>(selection);
}

void CloudOSNativeCommandCenterWindow::RefreshResults(
    bool preserve_selection)
{
    if (result_list_ == nullptr)
    {
        return;
    }

    int previous = -1;
    if (preserve_selection)
    {
        previous = ListView_GetNextItem(
            result_list_,
            -1,
            LVNI_SELECTED);
    }

    filtered_ = NativeShellActions::Filter(
        SearchText(),
        SelectedCategory());

    ListView_DeleteAllItems(result_list_);
    const auto& actions = NativeShellActions::All();

    for (std::size_t row = 0; row < filtered_.size(); ++row)
    {
        const std::size_t action_index = filtered_[row];
        if (action_index >= actions.size())
        {
            continue;
        }

        const ShellAction& action = actions[action_index];
        LVITEMW item{};
        item.mask = LVIF_TEXT | LVIF_PARAM;
        item.iItem = static_cast<int>(row);
        item.iSubItem = 0;
        item.pszText =
            const_cast<LPWSTR>(action.title);
        item.lParam =
            static_cast<LPARAM>(action_index);
        const int inserted =
            ListView_InsertItem(result_list_, &item);
        if (inserted >= 0)
        {
            ListView_SetItemText(
                result_list_,
                inserted,
                1,
                const_cast<LPWSTR>(action.description));
        }
    }

    if (!filtered_.empty())
    {
        const int selection =
            preserve_selection && previous >= 0
                ? std::min(
                      previous,
                      static_cast<int>(filtered_.size()) - 1)
                : 0;
        ListView_SetItemState(
            result_list_,
            selection,
            LVIS_SELECTED | LVIS_FOCUSED,
            LVIS_SELECTED | LVIS_FOCUSED);
        ListView_EnsureVisible(
            result_list_,
            selection,
            FALSE);
    }

    UpdateStatus();
}

void CloudOSNativeCommandCenterWindow::SelectFirstResult()
{
    if (result_list_ == nullptr || filtered_.empty())
    {
        return;
    }
    ListView_SetItemState(
        result_list_,
        0,
        LVIS_SELECTED | LVIS_FOCUSED,
        LVIS_SELECTED | LVIS_FOCUSED);
    SetFocus(result_list_);
}

void CloudOSNativeCommandCenterWindow::ExecuteSelection()
{
    if (result_list_ == nullptr || filtered_.empty())
    {
        return;
    }

    int selected = ListView_GetNextItem(
        result_list_,
        -1,
        LVNI_SELECTED);
    if (selected < 0)
    {
        selected = 0;
    }
    if (selected >= static_cast<int>(filtered_.size()))
    {
        return;
    }

    const auto& actions = NativeShellActions::All();
    const std::size_t action_index =
        filtered_[static_cast<std::size_t>(selected)];
    if (action_index >= actions.size())
    {
        return;
    }

    const ShellAction& action = actions[action_index];
    const bool success = NativeShellActions::Execute(
        instance_,
        window_,
        action);

    if (!success &&
        action.kind != ShellActionKind::PowerCommand)
    {
        std::wstring message =
            L"Nao foi possivel executar: ";
        message += action.title;
        MessageBoxW(
            window_,
            message.c_str(),
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
    UpdateStatus();
}

void CloudOSNativeCommandCenterWindow::UpdateStatus()
{
    if (status_label_ == nullptr)
    {
        return;
    }

    const SystemStats stats = NativeSystemStats::Query();
    std::wstring text =
        std::to_wstring(filtered_.size()) +
        L" resultados de " +
        std::to_wstring(NativeShellActions::All().size()) +
        L" acoes  |  CPU " +
        Percent(stats.cpu_available, stats.cpu_percent) +
        L"  RAM " +
        Percent(stats.ram_available, stats.ram_percent);

    if (stats.disk_available)
    {
        text +=
            L"  Disco " +
            std::to_wstring(stats.disk_free_gb) +
            L" GB livres";
    }

    text +=
        L"  |  Enter executa  Ctrl+F busca  F5 atualiza  Esc fecha";
    SetWindowTextW(status_label_, text.c_str());
}

void CloudOSNativeCommandCenterWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const int width =
        std::max(1, static_cast<int>(client.right - client.left));
    const int height =
        std::max(1, static_cast<int>(client.bottom - client.top));
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(18, dpi);
    const int gap = Scale(10, dpi);
    const int top_height = Scale(38, dpi);
    const int combo_width = Scale(180, dpi);
    const int button_width = Scale(100, dpi);
    const int status_height = Scale(30, dpi);

    const int search_width =
        std::max(
            Scale(220, dpi),
            width -
                margin * 2 -
                combo_width -
                button_width -
                gap * 2);

    MoveWindow(
        search_edit_,
        margin,
        margin,
        search_width,
        top_height,
        TRUE);

    MoveWindow(
        category_combo_,
        margin + search_width + gap,
        margin,
        combo_width,
        Scale(260, dpi),
        TRUE);

    MoveWindow(
        execute_button_,
        width - margin - button_width,
        margin,
        button_width,
        top_height,
        TRUE);

    const int list_top =
        margin + top_height + gap;
    const int list_height =
        std::max(
            Scale(180, dpi),
            height -
                list_top -
                status_height -
                margin -
                gap);

    MoveWindow(
        result_list_,
        margin,
        list_top,
        width - margin * 2,
        list_height,
        TRUE);

    MoveWindow(
        status_label_,
        margin,
        list_top + list_height + gap,
        width - margin * 2,
        status_height,
        TRUE);

    const int total_list_width =
        std::max(300, width - margin * 2 - Scale(6, dpi));
    ListView_SetColumnWidth(
        result_list_,
        0,
        std::min(Scale(320, dpi), total_list_width / 3));
    ListView_SetColumnWidth(
        result_list_,
        1,
        std::max(
            Scale(260, dpi),
            total_list_width -
                ListView_GetColumnWidth(result_list_, 0)));
}

LRESULT CloudOSNativeCommandCenterWindow::HandleMessage(
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

    case WM_TIMER:
        if (w_param == kStatsTimer)
        {
            UpdateStatus();
            return 0;
        }
        break;

    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchId &&
            HIWORD(w_param) == EN_CHANGE)
        {
            RefreshResults();
            return 0;
        }
        if (LOWORD(w_param) == kCategoryId &&
            HIWORD(w_param) == CBN_SELCHANGE)
        {
            RefreshResults();
            SetFocus(search_edit_);
            return 0;
        }
        if (LOWORD(w_param) == kExecuteId &&
            HIWORD(w_param) == BN_CLICKED)
        {
            ExecuteSelection();
            return 0;
        }
        break;

    case WM_NOTIFY:
        if (reinterpret_cast<LPNMHDR>(l_param) != nullptr &&
            reinterpret_cast<LPNMHDR>(l_param)->idFrom ==
                static_cast<UINT_PTR>(kListId) &&
            (reinterpret_cast<LPNMHDR>(l_param)->code == NM_DBLCLK ||
             reinterpret_cast<LPNMHDR>(l_param)->code == NM_RETURN))
        {
            ExecuteSelection();
            return 0;
        }
        break;

    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, RGB(225, 229, 236));
        SetBkColor(dc, RGB(22, 24, 29));
        return reinterpret_cast<LRESULT>(background_brush_);
    }

    case WM_CTLCOLOREDIT:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, RGB(245, 247, 250));
        SetBkColor(dc, RGB(33, 36, 43));
        return reinterpret_cast<LRESULT>(edit_brush_);
    }

    case WM_CLOSE:
        DestroyWindow(window);
        return 0;

    case WM_NCDESTROY:
    {
        KillTimer(window, kStatsTimer);
        const bool should_delete = auto_delete_;
        auto_delete_ = false;
        window_ = nullptr;
        search_edit_ = nullptr;
        category_combo_ = nullptr;
        result_list_ = nullptr;
        execute_button_ = nullptr;
        status_label_ = nullptr;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        if (should_delete)
        {
            delete this;
        }
        return 0;
    }

    default:
        break;
    }

    return DefWindowProcW(
        window,
        message,
        w_param,
        l_param);
}

LRESULT CALLBACK
CloudOSNativeCommandCenterWindow::ChildSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data)
{
    auto* self =
        reinterpret_cast<CloudOSNativeCommandCenterWindow*>(
            reference_data);
    if (self == nullptr)
    {
        return DefSubclassProc(
            window,
            message,
            w_param,
            l_param);
    }

    if (message == WM_KEYDOWN)
    {
        if (w_param == VK_ESCAPE)
        {
            PostMessageW(self->window_, WM_CLOSE, 0, 0);
            return 0;
        }

        if (w_param == VK_F5)
        {
            self->RefreshResults(true);
            return 0;
        }

        if (w_param == L'F' &&
            (GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            SetFocus(self->search_edit_);
            SendMessageW(
                self->search_edit_,
                EM_SETSEL,
                0,
                -1);
            return 0;
        }

        if (subclass_id == kSearchSubclass &&
            w_param == VK_DOWN)
        {
            self->SelectFirstResult();
            return 0;
        }

        if (w_param == VK_RETURN)
        {
            self->ExecuteSelection();
            return 0;
        }
    }

    return DefSubclassProc(
        window,
        message,
        w_param,
        l_param);
}

LRESULT CALLBACK
CloudOSNativeCommandCenterWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self =
        reinterpret_cast<CloudOSNativeCommandCenterWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));

    if (message == WM_NCCREATE)
    {
        const auto* create =
            reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self =
            static_cast<CloudOSNativeCommandCenterWindow*>(
                create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(self));
    }

    if (self == nullptr)
    {
        return DefWindowProcW(
            window,
            message,
            w_param,
            l_param);
    }

    return self->HandleMessage(
        window,
        message,
        w_param,
        l_param);
}
} // namespace CloudOS
