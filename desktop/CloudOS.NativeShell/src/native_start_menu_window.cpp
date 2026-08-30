#include "native_start_menu_window.h"

#include "native_app_launcher.h"
#include "native_icon_renderer.h"
#include "native_search_engine.h"
#include "native_start_menu_mru.h"
#include "native_theme.h"

#include <commctrl.h>
#include <gdiplus.h>
#include <uxtheme.h>

#include <algorithm>
#include <array>
#include <string>

#pragma comment(lib, "uxtheme.lib")

using namespace Gdiplus;

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

void DrawTextLine(
    HDC dc,
    HFONT font,
    COLORREF color,
    const std::wstring& text,
    RECT rect,
    UINT format)
{
    if (dc == nullptr || text.empty())
    {
        return;
    }
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;
    const int old_mode = SetBkMode(dc, TRANSPARENT);
    const COLORREF old_color = SetTextColor(dc, color);
    DrawTextW(dc, text.c_str(), -1, &rect, format);
    SetTextColor(dc, old_color);
    SetBkMode(dc, old_mode);
    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }
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
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kStartClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kStartClass,
        L"Iniciar - CloudOS",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        0,
        0,
        620,
        680,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    const UINT dpi = GetDpiForWindow(window_);
    background_ = CreateSolidBrush(WebSkin::BgPrimary);
    edit_background_ = CreateSolidBrush(WebSkin::BgSecondary);
    font_ = CreateFontW(
        -Scale(14, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    small_font_ = CreateFontW(
        -Scale(11, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(15, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    search_edit_ = CreateWindowExW(
        0,
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
        L"↻",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRefreshId)),
        instance_,
        nullptr);
    app_list_ = CreateWindowExW(
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS |
            LVS_NOSORTHEADER | LVS_NOCOLUMNHEADER,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    command_button_ = CreateWindowW(
        L"BUTTON",
        L"Central de Comandos",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCommandId)),
        instance_,
        nullptr);
    power_button_ = CreateWindowW(
        L"BUTTON",
        L"⏻",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPowerId)),
        instance_,
        nullptr);
    footer_label_ = CreateWindowW(
        L"STATIC",
        L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
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
    SetControlFont(footer_label_, small_font_);

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar aplicativos, arquivos e comandos"));

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
    ListView_SetBkColor(app_list_, WebSkin::BgPrimary);
    ListView_SetTextBkColor(app_list_, WebSkin::BgPrimary);
    ListView_SetTextColor(app_list_, WebSkin::TextPrimary);

    LVCOLUMNW app_column{};
    app_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    app_column.pszText = const_cast<LPWSTR>(L"Aplicativo");
    app_column.cx = 540;
    ListView_InsertColumn(app_list_, 0, &app_column);

    (void)SetWindowTheme(app_list_, L"DarkMode_Explorer", nullptr);
    (void)SetWindowTheme(search_edit_, L"DarkMode_CFD", nullptr);

    ApplyWebFlyoutMaterial(window_);
    RebuildRowHeight();
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
    if (app_list_ != nullptr && IsWindow(app_list_))
    {
        ListView_SetImageList(app_list_, nullptr, LVSIL_SMALL);
    }
    if (row_height_image_list_ != nullptr)
    {
        ImageList_Destroy(row_height_image_list_);
        row_height_image_list_ = nullptr;
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
    if (small_font_ != nullptr)
    {
        DeleteObject(small_font_);
        small_font_ = nullptr;
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

void CloudOSNativeStartMenuWindow::RebuildRowHeight()
{
    if (app_list_ == nullptr)
    {
        return;
    }

    if (row_height_image_list_ != nullptr)
    {
        ListView_SetImageList(app_list_, nullptr, LVSIL_SMALL);
        ImageList_Destroy(row_height_image_list_);
        row_height_image_list_ = nullptr;
    }

    const UINT dpi = GetDpiForWindow(window_);
    const int row_height = Scale(58, dpi);
    row_height_image_list_ = ImageList_Create(1, row_height, ILC_COLOR32, 1, 1);
    if (row_height_image_list_ == nullptr)
    {
        return;
    }

    HDC dc = GetDC(window_);
    HBITMAP blank = dc != nullptr ? CreateCompatibleBitmap(dc, 1, row_height) : nullptr;
    if (dc != nullptr)
    {
        ReleaseDC(window_, dc);
    }
    if (blank != nullptr)
    {
        (void)ImageList_Add(row_height_image_list_, blank, nullptr);
        DeleteObject(blank);
    }
    ListView_SetImageList(app_list_, row_height_image_list_, LVSIL_SMALL);
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
    const int margin = Scale(24, dpi);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));
    const int search_height = Scale(42, dpi);
    const int refresh_size = Scale(42, dpi);
    const int footer_height = Scale(62, dpi);
    const int footer_y = height - footer_height;

    const int search_frame_right = width - margin - refresh_size - Scale(10, dpi);
    MoveWindow(
        search_edit_,
        margin + Scale(14, dpi),
        margin + Scale(8, dpi),
        std::max(80, search_frame_right - margin - Scale(28, dpi)),
        search_height - Scale(16, dpi),
        TRUE);
    MoveWindow(
        refresh_button_,
        width - margin - refresh_size,
        margin,
        refresh_size,
        search_height,
        TRUE);

    const int list_y = margin + search_height + Scale(42, dpi);
    MoveWindow(
        app_list_,
        margin,
        list_y,
        width - margin * 2,
        std::max(80, footer_y - list_y - Scale(10, dpi)),
        TRUE);

    MoveWindow(
        footer_label_,
        margin,
        footer_y + Scale(18, dpi),
        std::max(100, width - Scale(285, dpi)),
        Scale(30, dpi),
        TRUE);
    MoveWindow(
        command_button_,
        width - margin - Scale(218, dpi),
        footer_y + Scale(12, dpi),
        Scale(164, dpi),
        Scale(38, dpi),
        TRUE);
    MoveWindow(
        power_button_,
        width - margin - Scale(44, dpi),
        footer_y + Scale(12, dpi),
        Scale(44, dpi),
        Scale(38, dpi),
        TRUE);

    ListView_SetColumnWidth(app_list_, 0, std::max(180, width - margin * 2 - Scale(8, dpi)));
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeStartMenuWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));

    HDC memory_dc = CreateCompatibleDC(screen_dc);
    HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    LinearGradientBrush background(
        PointF(0.0f, 0.0f),
        PointF(0.0f, static_cast<REAL>(height)),
        WebSkin::GdiColor(WebSkin::BgSecondary),
        WebSkin::GdiColor(WebSkin::BgSolid));
    graphics.FillRectangle(&background, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(24, dpi);
    const int search_height = Scale(42, dpi);
    const int refresh_size = Scale(42, dpi);
    const int search_width = width - margin * 2 - refresh_size - Scale(10, dpi);

    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(margin),
            static_cast<REAL>(margin),
            static_cast<REAL>(std::max(1, search_width)),
            static_cast<REAL>(search_height)),
        static_cast<REAL>(Scale(WebSkin::RadiusMedium, dpi)),
        WebSkin::GdiColor(search_focused_ ? WebSkin::BgTertiary : WebSkin::BgSecondary),
        WebSkin::GdiColor(search_focused_ ? WebSkin::Accent : WebSkin::BorderDefault),
        search_focused_ ? 1.5f : 1.0f);

    if (search_focused_)
    {
        WebSkin::DrawRoundedPanel(
            graphics,
            RectF(
                static_cast<REAL>(margin - Scale(2, dpi)),
                static_cast<REAL>(margin - Scale(2, dpi)),
                static_cast<REAL>(std::max(1, search_width + Scale(4, dpi))),
                static_cast<REAL>(search_height + Scale(4, dpi))),
            static_cast<REAL>(Scale(WebSkin::RadiusMedium + 2, dpi)),
            Color(0, 0, 0, 0),
            Color(70, 99, 102, 241),
            1.0f);
    }

    RECT section_title{
        margin,
        margin + search_height + Scale(17, dpi),
        width - margin,
        margin + search_height + Scale(39, dpi)};
    DrawTextLine(
        memory_dc,
        title_font_,
        WebSkin::TextPrimary,
        SearchText(search_edit_).empty() ? L"Aplicativos" : L"Resultados",
        section_title,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    std::wstring section_meta;
    if (NativeStartIndex::Instance().Indexing())
    {
        section_meta = L"indexando...";
    }
    else
    {
        section_meta = std::to_wstring(results_.size());
        section_meta += L" encontrados";
    }
    RECT section_meta_rect = section_title;
    DrawTextLine(
        memory_dc,
        small_font_,
        WebSkin::TextTertiary,
        section_meta,
        section_meta_rect,
        DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    const int footer_y = height - Scale(62, dpi);
    Pen footer_border(WebSkin::GdiColor(WebSkin::BorderDefault), 1.0f);
    graphics.DrawLine(
        &footer_border,
        static_cast<REAL>(margin),
        static_cast<REAL>(footer_y),
        static_cast<REAL>(width - margin),
        static_cast<REAL>(footer_y));

    // Tiny brand accent copied from the web shell's indigo focus language.
    SolidBrush accent(WebSkin::GdiColor(WebSkin::Accent));
    graphics.FillEllipse(
        &accent,
        static_cast<REAL>(margin),
        static_cast<REAL>(footer_y + Scale(25, dpi)),
        static_cast<REAL>(Scale(6, dpi)),
        static_cast<REAL>(Scale(6, dpi)));

    BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    EndPaint(window_, &paint);
}

std::wstring CloudOSNativeStartMenuWindow::ResultTitle(std::size_t index) const
{
    if (index >= results_.size())
    {
        return {};
    }
    const ResultRow& result = results_[index];
    if (result.kind == ResultKind::CloudOSApp)
    {
        if (result.cloud_app_index >= 0 && result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            return kAllApps[static_cast<std::size_t>(result.cloud_app_index)].name;
        }
        return L"CloudOS";
    }
    return result.indexed.title;
}

std::wstring CloudOSNativeStartMenuWindow::ResultSubtitle(std::size_t index) const
{
    if (index >= results_.size())
    {
        return {};
    }
    const ResultRow& result = results_[index];
    if (result.kind == ResultKind::CloudOSApp)
    {
        if (result.cloud_app_index >= 0 && result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            std::wstring subtitle = L"CloudOS  •  ";
            subtitle += kAllApps[static_cast<std::size_t>(result.cloud_app_index)].desc;
            return subtitle;
        }
        return L"Aplicativo CloudOS";
    }
    return result.indexed.subtitle.empty()
        ? std::wstring(L"Aplicativo do Windows")
        : result.indexed.subtitle;
}

LRESULT CloudOSNativeStartMenuWindow::CustomDrawResults(const NMLVCUSTOMDRAW& draw)
{
    switch (draw.nmcd.dwDrawStage)
    {
    case CDDS_PREPAINT:
        return CDRF_NOTIFYITEMDRAW;
    case CDDS_ITEMPREPAINT:
    {
        const std::size_t index = static_cast<std::size_t>(draw.nmcd.dwItemSpec);
        if (index >= results_.size())
        {
            return CDRF_DODEFAULT;
        }

        RECT row{};
        if (!ListView_GetItemRect(app_list_, static_cast<int>(index), &row, LVIR_BOUNDS))
        {
            return CDRF_DODEFAULT;
        }

        HDC dc = draw.nmcd.hdc;
        HBRUSH clear = CreateSolidBrush(WebSkin::BgPrimary);
        if (clear != nullptr)
        {
            FillRect(dc, &row, clear);
            DeleteObject(clear);
        }

        const UINT dpi = GetDpiForWindow(app_list_);
        const bool selected = (draw.nmcd.uItemState & CDIS_SELECTED) != 0;
        const bool hot = (draw.nmcd.uItemState & CDIS_HOT) != 0;

        Graphics graphics(dc);
        graphics.SetSmoothingMode(SmoothingModeAntiAlias);
        graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

        RectF card(
            static_cast<REAL>(row.left + Scale(3, dpi)),
            static_cast<REAL>(row.top + Scale(3, dpi)),
            static_cast<REAL>(std::max(1, Width(row) - Scale(6, dpi))),
            static_cast<REAL>(std::max(1, Height(row) - Scale(6, dpi))));
        if (selected || hot)
        {
            WebSkin::DrawRoundedPanel(
                graphics,
                card,
                static_cast<REAL>(Scale(WebSkin::RadiusMedium, dpi)),
                WebSkin::GdiColor(selected ? WebSkin::AccentSubtle : WebSkin::BgHover),
                WebSkin::GdiColor(selected ? WebSkin::Accent : WebSkin::BorderDefault, selected ? 125 : 80),
                1.0f);
        }

        const int icon_size = Scale(34, dpi);
        const int icon_x = row.left + Scale(13, dpi);
        const int icon_y = row.top + (Height(row) - icon_size) / 2;
        const ResultRow& result = results_[index];
        if (result.kind == ResultKind::CloudOSApp &&
            result.cloud_app_index >= 0 &&
            result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            NativeIconRenderer::DrawAetherSquircle(
                graphics,
                kAllApps[static_cast<std::size_t>(result.cloud_app_index)].icon_id,
                icon_x,
                icon_y,
                icon_size);
        }
        else
        {
            WebSkin::DrawRoundedPanel(
                graphics,
                RectF(
                    static_cast<REAL>(icon_x),
                    static_cast<REAL>(icon_y),
                    static_cast<REAL>(icon_size),
                    static_cast<REAL>(icon_size)),
                static_cast<REAL>(Scale(WebSkin::RadiusMedium, dpi)),
                WebSkin::GdiColor(WebSkin::BgTertiary),
                WebSkin::GdiColor(WebSkin::BorderDefault),
                1.0f);

            const std::wstring title = ResultTitle(index);
            const wchar_t initial[2]{title.empty() ? L'•' : title.front(), L'\0'};
            Font icon_font(
                L"Segoe UI Variable Display",
                static_cast<REAL>(Scale(15, dpi)),
                FontStyleBold,
                UnitPixel);
            SolidBrush icon_text(WebSkin::GdiColor(WebSkin::TextSecondary));
            StringFormat center;
            center.SetAlignment(StringAlignmentCenter);
            center.SetLineAlignment(StringAlignmentCenter);
            graphics.DrawString(
                initial,
                -1,
                &icon_font,
                RectF(
                    static_cast<REAL>(icon_x),
                    static_cast<REAL>(icon_y),
                    static_cast<REAL>(icon_size),
                    static_cast<REAL>(icon_size)),
                &center,
                &icon_text);
        }

        const int text_x = icon_x + icon_size + Scale(12, dpi);
        const int text_right = row.right - Scale(12, dpi);
        const std::wstring title = ResultTitle(index);
        const std::wstring subtitle = ResultSubtitle(index);

        Font title_font(
            L"Segoe UI Variable Text",
            static_cast<REAL>(Scale(13, dpi)),
            FontStyleRegular,
            UnitPixel);
        Font subtitle_font(
            L"Segoe UI Variable Text",
            static_cast<REAL>(Scale(10, dpi)),
            FontStyleRegular,
            UnitPixel);
        SolidBrush title_brush(WebSkin::GdiColor(WebSkin::TextPrimary));
        SolidBrush subtitle_brush(WebSkin::GdiColor(WebSkin::TextTertiary));
        StringFormat format;
        format.SetTrimming(StringTrimmingEllipsisCharacter);
        format.SetFormatFlags(StringFormatFlagsNoWrap);

        graphics.DrawString(
            title.c_str(),
            -1,
            &title_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(row.top + Scale(9, dpi)),
                static_cast<REAL>(std::max(1, text_right - text_x)),
                static_cast<REAL>(Scale(21, dpi))),
            &format,
            &title_brush);
        graphics.DrawString(
            subtitle.c_str(),
            -1,
            &subtitle_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(row.top + Scale(31, dpi)),
                static_cast<REAL>(std::max(1, text_right - text_x)),
                static_cast<REAL>(Scale(17, dpi))),
            &format,
            &subtitle_brush);

        return CDRF_SKIPDEFAULT;
    }
    default:
        return CDRF_DODEFAULT;
    }
}

LRESULT CloudOSNativeStartMenuWindow::DrawOwnerButton(const DRAWITEMSTRUCT& item)
{
    if (item.hDC == nullptr || item.hwndItem == nullptr)
    {
        return FALSE;
    }

    const int id = GetDlgCtrlID(item.hwndItem);
    const UINT dpi = GetDpiForWindow(item.hwndItem);
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool focused = (item.itemState & ODS_FOCUS) != 0;

    COLORREF fill = WebSkin::BgSecondary;
    COLORREF border = WebSkin::BorderDefault;
    COLORREF text = disabled ? WebSkin::TextDisabled : WebSkin::TextSecondary;

    if (id == kCommandId)
    {
        fill = pressed ? WebSkin::AccentActive : WebSkin::AccentSubtle;
        border = WebSkin::Accent;
        text = WebSkin::TextPrimary;
    }
    else if (pressed)
    {
        fill = WebSkin::BgActive;
        text = WebSkin::TextPrimary;
    }

    Graphics graphics(item.hDC);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(item.rcItem.left + 1),
            static_cast<REAL>(item.rcItem.top + 1),
            static_cast<REAL>(std::max<LONG>(1, item.rcItem.right - item.rcItem.left - 2)),
            static_cast<REAL>(std::max<LONG>(1, item.rcItem.bottom - item.rcItem.top - 2))),
        static_cast<REAL>(Scale(WebSkin::RadiusMedium, dpi)),
        WebSkin::GdiColor(fill),
        WebSkin::GdiColor(focused ? WebSkin::AccentHover : border),
        1.0f);

    std::array<wchar_t, 128> label{};
    GetWindowTextW(item.hwndItem, label.data(), static_cast<int>(label.size()));
    RECT text_rect = item.rcItem;
    DrawTextLine(
        item.hDC,
        id == kPowerId || id == kRefreshId ? title_font_ : font_,
        text,
        label.data(),
        text_rect,
        DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);
    return TRUE;
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
        std::wstring title = ResultTitle(row_index);
        LVITEMW item{};
        item.mask = LVIF_TEXT | LVIF_IMAGE;
        item.iItem = static_cast<int>(row_index);
        item.iImage = 0;
        item.pszText = title.data();
        ListView_InsertItem(app_list_, &item);
    }

    if (!results_.empty())
    {
        ListView_SetItemState(
            app_list_,
            0,
            LVIS_SELECTED | LVIS_FOCUSED,
            LVIS_SELECTED | LVIS_FOCUSED);
    }

    std::wstring footer = L"CloudOS  •  ";
    if (NativeStartIndex::Instance().Indexing())
    {
        footer += L"indexando aplicativos...";
    }
    else
    {
        footer += std::to_wstring(kAllApps.size());
        footer += L" nativos  •  ";
        footer += std::to_wstring(NativeStartIndex::Instance().Count());
        footer += L" Windows";
    }
    SetWindowTextW(footer_label_, footer.c_str());
    InvalidateRect(app_list_, nullptr, TRUE);
    InvalidateRect(window_, nullptr, FALSE);
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
    ListView_SetItemState(
        app_list_,
        selected,
        LVIS_SELECTED | LVIS_FOCUSED,
        LVIS_SELECTED | LVIS_FOCUSED);
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
    const int width = Scale(620, dpi);
    const int height = Scale(680, dpi);
    int x = taskbar_bounds.left + (taskbar_bounds.right - taskbar_bounds.left - width) / 2;
    int y = taskbar_bounds.top - height - Scale(12, dpi);
    x = std::clamp<int>(
        x,
        static_cast<int>(info.rcWork.left),
        std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(
        y,
        static_cast<int>(info.rcWork.top),
        std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));

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
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOZORDER | SWP_NOACTIVATE);
        }
        RebuildRowHeight();
        Layout();
        return 0;
    }
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
        if (LOWORD(w_param) == kSearchId)
        {
            if (HIWORD(w_param) == EN_CHANGE)
            {
                RefreshResults();
                return 0;
            }
            if (HIWORD(w_param) == EN_SETFOCUS)
            {
                search_focused_ = true;
                InvalidateRect(window_, nullptr, FALSE);
                return 0;
            }
            if (HIWORD(w_param) == EN_KILLFOCUS)
            {
                search_focused_ = false;
                InvalidateRect(window_, nullptr, FALSE);
                return 0;
            }
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
    case WM_DRAWITEM:
        if (l_param != 0)
        {
            return DrawOwnerButton(*reinterpret_cast<const DRAWITEMSTRUCT*>(l_param));
        }
        break;
    case WM_NOTIFY:
    {
        const auto* notification = reinterpret_cast<const NMHDR*>(l_param);
        if (notification != nullptr && notification->hwndFrom == app_list_)
        {
            if (notification->code == NM_CUSTOMDRAW)
            {
                return CustomDrawResults(*reinterpret_cast<const NMLVCUSTOMDRAW*>(l_param));
            }
            if (notification->code == NM_DBLCLK || notification->code == NM_RETURN)
            {
                ExecuteSelection();
                return 0;
            }
            if (notification->code == LVN_ITEMCHANGED)
            {
                InvalidateRect(app_list_, nullptr, FALSE);
                return 0;
            }
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
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextPrimary);
        SetBkColor(reinterpret_cast<HDC>(w_param), WebSkin::BgSecondary);
        return reinterpret_cast<LRESULT>(edit_background_);
    case WM_CTLCOLORSTATIC:
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextSecondary);
        SetBkColor(reinterpret_cast<HDC>(w_param), WebSkin::BgPrimary);
        return reinterpret_cast<LRESULT>(background_);
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
