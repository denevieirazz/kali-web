#include "native_workspace_overview_window.h"

#include "native_theme.h"
#include "native_window_manager.h"

#include <commctrl.h>
#include <gdiplus.h>
#include <uxtheme.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <string>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "uxtheme.lib")

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kOverviewClass[] = L"CloudOS.NativeShell.WorkspaceOverview.v1";
constexpr UINT_PTR kRefreshTimer = 0xBC01;
constexpr UINT_PTR kControlSubclass = 0xBC02;

constexpr int kSearchId = 12001;
constexpr int kListId = 12002;
constexpr int kWorkspaceComboId = 12003;
constexpr int kFocusId = 12004;
constexpr int kMoveId = 12005;
constexpr int kFloatingId = 12006;
constexpr int kMinimizeId = 12007;
constexpr int kMaximizeId = 12008;
constexpr int kCloseId = 12009;
constexpr int kTilingId = 12010;

constexpr UINT kContextFocus = 12101;
constexpr UINT kContextFloating = 12102;
constexpr UINT kContextMinimize = 12103;
constexpr UINT kContextMaximize = 12104;
constexpr UINT kContextClose = 12105;
constexpr UINT kContextMove1 = 12111;
constexpr UINT kContextMove2 = 12112;
constexpr UINT kContextMove3 = 12113;
constexpr UINT kContextMove4 = 12114;
constexpr UINT kContextTile = 12120;

constexpr int kWindowWidthDip = 1180;
constexpr int kWindowHeightDip = 780;

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

std::wstring ReadText(HWND control)
{
    if (control == nullptr)
    {
        return {};
    }
    const int length = GetWindowTextLengthW(control);
    if (length <= 0)
    {
        return {};
    }
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(control, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return value;
}

std::wstring Lower(std::wstring value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t character)
        {
            return static_cast<wchar_t>(std::towlower(character));
        });
    return value;
}

void DrawTextLine(
    HDC dc,
    HFONT font,
    COLORREF color,
    const std::wstring& text,
    RECT rect,
    UINT flags)
{
    if (dc == nullptr || text.empty())
    {
        return;
    }
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;
    const int old_mode = SetBkMode(dc, TRANSPARENT);
    const COLORREF old_color = SetTextColor(dc, color);
    DrawTextW(dc, text.c_str(), -1, &rect, flags | DT_NOPREFIX);
    SetTextColor(dc, old_color);
    SetBkMode(dc, old_mode);
    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }
}

std::wstring WorkspaceLabel(int workspace)
{
    return L"Área " + std::to_wstring(workspace + 1);
}

int WrappedWorkspace(int workspace, int direction) noexcept
{
    constexpr int kCount = 4;
    if (workspace < 0 || workspace >= kCount)
    {
        workspace = 0;
    }
    return (workspace + direction + kCount) % kCount;
}
}

CloudOSNativeWorkspaceOverviewWindow::~CloudOSNativeWorkspaceOverviewWindow()
{
    Destroy();
}

bool CloudOSNativeWorkspaceOverviewWindow::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    Destroy();
    if (instance == nullptr || window_manager == nullptr)
    {
        return false;
    }

    instance_ = instance;
    window_manager_ = window_manager;

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeWorkspaceOverviewWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kOverviewClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        Destroy();
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        kOverviewClass,
        L"Visão de Trabalho - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        kWindowWidthDip,
        kWindowHeightDip,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        Destroy();
        return false;
    }

    const UINT dpi = GetDpiForWindow(window_);
    font_ = CreateFontW(
        -Scale(13, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    small_font_ = CreateFontW(
        -Scale(10, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(20, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    background_ = CreateSolidBrush(WebSkin::BgPrimary);
    edit_background_ = CreateSolidBrush(WebSkin::BgTertiary);

    search_edit_ = CreateWindowExW(
        0, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSearchId)),
        instance_,
        nullptr);
    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    workspace_combo_ = CreateWindowExW(
        0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWorkspaceComboId)),
        instance_,
        nullptr);

    focus_button_ = CreateWindowW(
        L"BUTTON", L"Focar", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFocusId)), instance_, nullptr);
    move_button_ = CreateWindowW(
        L"BUTTON", L"Mover", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMoveId)), instance_, nullptr);
    floating_button_ = CreateWindowW(
        L"BUTTON", L"Flutuante", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFloatingId)), instance_, nullptr);
    minimize_button_ = CreateWindowW(
        L"BUTTON", L"Minimizar", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMinimizeId)), instance_, nullptr);
    maximize_button_ = CreateWindowW(
        L"BUTTON", L"Maximizar", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMaximizeId)), instance_, nullptr);
    close_button_ = CreateWindowW(
        L"BUTTON", L"Fechar", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCloseId)), instance_, nullptr);
    tiling_button_ = CreateWindowW(
        L"BUTTON", L"Tiling", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTilingId)), instance_, nullptr);
    status_label_ = CreateWindowW(
        L"STATIC", L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0,
        window_, nullptr, instance_, nullptr);

    if (search_edit_ == nullptr || list_ == nullptr || workspace_combo_ == nullptr ||
        focus_button_ == nullptr || move_button_ == nullptr || floating_button_ == nullptr ||
        minimize_button_ == nullptr || maximize_button_ == nullptr || close_button_ == nullptr ||
        tiling_button_ == nullptr || status_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    for (HWND child : {
             search_edit_, list_, workspace_combo_, focus_button_, move_button_, floating_button_,
             minimize_button_, maximize_button_, close_button_, tiling_button_, status_label_})
    {
        SetControlFont(child, font_);
    }
    SetControlFont(status_label_, small_font_);

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar janela, PID ou área"));
    if (!SetWindowSubclass(
            search_edit_,
            &CloudOSNativeWorkspaceOverviewWindow::SearchSubclass,
            kControlSubclass,
            reinterpret_cast<DWORD_PTR>(this)) ||
        !SetWindowSubclass(
            list_,
            &CloudOSNativeWorkspaceOverviewWindow::SearchSubclass,
            kControlSubclass,
            reinterpret_cast<DWORD_PTR>(this)))
    {
        Destroy();
        return false;
    }

    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(list_, WebSkin::BgSecondary);
    ListView_SetTextBkColor(list_, WebSkin::BgSecondary);
    ListView_SetTextColor(list_, WebSkin::TextPrimary);
    SetWindowTheme(list_, L"DarkMode_Explorer", nullptr);
    SetWindowTheme(search_edit_, L"DarkMode_CFD", nullptr);
    SetWindowTheme(workspace_combo_, L"DarkMode_CFD", nullptr);

    const struct Column final
    {
        const wchar_t* title;
        int width;
    } columns[] = {
        {L"Janela", 360},
        {L"Área", 92},
        {L"Modo", 96},
        {L"PID", 82},
    };
    for (int index = 0; index < static_cast<int>(std::size(columns)); ++index)
    {
        LVCOLUMNW column{};
        column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
        column.iSubItem = index;
        column.cx = Scale(columns[index].width, dpi);
        column.pszText = const_cast<LPWSTR>(columns[index].title);
        ListView_InsertColumn(list_, index, &column);
    }

    for (int workspace = 0; workspace < 4; ++workspace)
    {
        const std::wstring label = WorkspaceLabel(workspace);
        SendMessageW(
            workspace_combo_,
            CB_ADDSTRING,
            0,
            reinterpret_cast<LPARAM>(label.c_str()));
    }
    SendMessageW(workspace_combo_, CB_SETCURSEL, 0, 0);

    for (HWND button : {
             focus_button_, move_button_, floating_button_, minimize_button_,
             maximize_button_, close_button_, tiling_button_})
    {
        WebSkin::PrepareButton(button);
    }
    WebSkin::PrepareEdit(search_edit_);
    WebSkin::PrepareListView(list_);
    ApplyWebWindowMaterial(window_);

    SetTimer(window_, kRefreshTimer, 650, nullptr);
    Layout();
    RefreshRows(false);
    ShowWindow(window_, SW_HIDE);
    return true;
}

void CloudOSNativeWorkspaceOverviewWindow::Destroy() noexcept
{
    ClearPreview();
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kRefreshTimer);
    }
    if (search_edit_ != nullptr && IsWindow(search_edit_))
    {
        RemoveWindowSubclass(
            search_edit_,
            &CloudOSNativeWorkspaceOverviewWindow::SearchSubclass,
            kControlSubclass);
    }
    if (list_ != nullptr && IsWindow(list_))
    {
        RemoveWindowSubclass(
            list_,
            &CloudOSNativeWorkspaceOverviewWindow::SearchSubclass,
            kControlSubclass);
    }
    if (window_ != nullptr && IsWindow(window_))
    {
        DestroyWindow(window_);
    }

    window_ = nullptr;
    search_edit_ = nullptr;
    list_ = nullptr;
    workspace_combo_ = nullptr;
    focus_button_ = nullptr;
    move_button_ = nullptr;
    floating_button_ = nullptr;
    minimize_button_ = nullptr;
    maximize_button_ = nullptr;
    close_button_ = nullptr;
    tiling_button_ = nullptr;
    status_label_ = nullptr;
    window_manager_ = nullptr;
    visible_rows_.clear();

    for (HFONT* font : {&font_, &small_font_, &title_font_})
    {
        if (*font != nullptr)
        {
            DeleteObject(*font);
            *font = nullptr;
        }
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

bool CloudOSNativeWorkspaceOverviewWindow::Visible() const noexcept
{
    return window_ != nullptr && IsWindow(window_) && IsWindowVisible(window_);
}

void CloudOSNativeWorkspaceOverviewWindow::Show(HWND owner)
{
    if (window_ == nullptr || !IsWindow(window_))
    {
        return;
    }

    RefreshRows(true);
    HMONITOR monitor = owner != nullptr && IsWindow(owner)
        ? MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST)
        : MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info))
    {
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &info.rcWork, 0);
    }

    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::min(
        Scale(kWindowWidthDip, dpi),
        std::max<int>(Scale(760, dpi), Width(info.rcWork) - Scale(48, dpi)));
    const int height = std::min(
        Scale(kWindowHeightDip, dpi),
        std::max<int>(Scale(560, dpi), Height(info.rcWork) - Scale(48, dpi)));
    const int x = info.rcWork.left + (Width(info.rcWork) - width) / 2;
    const int y = info.rcWork.top + (Height(info.rcWork) - height) / 2;

    SetWindowPos(
        window_,
        HWND_TOP,
        x,
        y,
        width,
        height,
        SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    FocusSearch();
}

void CloudOSNativeWorkspaceOverviewWindow::Toggle(HWND owner)
{
    Visible() ? Hide() : Show(owner);
}

void CloudOSNativeWorkspaceOverviewWindow::Hide() noexcept
{
    if (window_ != nullptr && IsWindow(window_))
    {
        ShowWindow(window_, SW_HIDE);
    }
}

void CloudOSNativeWorkspaceOverviewWindow::Refresh()
{
    RefreshRows(true);
}

void CloudOSNativeWorkspaceOverviewWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(24, dpi);
    const int width = Width(client);
    const int height = Height(client);
    const int search_top = Scale(62, dpi);
    const int search_height = Scale(40, dpi);
    const int cards_top = Scale(118, dpi);
    const int cards_height = Scale(76, dpi);
    const int cards_gap = Scale(10, dpi);
    const int card_width = std::max<int>(90, (width - margin * 2 - cards_gap * 3) / 4);

    for (int workspace = 0; workspace < 4; ++workspace)
    {
        const int x = margin + workspace * (card_width + cards_gap);
        workspace_cards_[static_cast<std::size_t>(workspace)] = RECT{
            x,
            cards_top,
            x + card_width,
            cards_top + cards_height};
    }

    MoveWindow(
        search_edit_,
        margin,
        search_top,
        std::max(220, width - margin * 2),
        search_height,
        TRUE);

    const int content_top = cards_top + cards_height + Scale(22, dpi);
    const int action_height = Scale(42, dpi);
    const int action_gap = Scale(8, dpi);
    const int status_height = Scale(28, dpi);
    const int action_top = height - margin - status_height - action_height - Scale(8, dpi);
    const int content_bottom = action_top - Scale(16, dpi);
    const int preview_width = std::max(300, (width - margin * 2) * 38 / 100);
    const int list_width = std::max(340, width - margin * 2 - preview_width - Scale(16, dpi));

    MoveWindow(
        list_,
        margin,
        content_top,
        list_width,
        std::max(100, content_bottom - content_top),
        TRUE);

    preview_rect_ = RECT{
        margin + list_width + Scale(16, dpi),
        content_top,
        width - margin,
        content_bottom};

    const int combo_width = Scale(110, dpi);
    const int button_width = std::max(82, (width - margin * 2 - combo_width - action_gap * 7) / 7);
    int x = margin;
    MoveWindow(focus_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(floating_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(minimize_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(maximize_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(close_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(tiling_button_, x, action_top, button_width, action_height, TRUE);
    x += button_width + action_gap;
    MoveWindow(workspace_combo_, x, action_top, combo_width, Scale(260, dpi), TRUE);
    x += combo_width + action_gap;
    MoveWindow(move_button_, x, action_top, std::max(70, width - margin - x), action_height, TRUE);

    MoveWindow(
        status_label_,
        margin,
        action_top + action_height + Scale(8, dpi),
        width - margin * 2,
        status_height,
        TRUE);

    const int list_client = list_width - GetSystemMetrics(SM_CXVSCROLL) - Scale(12, dpi);
    ListView_SetColumnWidth(list_, 0, std::max(180, list_client - Scale(270, dpi)));
    ListView_SetColumnWidth(list_, 1, Scale(86, dpi));
    ListView_SetColumnWidth(list_, 2, Scale(96, dpi));
    ListView_SetColumnWidth(list_, 3, Scale(76, dpi));

    LayoutPreview();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeWorkspaceOverviewWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(1, Width(client));
    const int height = std::max(1, Height(client));

    HDC memory_dc = CreateCompatibleDC(screen_dc);
    HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    LinearGradientBrush background(
        PointF(0.0f, 0.0f),
        PointF(static_cast<REAL>(width), static_cast<REAL>(height)),
        WebSkin::GdiColor(WebSkin::BgSecondary),
        WebSkin::GdiColor(WebSkin::BgSolid));
    graphics.FillRectangle(
        &background,
        RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(24, dpi);
    RECT title_rect{margin, Scale(15, dpi), width - margin, Scale(48, dpi)};
    DrawTextLine(
        memory_dc,
        title_font_,
        WebSkin::TextPrimary,
        L"Visão de Trabalho",
        title_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    RECT subtitle_rect{margin + Scale(210, dpi), Scale(19, dpi), width - margin, Scale(48, dpi)};
    DrawTextLine(
        memory_dc,
        small_font_,
        WebSkin::TextTertiary,
        L"4 áreas  ·  busca global  ·  preview DWM  ·  Ctrl+Alt+O",
        subtitle_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    const int current_workspace = window_manager_ != nullptr
        ? window_manager_->CurrentWorkspace()
        : 0;
    Font card_title(
        L"Segoe UI Variable Display",
        static_cast<REAL>(Scale(13, dpi)),
        FontStyleBold,
        UnitPixel);
    Font card_meta(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(10, dpi)),
        FontStyleRegular,
        UnitPixel);
    SolidBrush primary(WebSkin::GdiColor(WebSkin::TextPrimary));
    SolidBrush secondary(WebSkin::GdiColor(WebSkin::TextSecondary));

    for (int workspace = 0; workspace < 4; ++workspace)
    {
        const RECT& rect = workspace_cards_[static_cast<std::size_t>(workspace)];
        const bool active = current_workspace == workspace;
        const bool hot = hovered_workspace_ == workspace;
        WebSkin::DrawRoundedPanel(
            graphics,
            RectF(
                static_cast<REAL>(rect.left),
                static_cast<REAL>(rect.top),
                static_cast<REAL>(Width(rect)),
                static_cast<REAL>(Height(rect))),
            static_cast<REAL>(Scale(WebSkin::RadiusLarge, dpi)),
            WebSkin::GdiColor(
                active ? WebSkin::AccentSubtle : hot ? WebSkin::BgHover : WebSkin::BgTertiary,
                238),
            WebSkin::GdiColor(
                active ? WebSkin::Accent : hot ? WebSkin::BorderStrong : WebSkin::BorderDefault),
            active ? 1.6f : 1.0f);

        const std::wstring label = WorkspaceLabel(workspace);
        graphics.DrawString(
            label.c_str(),
            -1,
            &card_title,
            PointF(
                static_cast<REAL>(rect.left + Scale(14, dpi)),
                static_cast<REAL>(rect.top + Scale(13, dpi))),
            &primary);

        std::wstring meta = std::to_wstring(workspace_counts_[static_cast<std::size_t>(workspace)]);
        meta += workspace_counts_[static_cast<std::size_t>(workspace)] == 1u
            ? L" janela"
            : L" janelas";
        if (active)
        {
            meta += L"  ·  ativa";
        }
        graphics.DrawString(
            meta.c_str(),
            -1,
            &card_meta,
            PointF(
                static_cast<REAL>(rect.left + Scale(14, dpi)),
                static_cast<REAL>(rect.top + Scale(43, dpi))),
            active ? &primary : &secondary);
    }

    if (preview_rect_.right > preview_rect_.left && preview_rect_.bottom > preview_rect_.top)
    {
        WebSkin::DrawRoundedPanel(
            graphics,
            RectF(
                static_cast<REAL>(preview_rect_.left),
                static_cast<REAL>(preview_rect_.top),
                static_cast<REAL>(Width(preview_rect_)),
                static_cast<REAL>(Height(preview_rect_))),
            static_cast<REAL>(Scale(WebSkin::RadiusXL, dpi)),
            WebSkin::GdiColor(WebSkin::BgSecondary, 232),
            WebSkin::GdiColor(WebSkin::BorderDefault),
            1.0f);

        const WindowRow* row = SelectedRow();
        std::wstring preview_title = row != nullptr ? row->title : L"Selecione uma janela";
        if (preview_title.empty())
        {
            preview_title = L"Janela";
        }
        RECT preview_title_rect{
            preview_rect_.left + Scale(16, dpi),
            preview_rect_.top + Scale(10, dpi),
            preview_rect_.right - Scale(16, dpi),
            preview_rect_.top + Scale(42, dpi)};
        DrawTextLine(
            memory_dc,
            font_,
            WebSkin::TextPrimary,
            preview_title,
            preview_title_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

        std::wstring preview_meta;
        if (row != nullptr)
        {
            preview_meta = WorkspaceLabel(row->workspace);
            preview_meta += row->floating ? L"  ·  flutuante" : L"  ·  gerenciada";
            preview_meta += L"  ·  PID ";
            preview_meta += std::to_wstring(row->process_id);
        }
        else
        {
            preview_meta = L"Enter foca  ·  Shift+1..4 move  ·  Espaço alterna flutuante";
        }
        RECT preview_meta_rect{
            preview_rect_.left + Scale(16, dpi),
            preview_rect_.bottom - Scale(36, dpi),
            preview_rect_.right - Scale(16, dpi),
            preview_rect_.bottom - Scale(10, dpi)};
        DrawTextLine(
            memory_dc,
            small_font_,
            WebSkin::TextTertiary,
            preview_meta,
            preview_meta_rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }

    BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    EndPaint(window_, &paint);
}

void CloudOSNativeWorkspaceOverviewWindow::RefreshWorkspaceCards()
{
    workspace_counts_.fill(0u);
    if (window_manager_ == nullptr)
    {
        return;
    }
    const auto all = window_manager_->AllManagedWindows();
    for (const CloudOSManagedWindow& item : all)
    {
        if (item.workspace >= 0 && item.workspace < 4 && item.hwnd != nullptr && IsWindow(item.hwnd))
        {
            ++workspace_counts_[static_cast<std::size_t>(item.workspace)];
        }
    }
}

void CloudOSNativeWorkspaceOverviewWindow::RefreshRows(bool preserve_selection)
{
    if (list_ == nullptr || window_manager_ == nullptr)
    {
        return;
    }

    const HWND previous = preserve_selection ? SelectedWindow() : nullptr;
    const std::wstring query = Lower(ReadText(search_edit_));
    window_manager_->Reconcile();
    RefreshWorkspaceCards();

    std::vector<CloudOSManagedWindow> managed = window_manager_->AllManagedWindows();
    std::sort(
        managed.begin(),
        managed.end(),
        [](const CloudOSManagedWindow& first, const CloudOSManagedWindow& second)
        {
            if (first.workspace != second.workspace)
            {
                return first.workspace < second.workspace;
            }
            return _wcsicmp(first.title.c_str(), second.title.c_str()) < 0;
        });

    visible_rows_.clear();
    ListView_DeleteAllItems(list_);
    for (const CloudOSManagedWindow& item : managed)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }

        const std::wstring workspace = WorkspaceLabel(item.workspace);
        const std::wstring pid = std::to_wstring(item.process_id);
        if (!query.empty())
        {
            std::wstring haystack = Lower(item.title);
            haystack += L" ";
            haystack += Lower(workspace);
            haystack += L" ";
            haystack += pid;
            haystack += item.floating ? L" flutuante floating" : L" gerenciada tiled";
            if (haystack.find(query) == std::wstring::npos)
            {
                continue;
            }
        }

        WindowRow row{};
        row.hwnd = item.hwnd;
        row.process_id = item.process_id;
        row.workspace = item.workspace;
        row.floating = item.floating;
        row.hidden_by_workspace = item.hidden_by_workspace;
        row.title = item.title.empty() ? L"Janela" : item.title;
        visible_rows_.push_back(std::move(row));
    }

    for (std::size_t index = 0; index < visible_rows_.size(); ++index)
    {
        const WindowRow& row = visible_rows_[index];
        std::wstring title = row.title;
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = title.data();
        ListView_InsertItem(list_, &item);

        std::wstring workspace = WorkspaceLabel(row.workspace);
        std::wstring mode = row.floating ? L"Flutuante" : L"Gerenciada";
        std::wstring pid = std::to_wstring(row.process_id);
        ListView_SetItemText(list_, static_cast<int>(index), 1, workspace.data());
        ListView_SetItemText(list_, static_cast<int>(index), 2, mode.data());
        ListView_SetItemText(list_, static_cast<int>(index), 3, pid.data());
    }

    int selected = -1;
    if (previous != nullptr)
    {
        for (std::size_t index = 0; index < visible_rows_.size(); ++index)
        {
            if (visible_rows_[index].hwnd == previous)
            {
                selected = static_cast<int>(index);
                break;
            }
        }
    }
    if (selected < 0 && !visible_rows_.empty())
    {
        selected = 0;
    }
    if (selected >= 0)
    {
        ListView_SetItemState(
            list_,
            selected,
            LVIS_SELECTED | LVIS_FOCUSED,
            LVIS_SELECTED | LVIS_FOCUSED);
        ListView_EnsureVisible(list_, selected, FALSE);
    }

    const int current = window_manager_->CurrentWorkspace();
    int target = static_cast<int>(SendMessageW(workspace_combo_, CB_GETCURSEL, 0, 0));
    if (target < 0 || target >= 4 || target == current)
    {
        target = WrappedWorkspace(current, 1);
        SendMessageW(workspace_combo_, CB_SETCURSEL, static_cast<WPARAM>(target), 0);
    }

    RefreshStatus();
    RebuildPreview();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeWorkspaceOverviewWindow::RefreshStatus()
{
    if (status_label_ == nullptr || window_manager_ == nullptr)
    {
        return;
    }

    const int current = window_manager_->CurrentWorkspace();
    std::wstring status = L"CloudOS  ·  ";
    status += WorkspaceLabel(current);
    status += L"  ·  ";
    status += std::to_wstring(window_manager_->ManagedWindowCount());
    status += L" janelas gerenciadas  ·  ";
    status += window_manager_->TilingEnabled() ? L"tiling ativo" : L"tiling desativado";
    status += L"  ·  Ctrl+PgUp/PgDn troca área";
    SetWindowTextW(status_label_, status.c_str());
    SetWindowTextW(
        tiling_button_,
        window_manager_->TilingEnabled() ? L"Tiling ON" : L"Tiling OFF");
}

int CloudOSNativeWorkspaceOverviewWindow::SelectedRowIndex() const noexcept
{
    if (list_ == nullptr)
    {
        return -1;
    }
    return ListView_GetNextItem(list_, -1, LVNI_SELECTED);
}

const CloudOSNativeWorkspaceOverviewWindow::WindowRow*
CloudOSNativeWorkspaceOverviewWindow::SelectedRow() const noexcept
{
    const int index = SelectedRowIndex();
    if (index < 0 || index >= static_cast<int>(visible_rows_.size()))
    {
        return nullptr;
    }
    return &visible_rows_[static_cast<std::size_t>(index)];
}

HWND CloudOSNativeWorkspaceOverviewWindow::SelectedWindow() const noexcept
{
    const WindowRow* row = SelectedRow();
    return row != nullptr ? row->hwnd : nullptr;
}

void CloudOSNativeWorkspaceOverviewWindow::SelectWindow(HWND window)
{
    if (window == nullptr || list_ == nullptr)
    {
        return;
    }
    for (std::size_t index = 0; index < visible_rows_.size(); ++index)
    {
        if (visible_rows_[index].hwnd == window)
        {
            ListView_SetItemState(list_, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
            ListView_SetItemState(
                list_,
                static_cast<int>(index),
                LVIS_SELECTED | LVIS_FOCUSED,
                LVIS_SELECTED | LVIS_FOCUSED);
            ListView_EnsureVisible(list_, static_cast<int>(index), FALSE);
            RebuildPreview();
            return;
        }
    }
}

void CloudOSNativeWorkspaceOverviewWindow::ClearPreview() noexcept
{
    if (thumbnail_ != nullptr)
    {
        DwmUnregisterThumbnail(thumbnail_);
        thumbnail_ = nullptr;
    }
    preview_source_ = nullptr;
}

void CloudOSNativeWorkspaceOverviewWindow::RebuildPreview()
{
    const HWND selected = SelectedWindow();
    if (selected == preview_source_ && thumbnail_ != nullptr)
    {
        LayoutPreview();
        return;
    }

    ClearPreview();
    if (window_ == nullptr || selected == nullptr || !IsWindow(selected))
    {
        InvalidateRect(window_, nullptr, FALSE);
        return;
    }

    HTHUMBNAIL thumbnail = nullptr;
    if (SUCCEEDED(DwmRegisterThumbnail(window_, selected, &thumbnail)))
    {
        thumbnail_ = thumbnail;
        preview_source_ = selected;
        LayoutPreview();
    }
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeWorkspaceOverviewWindow::LayoutPreview()
{
    if (thumbnail_ == nullptr || preview_rect_.right <= preview_rect_.left)
    {
        return;
    }

    SIZE source{};
    if (FAILED(DwmQueryThumbnailSourceSize(thumbnail_, &source)) || source.cx <= 0 || source.cy <= 0)
    {
        return;
    }

    const UINT dpi = GetDpiForWindow(window_);
    RECT available{
        preview_rect_.left + Scale(16, dpi),
        preview_rect_.top + Scale(52, dpi),
        preview_rect_.right - Scale(16, dpi),
        preview_rect_.bottom - Scale(48, dpi)};
    if (available.right <= available.left || available.bottom <= available.top)
    {
        return;
    }

    int width = Width(available);
    int height = MulDiv(width, source.cy, source.cx);
    if (height > Height(available))
    {
        height = Height(available);
        width = MulDiv(height, source.cx, source.cy);
    }
    RECT destination{
        available.left + (Width(available) - width) / 2,
        available.top + (Height(available) - height) / 2,
        0,
        0};
    destination.right = destination.left + width;
    destination.bottom = destination.top + height;

    DWM_THUMBNAIL_PROPERTIES properties{};
    properties.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY;
    properties.rcDestination = destination;
    properties.fVisible = TRUE;
    properties.opacity = 255;
    DwmUpdateThumbnailProperties(thumbnail_, &properties);
}

int CloudOSNativeWorkspaceOverviewWindow::HitWorkspaceCard(POINT point) const noexcept
{
    for (int workspace = 0; workspace < 4; ++workspace)
    {
        if (Contains(workspace_cards_[static_cast<std::size_t>(workspace)], point))
        {
            return workspace;
        }
    }
    return -1;
}

void CloudOSNativeWorkspaceOverviewWindow::SwitchWorkspace(int workspace, bool hide_after)
{
    if (window_manager_ == nullptr || workspace < 0 || workspace >= 4)
    {
        return;
    }
    window_manager_->SwitchWorkspace(workspace);
    RefreshRows(true);
    if (hide_after)
    {
        Hide();
    }
}

void CloudOSNativeWorkspaceOverviewWindow::CycleWorkspace(int direction)
{
    if (window_manager_ == nullptr || direction == 0)
    {
        return;
    }
    SwitchWorkspace(WrappedWorkspace(window_manager_->CurrentWorkspace(), direction), false);
}

void CloudOSNativeWorkspaceOverviewWindow::MoveActiveToWorkspace(int workspace, bool follow)
{
    if (window_manager_ == nullptr || workspace < 0 || workspace >= 4)
    {
        return;
    }
    if (window_manager_->ActiveManagedWindow() == nullptr)
    {
        return;
    }
    window_manager_->MoveActiveToWorkspace(workspace);
    if (follow)
    {
        window_manager_->SwitchWorkspace(workspace);
    }
    RefreshRows(true);
}

void CloudOSNativeWorkspaceOverviewWindow::MoveSelectedToWorkspace(int workspace, bool follow)
{
    if (window_manager_ == nullptr || workspace < 0 || workspace >= 4)
    {
        return;
    }
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr || selected->hwnd == nullptr || !IsWindow(selected->hwnd))
    {
        return;
    }

    const HWND target = selected->hwnd;
    const int source_workspace = selected->workspace;
    if (source_workspace != window_manager_->CurrentWorkspace())
    {
        window_manager_->SwitchWorkspace(source_workspace);
    }
    window_manager_->FocusWindow(target);
    window_manager_->MoveActiveToWorkspace(workspace);
    if (follow)
    {
        window_manager_->SwitchWorkspace(workspace);
        window_manager_->FocusWindow(target);
    }
    RefreshRows(false);
    SelectWindow(target);
}

void CloudOSNativeWorkspaceOverviewWindow::FocusSelected(bool hide_after)
{
    if (window_manager_ == nullptr)
    {
        return;
    }
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr || selected->hwnd == nullptr || !IsWindow(selected->hwnd))
    {
        return;
    }
    const HWND target = selected->hwnd;
    if (selected->workspace != window_manager_->CurrentWorkspace())
    {
        window_manager_->SwitchWorkspace(selected->workspace);
    }
    window_manager_->FocusWindow(target);
    RefreshRows(true);
    if (hide_after)
    {
        Hide();
    }
}

void CloudOSNativeWorkspaceOverviewWindow::ToggleFloatingSelected()
{
    if (window_manager_ == nullptr)
    {
        return;
    }
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr || selected->hwnd == nullptr || !IsWindow(selected->hwnd))
    {
        return;
    }
    const HWND target = selected->hwnd;
    window_manager_->SetWindowFloating(target, !selected->floating);
    if (window_manager_->TilingEnabled() && selected->workspace == window_manager_->CurrentWorkspace())
    {
        window_manager_->TileCurrentWorkspace();
    }
    RefreshRows(true);
    SelectWindow(target);
}

void CloudOSNativeWorkspaceOverviewWindow::MinimizeSelected()
{
    if (window_manager_ == nullptr)
    {
        return;
    }
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr)
    {
        return;
    }
    const HWND target = selected->hwnd;
    if (selected->workspace != window_manager_->CurrentWorkspace())
    {
        window_manager_->SwitchWorkspace(selected->workspace);
    }
    window_manager_->FocusWindow(target);
    window_manager_->MinimizeActive();
    RefreshRows(true);
}

void CloudOSNativeWorkspaceOverviewWindow::MaximizeSelected()
{
    if (window_manager_ == nullptr)
    {
        return;
    }
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr)
    {
        return;
    }
    const HWND target = selected->hwnd;
    if (selected->workspace != window_manager_->CurrentWorkspace())
    {
        window_manager_->SwitchWorkspace(selected->workspace);
    }
    window_manager_->FocusWindow(target);
    window_manager_->ToggleMaximizeActive();
    RefreshRows(true);
}

void CloudOSNativeWorkspaceOverviewWindow::CloseSelected()
{
    const HWND selected = SelectedWindow();
    if (selected != nullptr && IsWindow(selected))
    {
        PostMessageW(selected, WM_CLOSE, 0, 0);
    }
}

void CloudOSNativeWorkspaceOverviewWindow::ToggleTiling()
{
    if (window_manager_ == nullptr)
    {
        return;
    }
    window_manager_->ToggleTiling();
    RefreshRows(true);
}

void CloudOSNativeWorkspaceOverviewWindow::FocusSearch()
{
    if (search_edit_ != nullptr)
    {
        SetFocus(search_edit_);
        SendMessageW(search_edit_, EM_SETSEL, 0, -1);
    }
}

void CloudOSNativeWorkspaceOverviewWindow::FocusList()
{
    if (list_ != nullptr)
    {
        SetFocus(list_);
        if (SelectedRowIndex() < 0 && !visible_rows_.empty())
        {
            ListView_SetItemState(
                list_,
                0,
                LVIS_SELECTED | LVIS_FOCUSED,
                LVIS_SELECTED | LVIS_FOCUSED);
        }
    }
}

void CloudOSNativeWorkspaceOverviewWindow::ShowSelectedContextMenu(POINT screen_point)
{
    const WindowRow* selected = SelectedRow();
    if (selected == nullptr)
    {
        return;
    }

    HMENU menu = CreatePopupMenu();
    HMENU move = CreatePopupMenu();
    if (menu == nullptr || move == nullptr)
    {
        if (menu != nullptr) DestroyMenu(menu);
        if (move != nullptr) DestroyMenu(move);
        return;
    }

    AppendMenuW(menu, MF_STRING, kContextFocus, L"Focar janela");
    AppendMenuW(menu, MF_STRING, kContextFloating, selected->floating ? L"Voltar ao tiling" : L"Tornar flutuante");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kContextMinimize, L"Minimizar");
    AppendMenuW(menu, MF_STRING, kContextMaximize, L"Maximizar / restaurar");

    AppendMenuW(move, MF_STRING, kContextMove1, L"Área 1");
    AppendMenuW(move, MF_STRING, kContextMove2, L"Área 2");
    AppendMenuW(move, MF_STRING, kContextMove3, L"Área 3");
    AppendMenuW(move, MF_STRING, kContextMove4, L"Área 4");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(move), L"Mover para área");

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kContextTile, L"Alternar tiling da área atual");
    AppendMenuW(menu, MF_STRING, kContextClose, L"Fechar janela");

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case kContextFocus:
        FocusSelected(true);
        break;
    case kContextFloating:
        ToggleFloatingSelected();
        break;
    case kContextMinimize:
        MinimizeSelected();
        break;
    case kContextMaximize:
        MaximizeSelected();
        break;
    case kContextMove1:
    case kContextMove2:
    case kContextMove3:
    case kContextMove4:
        MoveSelectedToWorkspace(command - static_cast<int>(kContextMove1), false);
        break;
    case kContextTile:
        ToggleTiling();
        break;
    case kContextClose:
        CloseSelected();
        break;
    default:
        break;
    }
}

LRESULT CloudOSNativeWorkspaceOverviewWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_PAINT:
        Paint();
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_SIZE:
        Layout();
        return 0;
    case WM_DPICHANGED:
    {
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        if (suggested != nullptr)
        {
            SetWindowPos(
                window_,
                nullptr,
                suggested->left,
                suggested->top,
                Width(*suggested),
                Height(*suggested),
                SWP_NOZORDER | SWP_NOACTIVATE);
        }
        Layout();
        return 0;
    }
    case WM_TIMER:
        if (w_param == kRefreshTimer && Visible())
        {
            RefreshRows(true);
            return 0;
        }
        break;
    case WM_MOUSEMOVE:
    {
        if (!tracking_mouse_)
        {
            TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window_, 0};
            TrackMouseEvent(&tracking);
            tracking_mouse_ = true;
        }
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const int next = HitWorkspaceCard(point);
        if (next != hovered_workspace_)
        {
            hovered_workspace_ = next;
            InvalidateRect(window_, nullptr, FALSE);
        }
        if (next >= 0)
        {
            SetCursor(LoadCursorW(nullptr, IDC_HAND));
        }
        return 0;
    }
    case WM_MOUSELEAVE:
        tracking_mouse_ = false;
        hovered_workspace_ = -1;
        InvalidateRect(window_, nullptr, FALSE);
        return 0;
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const int workspace = HitWorkspaceCard(point);
        if (workspace >= 0)
        {
            const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            if (shift)
            {
                MoveActiveToWorkspace(workspace, true);
            }
            else
            {
                SwitchWorkspace(workspace, false);
            }
            return 0;
        }
        break;
    }
    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchId && HIWORD(w_param) == EN_CHANGE)
        {
            RefreshRows(false);
            return 0;
        }
        switch (LOWORD(w_param))
        {
        case kFocusId:
            FocusSelected(true);
            return 0;
        case kMoveId:
        {
            const int target = static_cast<int>(SendMessageW(workspace_combo_, CB_GETCURSEL, 0, 0));
            MoveSelectedToWorkspace(target, false);
            return 0;
        }
        case kFloatingId:
            ToggleFloatingSelected();
            return 0;
        case kMinimizeId:
            MinimizeSelected();
            return 0;
        case kMaximizeId:
            MaximizeSelected();
            return 0;
        case kCloseId:
            CloseSelected();
            return 0;
        case kTilingId:
            ToggleTiling();
            return 0;
        default:
            break;
        }
        break;
    case WM_DRAWITEM:
        if (l_param != 0)
        {
            const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
            ButtonTone tone = ButtonTone::Neutral;
            if (draw->CtlID == static_cast<UINT>(kFocusId))
            {
                tone = ButtonTone::Accent;
            }
            else if (draw->CtlID == static_cast<UINT>(kCloseId))
            {
                tone = ButtonTone::Danger;
            }
            return WebSkin::PaintOwnerDrawButton(draw, tone) ? TRUE : FALSE;
        }
        break;
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK || header->code == NM_RETURN)
            {
                FocusSelected(true);
                return 0;
            }
            if (header->code == LVN_ITEMCHANGED)
            {
                RebuildPreview();
                InvalidateRect(window_, nullptr, FALSE);
                return 0;
            }
            if (header->code == NM_RCLICK)
            {
                POINT point{};
                GetCursorPos(&point);
                ShowSelectedContextMenu(point);
                return 0;
            }
            if (header->code == NM_CUSTOMDRAW)
            {
                return WebSkin::HandleListViewCustomDraw(
                    reinterpret_cast<LPNMLVCUSTOMDRAW>(l_param));
            }
        }
        break;
    }
    case WM_KEYDOWN:
    {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        if (w_param == VK_ESCAPE)
        {
            Hide();
            return 0;
        }
        if (w_param == VK_F5)
        {
            RefreshRows(true);
            return 0;
        }
        if (control && w_param == L'F')
        {
            FocusSearch();
            return 0;
        }
        if (control && (w_param == VK_PRIOR || w_param == VK_NEXT))
        {
            CycleWorkspace(w_param == VK_PRIOR ? -1 : 1);
            return 0;
        }
        if (w_param >= L'1' && w_param <= L'4')
        {
            const int workspace = static_cast<int>(w_param - L'1');
            if (shift)
            {
                MoveSelectedToWorkspace(workspace, control);
            }
            else
            {
                SwitchWorkspace(workspace, false);
            }
            return 0;
        }
        if (w_param == VK_RETURN)
        {
            FocusSelected(true);
            return 0;
        }
        if (w_param == VK_DELETE)
        {
            CloseSelected();
            return 0;
        }
        if (w_param == VK_SPACE)
        {
            ToggleFloatingSelected();
            return 0;
        }
        if (w_param == L'T')
        {
            ToggleTiling();
            return 0;
        }
        break;
    }
    case WM_CTLCOLOREDIT:
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextPrimary);
        SetBkColor(reinterpret_cast<HDC>(w_param), WebSkin::BgTertiary);
        return reinterpret_cast<LRESULT>(edit_background_);
    case WM_CTLCOLORSTATIC:
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextSecondary);
        SetBkColor(reinterpret_cast<HDC>(w_param), WebSkin::BgPrimary);
        return reinterpret_cast<LRESULT>(background_);
    case WM_CLOSE:
        Hide();
        return 0;
    case WM_NCDESTROY:
        ClearPreview();
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        window_ = nullptr;
        return DefWindowProcW(window, message, w_param, l_param);
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeWorkspaceOverviewWindow::SearchSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data)
{
    auto* self = reinterpret_cast<CloudOSNativeWorkspaceOverviewWindow*>(reference_data);
    if (self == nullptr)
    {
        return DefSubclassProc(window, message, w_param, l_param);
    }

    if (message == WM_KEYDOWN)
    {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        if (control && w_param == L'F')
        {
            self->FocusSearch();
            return 0;
        }
        if (w_param == VK_ESCAPE)
        {
            if (window == self->search_edit_ && !ReadText(window).empty())
            {
                SetWindowTextW(window, L"");
                return 0;
            }
            self->Hide();
            return 0;
        }
        if (w_param == VK_F5)
        {
            self->RefreshRows(true);
            return 0;
        }
        if (control && (w_param == VK_PRIOR || w_param == VK_NEXT))
        {
            self->CycleWorkspace(w_param == VK_PRIOR ? -1 : 1);
            return 0;
        }
        if (w_param >= L'1' && w_param <= L'4' && (window == self->list_ || control || shift))
        {
            const int workspace = static_cast<int>(w_param - L'1');
            if (shift)
            {
                self->MoveSelectedToWorkspace(workspace, control);
            }
            else
            {
                self->SwitchWorkspace(workspace, false);
            }
            return 0;
        }

        if (window == self->search_edit_)
        {
            if (w_param == VK_DOWN)
            {
                self->FocusList();
                return 0;
            }
            if (w_param == VK_RETURN)
            {
                self->FocusSelected(true);
                return 0;
            }
        }
        else if (window == self->list_)
        {
            if (w_param == VK_RETURN)
            {
                self->FocusSelected(true);
                return 0;
            }
            if (w_param == VK_DELETE)
            {
                self->CloseSelected();
                return 0;
            }
            if (w_param == VK_SPACE)
            {
                self->ToggleFloatingSelected();
                return 0;
            }
            if (w_param == L'T')
            {
                self->ToggleTiling();
                return 0;
            }
            if (w_param == VK_APPS || (w_param == VK_F10 && shift))
            {
                const int selected = self->SelectedRowIndex();
                POINT point{};
                if (selected >= 0)
                {
                    RECT rect{};
                    if (ListView_GetItemRect(self->list_, selected, &rect, LVIR_BOUNDS))
                    {
                        point.x = rect.left + Scale(24, GetDpiForWindow(self->list_));
                        point.y = rect.bottom;
                        ClientToScreen(self->list_, &point);
                    }
                    else
                    {
                        GetCursorPos(&point);
                    }
                }
                else
                {
                    GetCursorPos(&point);
                }
                self->ShowSelectedContextMenu(point);
                return 0;
            }
        }
    }

    if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, SearchSubclass, subclass_id);
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeWorkspaceOverviewWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeWorkspaceOverviewWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeWorkspaceOverviewWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeWorkspaceOverviewWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
