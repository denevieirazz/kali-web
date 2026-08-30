#include "native_start_menu_window.h"

#include "native_app_launcher.h"
#include "native_icon_renderer.h"
#include "native_search_engine.h"
#include "native_start_menu_mru.h"
#include "native_popup_menu.h"
#include "native_theme.h"

#include <commctrl.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <uxtheme.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <filesystem>
#include <string>
#include <unordered_set>

#pragma comment(lib, "uxtheme.lib")
#pragma comment(lib, "shell32.lib")

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kStartClass[] = L"CloudOS.NativeShell.Start.v4";
constexpr int kSearchId = 9001;
constexpr int kListId = 9002;
constexpr int kCommandId = 9003;
constexpr int kPowerId = 9004;
constexpr int kAllAppsId = 9005;
constexpr UINT_PTR kSearchSubclass = 9006;
constexpr UINT_PTR kIndexTimer = 9007;

constexpr int kMenuWidthDip = 720;
constexpr int kMenuHeightDip = 760;

constexpr UINT kContextOpen = 9201;
constexpr UINT kContextToggleStartPin = 9202;
constexpr UINT kContextToggleTaskbarPin = 9203;
constexpr UINT kContextOpenLocation = 9204;
constexpr UINT kContextMoveLeft = 9205;
constexpr UINT kContextMoveRight = 9206;
constexpr UINT kContextRefreshIndex = 9207;
constexpr UINT kContextClearRecommendations = 9208;

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
    UINT format)
{
    if (dc == nullptr || text.empty())
    {
        return;
    }
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;
    const int old_mode = SetBkMode(dc, TRANSPARENT);
    const COLORREF old_color = SetTextColor(dc, color);
    (void)DrawTextW(dc, text.c_str(), -1, &rect, format);
    SetTextColor(dc, old_color);
    SetBkMode(dc, old_mode);
    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }
}

void DrawFallbackInitial(
    Graphics& graphics,
    const std::wstring& title,
    int x,
    int y,
    int size,
    UINT dpi)
{
    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(x),
            static_cast<REAL>(y),
            static_cast<REAL>(size),
            static_cast<REAL>(size)),
        static_cast<REAL>(Scale(WebSkin::RadiusMedium, dpi)),
        WebSkin::GdiColor(WebSkin::BgElevated),
        WebSkin::GdiColor(WebSkin::BorderStrong),
        1.0f);

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
            static_cast<REAL>(x),
            static_cast<REAL>(y),
            static_cast<REAL>(size),
            static_cast<REAL>(size)),
        &center,
        &icon_text);
}

bool DrawWindowsIcon(
    HDC dc,
    const std::wstring& target,
    int x,
    int y,
    int size)
{
    if (dc == nullptr || target.empty())
    {
        return false;
    }
    SHFILEINFOW info{};
    const DWORD_PTR result = SHGetFileInfoW(
        target.c_str(),
        0,
        &info,
        sizeof(info),
        SHGFI_ICON | SHGFI_LARGEICON);
    if (result == 0 || info.hIcon == nullptr)
    {
        return false;
    }
    const BOOL drawn = DrawIconEx(
        dc,
        x,
        y,
        info.hIcon,
        size,
        size,
        0,
        nullptr,
        DI_NORMAL);
    DestroyIcon(info.hIcon);
    return drawn != FALSE;
}

std::wstring Ellipsize(std::wstring value, std::size_t maximum)
{
    if (value.size() <= maximum)
    {
        return value;
    }
    if (maximum < 4)
    {
        value.resize(maximum);
        return value;
    }
    value.resize(maximum - 3);
    value += L"...";
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
        kMenuWidthDip,
        kMenuHeightDip,
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
        -Scale(16, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
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
    all_apps_button_ = CreateWindowW(
        L"BUTTON",
        L"Todos  ›",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kAllAppsId)),
        instance_,
        nullptr);
    app_list_ = CreateWindowExW(
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_TABSTOP |
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

    if (search_edit_ == nullptr || all_apps_button_ == nullptr || app_list_ == nullptr ||
        command_button_ == nullptr || power_button_ == nullptr || footer_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    for (HWND child : {search_edit_, all_apps_button_, app_list_, command_button_, power_button_, footer_label_})
    {
        SetControlFont(child, font_);
    }
    SetControlFont(footer_label_, small_font_);

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar aplicativos e comandos"));

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
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP | LVS_EX_TRACKSELECT);
    ListView_SetHoverTime(app_list_, 80);
    ListView_SetBkColor(app_list_, WebSkin::BgPrimary);
    ListView_SetTextBkColor(app_list_, WebSkin::BgPrimary);
    ListView_SetTextColor(app_list_, WebSkin::TextPrimary);

    LVCOLUMNW app_column{};
    app_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    app_column.pszText = const_cast<LPWSTR>(L"Aplicativo");
    app_column.cx = 650;
    ListView_InsertColumn(app_list_, 0, &app_column);

    (void)SetWindowTheme(app_list_, L"DarkMode_Explorer", nullptr);
    (void)SetWindowTheme(search_edit_, L"DarkMode_CFD", nullptr);
    WebSkin::PrepareButton(all_apps_button_);
    WebSkin::PrepareButton(command_button_);
    WebSkin::PrepareButton(power_button_);

    ApplyWebFlyoutMaterial(window_);
    RebuildRowHeight();
    Layout();
    NativeStartIndex::Instance().StartAsync();
    last_index_count_ = NativeStartIndex::Instance().Count();
    RefreshHome();
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
    all_apps_button_ = nullptr;
    command_button_ = nullptr;
    power_button_ = nullptr;
    footer_label_ = nullptr;
    results_.clear();
    start_pins_.clear();
    home_hits_.clear();

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

int CloudOSNativeStartMenuWindow::FindCloudApp(std::wstring_view id) const
{
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
    {
        if (id == kAllApps[index].id)
        {
            return static_cast<int>(index);
        }
    }
    return -1;
}

std::wstring CloudOSNativeStartMenuWindow::PinTitle(const ShellPinItem& pin) const
{
    if (pin.kind == ShellPinKind::CloudOSApp)
    {
        const int index = FindCloudApp(pin.id);
        if (index >= 0)
        {
            return kAllApps[static_cast<std::size_t>(index)].name;
        }
        return pin.id.empty() ? std::wstring(L"CloudOS") : pin.id;
    }
    if (!pin.title.empty())
    {
        return pin.title;
    }
    return L"Aplicativo";
}

std::wstring CloudOSNativeStartMenuWindow::PinSubtitle(const ShellPinItem& pin) const
{
    if (pin.kind == ShellPinKind::CloudOSApp)
    {
        const int index = FindCloudApp(pin.id);
        if (index >= 0)
        {
            return kAllApps[static_cast<std::size_t>(index)].desc;
        }
        return L"CloudOS";
    }
    return pin.subtitle.empty() ? std::wstring(L"Aplicativo do Windows") : pin.subtitle;
}

void CloudOSNativeStartMenuWindow::RefreshHome()
{
    start_pins_ = ShellPinStore::Instance().StartPins();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeStartMenuWindow::UpdateViewVisibility()
{
    const bool list_visible = view_mode_ != ViewMode::Home || !SearchText(search_edit_).empty();
    ShowWindow(app_list_, list_visible ? SW_SHOWNA : SW_HIDE);
    SetWindowTextW(all_apps_button_, list_visible ? L"‹  Voltar" : L"Todos  ›");
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
    const int row_height = Scale(64, dpi);
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
    const int search_height = Scale(46, dpi);
    const int all_width = Scale(92, dpi);
    const int footer_height = Scale(68, dpi);
    const int footer_y = height - footer_height;

    const int search_frame_right = width - margin - all_width - Scale(10, dpi);
    MoveWindow(
        search_edit_,
        margin + Scale(38, dpi),
        margin + Scale(10, dpi),
        std::max(80, search_frame_right - margin - Scale(50, dpi)),
        search_height - Scale(20, dpi),
        TRUE);
    MoveWindow(
        all_apps_button_,
        width - margin - all_width,
        margin,
        all_width,
        search_height,
        TRUE);

    const int list_y = margin + search_height + Scale(50, dpi);
    MoveWindow(
        app_list_,
        margin,
        list_y,
        width - margin * 2,
        std::max(80, footer_y - list_y - Scale(12, dpi)),
        TRUE);

    MoveWindow(
        footer_label_,
        margin + Scale(18, dpi),
        footer_y + Scale(21, dpi),
        std::max(100, width - Scale(330, dpi)),
        Scale(28, dpi),
        TRUE);
    MoveWindow(
        command_button_,
        width - margin - Scale(224, dpi),
        footer_y + Scale(14, dpi),
        Scale(170, dpi),
        Scale(40, dpi),
        TRUE);
    MoveWindow(
        power_button_,
        width - margin - Scale(44, dpi),
        footer_y + Scale(14, dpi),
        Scale(44, dpi),
        Scale(40, dpi),
        TRUE);

    ListView_SetColumnWidth(app_list_, 0, std::max(180, width - margin * 2 - Scale(8, dpi)));
    UpdateViewVisibility();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeStartMenuWindow::PaintHome(
    HDC dc,
    Graphics& graphics,
    UINT dpi,
    int width,
    int height)
{
    home_hits_.clear();
    const int margin = Scale(24, dpi);
    const int search_height = Scale(46, dpi);
    const int footer_y = height - Scale(68, dpi);
    const int content_width = width - margin * 2;

    Font section_font(
        L"Segoe UI Variable Display",
        static_cast<REAL>(Scale(15, dpi)),
        FontStyleBold,
        UnitPixel);
    Font tile_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(11, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font card_title_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(12, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font card_subtitle_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(9, dpi)),
        FontStyleRegular,
        UnitPixel);
    SolidBrush primary(WebSkin::GdiColor(WebSkin::TextPrimary));
    SolidBrush secondary(WebSkin::GdiColor(WebSkin::TextSecondary));
    SolidBrush tertiary(WebSkin::GdiColor(WebSkin::TextTertiary));

    const int pinned_title_y = margin + search_height + Scale(28, dpi);
    graphics.DrawString(
        L"Fixados",
        -1,
        &section_font,
        PointF(static_cast<REAL>(margin), static_cast<REAL>(pinned_title_y)),
        &primary);

    const int columns = std::clamp(content_width / Scale(112, dpi), 2, 6);
    const int gap = Scale(8, dpi);
    const int tile_width = std::max(72, (content_width - gap * (columns - 1)) / columns);
    const int tile_height = Scale(94, dpi);
    const int grid_y = pinned_title_y + Scale(31, dpi);
    const std::size_t visible_pins = start_pins_.size();

    auto draw_pin_icon = [this, dc, &graphics, dpi](const ShellPinItem& pin, int x, int y, int size)
    {
        if (pin.kind == ShellPinKind::CloudOSApp)
        {
            const int app_index = FindCloudApp(pin.id);
            if (app_index >= 0)
            {
                NativeIconRenderer::DrawAetherSquircle(
                    graphics,
                    kAllApps[static_cast<std::size_t>(app_index)].icon_id,
                    x,
                    y,
                    size);
                return;
            }
        }
        if (pin.kind == ShellPinKind::WindowsTarget && DrawWindowsIcon(dc, pin.target, x, y, size))
        {
            return;
        }
        DrawFallbackInitial(graphics, PinTitle(pin), x, y, size, dpi);
    };

    for (std::size_t index = 0; index < visible_pins; ++index)
    {
        const int column = static_cast<int>(index % static_cast<std::size_t>(columns));
        const int row = static_cast<int>(index / static_cast<std::size_t>(columns));
        const int x = margin + column * (tile_width + gap);
        const int y = grid_y + row * (tile_height + gap);
        RECT hit{x, y, x + tile_width, y + tile_height};
        home_hits_.push_back(HomeHit{hit, start_pins_[index], false});
        const int hit_index = static_cast<int>(home_hits_.size() - 1u);
        const bool hot = hovered_home_index_ == hit_index;

        if (hot)
        {
            WebSkin::DrawRoundedPanel(
                graphics,
                RectF(
                    static_cast<REAL>(x),
                    static_cast<REAL>(y),
                    static_cast<REAL>(tile_width),
                    static_cast<REAL>(tile_height)),
                static_cast<REAL>(Scale(WebSkin::RadiusLarge, dpi)),
                WebSkin::GdiColor(WebSkin::BgHover, 225),
                WebSkin::GdiColor(keyboard_home_navigation_ ? WebSkin::Accent : WebSkin::BorderStrong),
                keyboard_home_navigation_ ? 1.5f : 1.0f);
        }

        const int icon_size = Scale(40, dpi);
        const int icon_x = x + (tile_width - icon_size) / 2;
        const int icon_y = y + Scale(9, dpi);
        draw_pin_icon(start_pins_[index], icon_x, icon_y, icon_size);

        StringFormat center;
        center.SetAlignment(StringAlignmentCenter);
        center.SetLineAlignment(StringAlignmentNear);
        center.SetTrimming(StringTrimmingEllipsisCharacter);
        center.SetFormatFlags(StringFormatFlagsLineLimit);
        const std::wstring title = PinTitle(start_pins_[index]);
        graphics.DrawString(
            title.c_str(),
            -1,
            &tile_font,
            RectF(
                static_cast<REAL>(x + Scale(4, dpi)),
                static_cast<REAL>(y + Scale(56, dpi)),
                static_cast<REAL>(tile_width - Scale(8, dpi)),
                static_cast<REAL>(Scale(34, dpi))),
            &center,
            hot ? &primary : &secondary);
    }

    if (visible_pins == 0)
    {
        RECT empty_rect{margin, grid_y + Scale(12, dpi), width - margin, grid_y + Scale(52, dpi)};
        DrawTextLine(dc, small_font_, WebSkin::TextTertiary,
            L"Nenhum item fixado. Clique com o botao direito em um resultado para fixar.",
            empty_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    const int pinned_rows = std::max<int>(1, static_cast<int>((visible_pins + static_cast<std::size_t>(columns) - 1u) / static_cast<std::size_t>(columns)));
    const int recommended_y = grid_y + pinned_rows * (tile_height + gap) + Scale(18, dpi);
    graphics.DrawString(
        L"Recomendados",
        -1,
        &section_font,
        PointF(static_cast<REAL>(margin), static_cast<REAL>(recommended_y)),
        &primary);

    std::vector<std::wstring> recommended_ids = StartMenuMRUTracker::Instance().GetTopApps(8);
    for (const wchar_t* fallback : {L"files", L"browser", L"terminal", L"control", L"settings", L"sysmon"})
    {
        if (recommended_ids.size() >= 6u)
        {
            break;
        }
        if (std::find(recommended_ids.begin(), recommended_ids.end(), fallback) == recommended_ids.end())
        {
            recommended_ids.emplace_back(fallback);
        }
    }

    const int card_gap = Scale(10, dpi);
    const int card_width = (content_width - card_gap) / 2;
    const int card_height = Scale(58, dpi);
    const int cards_y = recommended_y + Scale(32, dpi);
    std::size_t rendered = 0;
    for (const std::wstring& id : recommended_ids)
    {
        if (rendered >= 6u)
        {
            break;
        }
        const int app_index = FindCloudApp(id);
        if (app_index < 0)
        {
            continue;
        }
        const int column = static_cast<int>(rendered % 2u);
        const int row = static_cast<int>(rendered / 2u);
        const int x = margin + column * (card_width + card_gap);
        const int y = cards_y + row * (card_height + Scale(8, dpi));
        RECT hit{x, y, x + card_width, y + card_height};
        ShellPinItem pin{};
        pin.kind = ShellPinKind::CloudOSApp;
        pin.id = id;
        home_hits_.push_back(HomeHit{hit, pin, true});
        const int hit_index = static_cast<int>(home_hits_.size() - 1u);
        const bool hot = hovered_home_index_ == hit_index;

        WebSkin::DrawRoundedPanel(
            graphics,
            RectF(
                static_cast<REAL>(x),
                static_cast<REAL>(y),
                static_cast<REAL>(card_width),
                static_cast<REAL>(card_height)),
            static_cast<REAL>(Scale(WebSkin::RadiusLarge, dpi)),
            WebSkin::GdiColor(hot ? WebSkin::BgHover : WebSkin::BgSecondary, 218),
            WebSkin::GdiColor(
                hot && keyboard_home_navigation_ ? WebSkin::Accent :
                hot ? WebSkin::BorderStrong : WebSkin::BorderDefault),
            hot && keyboard_home_navigation_ ? 1.5f : 1.0f);

        const int icon_size = Scale(34, dpi);
        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            x + Scale(12, dpi),
            y + (card_height - icon_size) / 2,
            icon_size);

        const int text_x = x + Scale(58, dpi);
        const std::wstring title = kAllApps[static_cast<std::size_t>(app_index)].name;
        const std::wstring subtitle = kAllApps[static_cast<std::size_t>(app_index)].desc;
        StringFormat trim;
        trim.SetTrimming(StringTrimmingEllipsisCharacter);
        trim.SetFormatFlags(StringFormatFlagsNoWrap);
        graphics.DrawString(
            title.c_str(), -1, &card_title_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(y + Scale(9, dpi)),
                static_cast<REAL>(card_width - Scale(70, dpi)),
                static_cast<REAL>(Scale(20, dpi))),
            &trim, &primary);
        graphics.DrawString(
            subtitle.c_str(), -1, &card_subtitle_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(y + Scale(31, dpi)),
                static_cast<REAL>(card_width - Scale(70, dpi)),
                static_cast<REAL>(Scale(17, dpi))),
            &trim, &tertiary);
        ++rendered;
    }

    const int hint_y = footer_y - Scale(30, dpi);
    RECT hint_rect{margin, hint_y, width - margin, footer_y - Scale(5, dpi)};
    DrawTextLine(
        dc,
        small_font_,
        WebSkin::TextTertiary,
        L"Setas navegam  ·  Enter abre  ·  Shift+F10 menu  ·  Digite para pesquisar  ·  F5 reindexa",
        hint_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);
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
        PointF(static_cast<REAL>(width), static_cast<REAL>(height)),
        WebSkin::GdiColor(WebSkin::BgSecondary),
        WebSkin::GdiColor(WebSkin::BgSolid));
    graphics.FillRectangle(
        &background,
        RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(24, dpi);
    const int search_height = Scale(46, dpi);
    const int all_width = Scale(92, dpi);
    const int search_width = width - margin * 2 - all_width - Scale(10, dpi);

    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(margin),
            static_cast<REAL>(margin),
            static_cast<REAL>(std::max(1, search_width)),
            static_cast<REAL>(search_height)),
        static_cast<REAL>(Scale(WebSkin::RadiusLarge, dpi)),
        WebSkin::GdiColor(search_focused_ ? WebSkin::BgTertiary : WebSkin::BgSecondary),
        WebSkin::GdiColor(search_focused_ ? WebSkin::Accent : WebSkin::BorderDefault),
        search_focused_ ? 1.5f : 1.0f);

    Pen search_pen(WebSkin::GdiColor(search_focused_ ? WebSkin::AccentHover : WebSkin::TextTertiary), 1.6f);
    const REAL lens_x = static_cast<REAL>(margin + Scale(16, dpi));
    const REAL lens_y = static_cast<REAL>(margin + Scale(14, dpi));
    const REAL lens_size = static_cast<REAL>(Scale(12, dpi));
    graphics.DrawEllipse(&search_pen, lens_x, lens_y, lens_size, lens_size);
    graphics.DrawLine(
        &search_pen,
        lens_x + lens_size - 1.0f,
        lens_y + lens_size - 1.0f,
        lens_x + lens_size + static_cast<REAL>(Scale(5, dpi)),
        lens_y + lens_size + static_cast<REAL>(Scale(5, dpi)));

    const bool list_visible = view_mode_ != ViewMode::Home || !SearchText(search_edit_).empty();
    if (!list_visible)
    {
        PaintHome(memory_dc, graphics, dpi, width, height);
    }
    else
    {
        RECT section_title{
            margin,
            margin + search_height + Scale(18, dpi),
            width - margin,
            margin + search_height + Scale(42, dpi)};
        const std::wstring heading = SearchText(search_edit_).empty()
            ? std::wstring(L"Todos os aplicativos")
            : std::wstring(L"Resultados");
        DrawTextLine(
            memory_dc,
            title_font_,
            WebSkin::TextPrimary,
            heading,
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
        DrawTextLine(
            memory_dc,
            small_font_,
            WebSkin::TextTertiary,
            section_meta,
            section_title,
            DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    const int footer_y = height - Scale(68, dpi);
    Pen footer_border(WebSkin::GdiColor(WebSkin::BorderDefault, 190), 1.0f);
    graphics.DrawLine(
        &footer_border,
        static_cast<REAL>(margin),
        static_cast<REAL>(footer_y),
        static_cast<REAL>(width - margin),
        static_cast<REAL>(footer_y));

    SolidBrush accent(WebSkin::GdiColor(WebSkin::Accent));
    graphics.FillEllipse(
        &accent,
        static_cast<REAL>(margin),
        static_cast<REAL>(footer_y + Scale(27, dpi)),
        static_cast<REAL>(Scale(7, dpi)),
        static_cast<REAL>(Scale(7, dpi)));

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

ShellPinItem CloudOSNativeStartMenuWindow::PinFromResult(const ResultRow& result) const
{
    ShellPinItem pin{};
    if (result.kind == ResultKind::CloudOSApp)
    {
        pin.kind = ShellPinKind::CloudOSApp;
        if (result.cloud_app_index >= 0 && result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            const AppItem& app = kAllApps[static_cast<std::size_t>(result.cloud_app_index)];
            pin.id = app.id;
            pin.title = app.name;
            pin.subtitle = app.desc;
        }
        return pin;
    }
    pin.kind = ShellPinKind::WindowsTarget;
    pin.title = result.indexed.title;
    pin.subtitle = result.indexed.subtitle;
    pin.target = result.indexed.launch_target;
    return pin;
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
        WebSkin::DrawRoundedPanel(
            graphics,
            card,
            static_cast<REAL>(Scale(WebSkin::RadiusLarge, dpi)),
            WebSkin::GdiColor(
                selected ? WebSkin::AccentSubtle :
                hot ? WebSkin::BgHover : WebSkin::BgSecondary,
                selected ? 255 : 220),
            WebSkin::GdiColor(
                selected ? WebSkin::Accent :
                hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
                selected ? 150 : 95),
            1.0f);

        const int icon_size = Scale(38, dpi);
        const int icon_x = row.left + Scale(14, dpi);
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
        else if (!DrawWindowsIcon(dc, result.indexed.launch_target, icon_x, icon_y, icon_size))
        {
            DrawFallbackInitial(graphics, ResultTitle(index), icon_x, icon_y, icon_size, dpi);
        }

        const int text_x = icon_x + icon_size + Scale(13, dpi);
        const int text_right = row.right - Scale(54, dpi);
        const std::wstring title = ResultTitle(index);
        const std::wstring subtitle = ResultSubtitle(index);

        Font row_title_font(
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
            title.c_str(), -1, &row_title_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(row.top + Scale(10, dpi)),
                static_cast<REAL>(std::max(1, text_right - text_x)),
                static_cast<REAL>(Scale(21, dpi))),
            &format, &title_brush);
        graphics.DrawString(
            subtitle.c_str(), -1, &subtitle_font,
            RectF(
                static_cast<REAL>(text_x),
                static_cast<REAL>(row.top + Scale(34, dpi)),
                static_cast<REAL>(std::max(1, text_right - text_x)),
                static_cast<REAL>(Scale(17, dpi))),
            &format, &subtitle_brush);

        const ShellPinItem pin = PinFromResult(result);
        if (ShellPinStore::Instance().IsStartPinned(pin))
        {
            SolidBrush pin_brush(WebSkin::GdiColor(WebSkin::AccentHover));
            graphics.FillEllipse(
                &pin_brush,
                static_cast<REAL>(row.right - Scale(30, dpi)),
                static_cast<REAL>(row.top + (Height(row) - Scale(8, dpi)) / 2),
                static_cast<REAL>(Scale(8, dpi)),
                static_cast<REAL>(Scale(8, dpi)));
        }

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
    if (id == kCommandId)
    {
        return WebSkin::PaintOwnerDrawButton(&item, WebSkin::ButtonTone::Accent) ? TRUE : FALSE;
    }
    if (id == kPowerId)
    {
        return WebSkin::PaintOwnerDrawButton(&item, WebSkin::ButtonTone::Danger) ? TRUE : FALSE;
    }
    return WebSkin::PaintOwnerDrawButton(&item, WebSkin::ButtonTone::Neutral) ? TRUE : FALSE;
}

void CloudOSNativeStartMenuWindow::RefreshResults()
{
    if (app_list_ == nullptr)
    {
        return;
    }

    const std::wstring query = SearchText(search_edit_);
    if (!query.empty())
    {
        view_mode_ = ViewMode::Search;
        hovered_home_index_ = -1;
        keyboard_home_navigation_ = false;
    }
    else if (view_mode_ == ViewMode::Search)
    {
        view_mode_ = ViewMode::Home;
    }

    if (view_mode_ == ViewMode::Home && query.empty())
    {
        results_.clear();
        ListView_DeleteAllItems(app_list_);
        RefreshHome();
        UpdateViewVisibility();
    }
    else
    {
        results_.clear();
        ListView_DeleteAllItems(app_list_);

        const std::vector<int> cloud_results = NativeSearchEngine::FilterApps(query);
        const std::size_t cloud_limit = query.empty() ? kAllApps.size() : 28u;
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

        const std::size_t windows_limit = query.empty() ? 220u : 90u;
        const auto indexed_results = NativeStartIndex::Instance().Query(query, windows_limit);
        std::unordered_set<std::wstring> seen_titles;
        for (const auto& indexed : indexed_results)
        {
            const std::wstring key = Lower(indexed.title);
            if (!key.empty() && !seen_titles.insert(key).second)
            {
                continue;
            }
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
        UpdateViewVisibility();
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

void CloudOSNativeStartMenuWindow::ExecutePin(const ShellPinItem& pin)
{
    Hide();
    if (pin.kind == ShellPinKind::CloudOSApp)
    {
        const int index = FindCloudApp(pin.id);
        if (index >= 0)
        {
            NativeAppLauncher::Launch(
                instance_,
                nullptr,
                kAllApps[static_cast<std::size_t>(index)]);
        }
        return;
    }

    if (!pin.target.empty())
    {
        const HINSTANCE result = ShellExecuteW(
            nullptr,
            L"open",
            pin.target.c_str(),
            nullptr,
            nullptr,
            SW_SHOWNORMAL);
        if (reinterpret_cast<INT_PTR>(result) <= 32)
        {
            MessageBoxW(
                nullptr,
                L"O Windows nao conseguiu abrir este aplicativo.",
                L"CloudOS",
                MB_OK | MB_ICONERROR);
        }
    }
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
    if (result.kind == ResultKind::CloudOSApp)
    {
        if (result.cloud_app_index >= 0 && result.cloud_app_index < static_cast<int>(kAllApps.size()))
        {
            Hide();
            NativeAppLauncher::Launch(
                instance_,
                nullptr,
                kAllApps[static_cast<std::size_t>(result.cloud_app_index)]);
        }
        return;
    }

    Hide();
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

void CloudOSNativeStartMenuWindow::MoveHomeSelection(int horizontal, int vertical)
{
    if (window_ == nullptr || view_mode_ != ViewMode::Home || !SearchText(search_edit_).empty())
    {
        return;
    }

    if (home_hits_.empty())
    {
        InvalidateRect(window_, nullptr, FALSE);
        UpdateWindow(window_);
    }
    if (home_hits_.empty())
    {
        return;
    }

    keyboard_home_navigation_ = true;
    if (hovered_home_index_ < 0 || hovered_home_index_ >= static_cast<int>(home_hits_.size()))
    {
        hovered_home_index_ = (horizontal < 0 || vertical < 0)
            ? static_cast<int>(home_hits_.size()) - 1
            : 0;
        InvalidateRect(window_, nullptr, FALSE);
        return;
    }

    const RECT current = home_hits_[static_cast<std::size_t>(hovered_home_index_)].rect;
    const long current_x = (current.left + current.right) / 2;
    const long current_y = (current.top + current.bottom) / 2;
    long long best_score = 0x7fffffffffffffffLL;
    int best_index = hovered_home_index_;

    for (std::size_t index = 0; index < home_hits_.size(); ++index)
    {
        if (static_cast<int>(index) == hovered_home_index_)
        {
            continue;
        }
        const RECT candidate = home_hits_[index].rect;
        const long candidate_x = (candidate.left + candidate.right) / 2;
        const long candidate_y = (candidate.top + candidate.bottom) / 2;
        const long delta_x = candidate_x - current_x;
        const long delta_y = candidate_y - current_y;

        if ((horizontal < 0 && delta_x >= 0) ||
            (horizontal > 0 && delta_x <= 0) ||
            (vertical < 0 && delta_y >= 0) ||
            (vertical > 0 && delta_y <= 0))
        {
            continue;
        }

        const long primary = horizontal != 0 ? std::abs(delta_x) : std::abs(delta_y);
        const long secondary = horizontal != 0 ? std::abs(delta_y) : std::abs(delta_x);
        const long long score = static_cast<long long>(primary) * 1000LL + secondary;
        if (score < best_score)
        {
            best_score = score;
            best_index = static_cast<int>(index);
        }
    }

    hovered_home_index_ = best_index;
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeStartMenuWindow::SelectHomeEdge(bool last)
{
    if (window_ == nullptr || view_mode_ != ViewMode::Home || !SearchText(search_edit_).empty())
    {
        return;
    }
    if (home_hits_.empty())
    {
        InvalidateRect(window_, nullptr, FALSE);
        UpdateWindow(window_);
    }
    if (home_hits_.empty())
    {
        return;
    }
    keyboard_home_navigation_ = true;
    hovered_home_index_ = last ? static_cast<int>(home_hits_.size()) - 1 : 0;
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeStartMenuWindow::ActivateHomeSelection()
{
    if (hovered_home_index_ < 0 || hovered_home_index_ >= static_cast<int>(home_hits_.size()))
    {
        return;
    }
    ExecutePin(home_hits_[static_cast<std::size_t>(hovered_home_index_)].pin);
}

void CloudOSNativeStartMenuWindow::ShowHomeSelectionContextMenu()
{
    if (hovered_home_index_ < 0 || hovered_home_index_ >= static_cast<int>(home_hits_.size()))
    {
        return;
    }
    const RECT rect = home_hits_[static_cast<std::size_t>(hovered_home_index_)].rect;
    POINT point{(rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2};
    ClientToScreen(window_, &point);
    ShowPinContextMenu(static_cast<std::size_t>(hovered_home_index_), point);
}

void CloudOSNativeStartMenuWindow::RefreshIndexer()
{
    NativeStartIndex::Instance().RefreshAsync();
    last_index_count_ = 0;
    RefreshResults();
}

void CloudOSNativeStartMenuWindow::ToggleAllApps()
{
    SetWindowTextW(search_edit_, L"");
    view_mode_ = view_mode_ == ViewMode::Home ? ViewMode::AllApps : ViewMode::Home;
    hovered_home_index_ = -1;
    keyboard_home_navigation_ = false;
    RefreshResults();
    if (view_mode_ == ViewMode::AllApps && app_list_ != nullptr)
    {
        SetFocus(app_list_);
    }
    else
    {
        FocusSearch();
    }
}

void CloudOSNativeStartMenuWindow::OpenIndexedLocation(const NativeStartIndexEntry& entry)
{
    if (entry.launch_target.empty())
    {
        return;
    }

    if (entry.launch_target.rfind(L"shell:", 0) == 0 ||
        entry.launch_target.find(L"::{") != std::wstring::npos)
    {
        (void)ShellExecuteW(
            window_,
            L"open",
            L"explorer.exe",
            L"shell:AppsFolder",
            nullptr,
            SW_SHOWNORMAL);
        return;
    }

    std::wstring parameters = L"/select,\"";
    parameters += entry.launch_target;
    parameters += L"\"";
    (void)ShellExecuteW(
        window_,
        L"open",
        L"explorer.exe",
        parameters.c_str(),
        nullptr,
        SW_SHOWNORMAL);
}

void CloudOSNativeStartMenuWindow::ShowResultContextMenu(int row, POINT screen_point)
{
    if (row < 0 || row >= static_cast<int>(results_.size()))
    {
        return;
    }
    const ResultRow result = results_[static_cast<std::size_t>(row)];
    const ShellPinItem pin = PinFromResult(result);
    ShellPinStore& store = ShellPinStore::Instance();

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }
    AppendMenuW(menu, MF_STRING, kContextOpen, L"Abrir");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        menu,
        MF_STRING,
        kContextToggleStartPin,
        store.IsStartPinned(pin) ? L"Desafixar do Iniciar" : L"Fixar no Iniciar");
    AppendMenuW(
        menu,
        MF_STRING,
        kContextToggleTaskbarPin,
        store.IsTaskbarPinned(pin) ? L"Desafixar da barra" : L"Fixar na barra");
    if (result.kind == ResultKind::IndexedWindowsApp)
    {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kContextOpenLocation, L"Abrir local do aplicativo");
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kContextRefreshIndex, L"Reindexar aplicativos  (F5)");

    const int command = NativePopupMenu::Track(
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
    case kContextOpen:
        ListView_SetItemState(app_list_, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
        ListView_SetItemState(app_list_, row, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
        ExecuteSelection();
        break;
    case kContextToggleStartPin:
        store.ToggleStart(pin);
        RefreshHome();
        RefreshResults();
        break;
    case kContextToggleTaskbarPin:
        store.ToggleTaskbar(pin);
        InvalidateRect(window_, nullptr, FALSE);
        break;
    case kContextOpenLocation:
        if (result.kind == ResultKind::IndexedWindowsApp)
        {
            OpenIndexedLocation(result.indexed);
        }
        break;
    case kContextRefreshIndex:
        RefreshIndexer();
        break;
    default:
        break;
    }
}

void CloudOSNativeStartMenuWindow::ShowPinContextMenu(
    std::size_t hit_index,
    POINT screen_point)
{
    if (hit_index >= home_hits_.size())
    {
        return;
    }
    const HomeHit hit = home_hits_[hit_index];
    ShellPinStore& store = ShellPinStore::Instance();
    const bool start_pinned = store.IsStartPinned(hit.pin);
    const bool taskbar_pinned = store.IsTaskbarPinned(hit.pin);

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }
    AppendMenuW(menu, MF_STRING, kContextOpen, L"Abrir");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        menu,
        MF_STRING,
        kContextToggleStartPin,
        start_pinned ? L"Desafixar do Iniciar" : L"Fixar no Iniciar");
    AppendMenuW(
        menu,
        MF_STRING,
        kContextToggleTaskbarPin,
        taskbar_pinned ? L"Desafixar da barra" : L"Fixar na barra");

    std::size_t pinned_index = start_pins_.size();
    for (std::size_t index = 0; index < start_pins_.size(); ++index)
    {
        if (ShellPinStore::SameIdentity(start_pins_[index], hit.pin))
        {
            pinned_index = index;
            break;
        }
    }
    if (start_pinned && pinned_index < start_pins_.size())
    {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(
            menu,
            pinned_index > 0 ? MF_STRING : MF_STRING | MF_GRAYED,
            kContextMoveLeft,
            L"Mover para a esquerda");
        AppendMenuW(
            menu,
            pinned_index + 1u < start_pins_.size() ? MF_STRING : MF_STRING | MF_GRAYED,
            kContextMoveRight,
            L"Mover para a direita");
    }
    if (hit.recommended)
    {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kContextClearRecommendations, L"Redefinir recomendacoes");
    }

    const int command = NativePopupMenu::Track(
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
    case kContextOpen:
        ExecutePin(hit.pin);
        break;
    case kContextToggleStartPin:
        store.ToggleStart(hit.pin);
        RefreshHome();
        break;
    case kContextToggleTaskbarPin:
        store.ToggleTaskbar(hit.pin);
        InvalidateRect(window_, nullptr, FALSE);
        break;
    case kContextMoveLeft:
        if (pinned_index > 0 && pinned_index < start_pins_.size())
        {
            store.MoveStart(pinned_index, pinned_index - 1u);
            RefreshHome();
        }
        break;
    case kContextMoveRight:
        if (pinned_index + 1u < start_pins_.size())
        {
            store.MoveStart(pinned_index, pinned_index + 1u);
            RefreshHome();
        }
        break;
    case kContextClearRecommendations:
        StartMenuMRUTracker::Instance().Clear();
        hovered_home_index_ = -1;
        keyboard_home_navigation_ = false;
        RefreshHome();
        break;
    default:
        break;
    }
}

void CloudOSNativeStartMenuWindow::ShowNear(const RECT& taskbar_bounds)
{
    if (window_ == nullptr)
    {
        return;
    }

    NativeStartIndex::Instance().StartAsync();
    SetWindowTextW(search_edit_, L"");
    view_mode_ = ViewMode::Home;
    hovered_home_index_ = -1;
    keyboard_home_navigation_ = false;
    RefreshHome();
    RefreshResults();

    HMONITOR monitor = MonitorFromRect(&taskbar_bounds, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(kMenuWidthDip, dpi);
    const int height = Scale(kMenuHeightDip, dpi);
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
        keyboard_home_navigation_ = false;
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
            if (IsWindowVisible(window_))
            {
                const std::size_t count = NativeStartIndex::Instance().Count();
                if (count != last_index_count_ || NativeStartIndex::Instance().Indexing())
                {
                    last_index_count_ = count;
                    RefreshResults();
                }
            }
            return 0;
        }
        break;
    case WM_MOUSEMOVE:
        if (view_mode_ == ViewMode::Home)
        {
            keyboard_home_navigation_ = false;
            if (!tracking_mouse_)
            {
                TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window_, 0};
                (void)TrackMouseEvent(&tracking);
                tracking_mouse_ = true;
            }
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            int next_hover = -1;
            for (std::size_t index = 0; index < home_hits_.size(); ++index)
            {
                if (Contains(home_hits_[index].rect, point))
                {
                    next_hover = static_cast<int>(index);
                    break;
                }
            }
            if (next_hover != hovered_home_index_)
            {
                hovered_home_index_ = next_hover;
                InvalidateRect(window_, nullptr, FALSE);
            }
            SetCursor(LoadCursorW(nullptr, next_hover >= 0 ? IDC_HAND : IDC_ARROW));
        }
        return 0;
    case WM_MOUSELEAVE:
        tracking_mouse_ = false;
        if (!keyboard_home_navigation_)
        {
            hovered_home_index_ = -1;
            InvalidateRect(window_, nullptr, FALSE);
        }
        return 0;
    case WM_LBUTTONUP:
        if (view_mode_ == ViewMode::Home)
        {
            keyboard_home_navigation_ = false;
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (const HomeHit& hit : home_hits_)
            {
                if (Contains(hit.rect, point))
                {
                    ExecutePin(hit.pin);
                    return 0;
                }
            }
        }
        break;
    case WM_RBUTTONUP:
        if (view_mode_ == ViewMode::Home)
        {
            keyboard_home_navigation_ = false;
            const POINT client_point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < home_hits_.size(); ++index)
            {
                if (Contains(home_hits_[index].rect, client_point))
                {
                    hovered_home_index_ = static_cast<int>(index);
                    POINT screen_point = client_point;
                    ClientToScreen(window_, &screen_point);
                    ShowPinContextMenu(index, screen_point);
                    return 0;
                }
            }
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
        if (LOWORD(w_param) == kAllAppsId)
        {
            ToggleAllApps();
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
            if (notification->code == NM_RCLICK)
            {
                POINT screen{};
                GetCursorPos(&screen);
                POINT client = screen;
                ScreenToClient(app_list_, &client);
                LVHITTESTINFO hit{};
                hit.pt = client;
                const int row = ListView_HitTest(app_list_, &hit);
                if (row >= 0)
                {
                    ShowResultContextMenu(row, screen);
                }
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
        if (view_mode_ == ViewMode::Home && SearchText(search_edit_).empty())
        {
            switch (w_param)
            {
            case VK_LEFT:
                MoveHomeSelection(-1, 0);
                return 0;
            case VK_RIGHT:
                MoveHomeSelection(1, 0);
                return 0;
            case VK_UP:
                MoveHomeSelection(0, -1);
                return 0;
            case VK_DOWN:
                MoveHomeSelection(0, 1);
                return 0;
            case VK_HOME:
                SelectHomeEdge(false);
                return 0;
            case VK_END:
                SelectHomeEdge(true);
                return 0;
            case VK_RETURN:
            case VK_SPACE:
                ActivateHomeSelection();
                return 0;
            case VK_APPS:
                ShowHomeSelectionContextMenu();
                return 0;
            case VK_F10:
                if ((GetKeyState(VK_SHIFT) & 0x8000) != 0)
                {
                    ShowHomeSelectionContextMenu();
                    return 0;
                }
                break;
            default:
                break;
            }
        }
        if (w_param == L'F' && (GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            FocusSearch();
            return 0;
        }
        if (w_param == VK_ESCAPE)
        {
            if (view_mode_ != ViewMode::Home)
            {
                SetWindowTextW(search_edit_, L"");
                view_mode_ = ViewMode::Home;
                hovered_home_index_ = -1;
                keyboard_home_navigation_ = false;
                RefreshResults();
                FocusSearch();
            }
            else
            {
                Hide();
            }
            return 0;
        }
        if (w_param == VK_F5)
        {
            RefreshIndexer();
            return 0;
        }
        break;
    case WM_CHAR:
        if (view_mode_ == ViewMode::Home &&
            SearchText(search_edit_).empty() &&
            w_param >= 0x21 &&
            (GetKeyState(VK_CONTROL) & 0x8000) == 0 &&
            (GetKeyState(VK_MENU) & 0x8000) == 0)
        {
            FocusSearch();
            SendMessageW(search_edit_, WM_CHAR, w_param, l_param);
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
        const bool home_empty = self->view_mode_ == ViewMode::Home && SearchText(window).empty();
        switch (w_param)
        {
        case VK_DOWN:
            if (home_empty)
            {
                self->MoveHomeSelection(0, 1);
                SetFocus(self->window_);
                return 0;
            }
            self->MoveSelection(1);
            SetFocus(self->app_list_);
            return 0;
        case VK_UP:
            if (home_empty)
            {
                self->MoveHomeSelection(0, -1);
                SetFocus(self->window_);
                return 0;
            }
            self->MoveSelection(-1);
            SetFocus(self->app_list_);
            return 0;
        case VK_LEFT:
            if (home_empty)
            {
                self->MoveHomeSelection(-1, 0);
                SetFocus(self->window_);
                return 0;
            }
            break;
        case VK_RIGHT:
            if (home_empty)
            {
                self->MoveHomeSelection(1, 0);
                SetFocus(self->window_);
                return 0;
            }
            break;
        case VK_HOME:
            if (home_empty)
            {
                self->SelectHomeEdge(false);
                SetFocus(self->window_);
                return 0;
            }
            break;
        case VK_END:
            if (home_empty)
            {
                self->SelectHomeEdge(true);
                SetFocus(self->window_);
                return 0;
            }
            break;
        case VK_RETURN:
            if (home_empty)
            {
                self->ActivateHomeSelection();
            }
            else
            {
                self->ExecuteSelection();
            }
            return 0;
        case VK_APPS:
            if (home_empty)
            {
                self->ShowHomeSelectionContextMenu();
                return 0;
            }
            break;
        case VK_F10:
            if (home_empty && (GetKeyState(VK_SHIFT) & 0x8000) != 0)
            {
                self->ShowHomeSelectionContextMenu();
                return 0;
            }
            break;
        case VK_ESCAPE:
            if (self->view_mode_ != ViewMode::Home || !SearchText(window).empty())
            {
                SetWindowTextW(window, L"");
                self->view_mode_ = ViewMode::Home;
                self->hovered_home_index_ = -1;
                self->keyboard_home_navigation_ = false;
                self->RefreshResults();
            }
            else
            {
                self->Hide();
            }
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
