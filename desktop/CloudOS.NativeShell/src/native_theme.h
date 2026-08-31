#include "native_design_system_v12.h"
#pragma once

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <gdiplus.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <iterator>
#include <string>
#include <string_view>

namespace CloudOS
{
constexpr int kBottomBarHeight = 48;
constexpr UINT_PTR kReconcileTimer = 1;
constexpr UINT_PTR kMetricsTimer = 2;

namespace WebSkin
{
// Visual Experience V7 foundation. The shell stays native Win32/DWM, but the
// material system now carries Fluent-style reveal lighting, stronger depth,
// ambient color and motion primitives instead of flat dark rectangles.
constexpr COLORREF BgSolid = DesignV12::Canvas;
constexpr COLORREF BgPrimary = DesignV12::Background;
constexpr COLORREF BgSecondary = DesignV12::Surface;
constexpr COLORREF BgTertiary = DesignV12::Raised;
constexpr COLORREF BgElevated = DesignV12::Raised;
constexpr COLORREF BgHover = DesignV12::Hover;
constexpr COLORREF BgActive = DesignV12::Active;
inline COLORREF Accent = DesignV12::Accent;
inline COLORREF AccentHover = DesignV12::AccentHover;
inline COLORREF AccentActive = DesignV12::AccentPressed;
inline COLORREF AccentSubtle = DesignV12::AccentSubtle;
inline COLORREF AccentCyan = DesignV12::Accent;
constexpr COLORREF TextPrimary = DesignV12::Text;
constexpr COLORREF TextSecondary = DesignV12::Secondary;
constexpr COLORREF TextTertiary = DesignV12::Caption;
constexpr COLORREF TextDisabled = DesignV12::Disabled;
constexpr COLORREF BorderDefault = DesignV12::Border;
constexpr COLORREF BorderSubtle = DesignV12::Border;
constexpr COLORREF BorderStrong = DesignV12::BorderStrong;
constexpr COLORREF Danger = DesignV12::Danger;
constexpr int RadiusSmall = DesignV12::RadiusSmall;
constexpr int RadiusMedium = DesignV12::RadiusMedium;
constexpr int RadiusLarge = DesignV12::RadiusLarge;
constexpr int RadiusXL = DesignV12::RadiusLarge;
constexpr UINT MotionFrameMilliseconds = 16; // target cadence; compositor decides final refresh cadence.
constexpr UINT_PTR WindowSubclassId = 0xC10D5A11;

enum class ButtonTone { Neutral, Accent, Danger };

inline Gdiplus::Color GdiColor(COLORREF color, BYTE alpha = 255) noexcept
{
    const BYTE red = static_cast<BYTE>(color & 0xFFu);
    const BYTE green = static_cast<BYTE>((color >> 8u) & 0xFFu);
    const BYTE blue = static_cast<BYTE>((color >> 16u) & 0xFFu);
    return Gdiplus::Color(alpha, red, green, blue);
}

inline float ClampUnit(float value) noexcept
{
    return std::clamp(value, 0.0f, 1.0f);
}

inline float EaseOutCubic(float value) noexcept
{
    const float t = 1.0f - ClampUnit(value);
    return 1.0f - t * t * t;
}

inline float EaseOutQuint(float value) noexcept
{
    const float t = 1.0f - ClampUnit(value);
    return 1.0f - t * t * t * t * t;
}

inline void DrawRoundedPanel(
    Gdiplus::Graphics& graphics,
    const Gdiplus::RectF& rect,
    float radius,
    Gdiplus::Color fill,
    Gdiplus::Color border,
    float border_width = 1.0f)
{
    const float safe_radius = std::max(0.0f, std::min(radius, std::min(rect.Width, rect.Height) / 2.0f));
    const float diameter = safe_radius * 2.0f;
    Gdiplus::GraphicsPath path;
    if (diameter <= 0.0f)
        path.AddRectangle(rect);
    else
    {
        path.AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
        path.AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270.0f, 90.0f);
        path.AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter, diameter, diameter, 0.0f, 90.0f);
        path.AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90.0f, 90.0f);
        path.CloseFigure();
    }
    Gdiplus::SolidBrush background(fill);
    graphics.FillPath(&background, &path);
    if (border_width > 0.0f && border.GetA() != 0)
    {
        Gdiplus::Pen outline(border, border_width);
        graphics.DrawPath(&outline, &path);
    }
}

inline void DrawRevealHighlight(
    Gdiplus::Graphics& graphics,
    const Gdiplus::RectF& clip_rect,
    const Gdiplus::PointF& cursor,
    float radius,
    Gdiplus::Color center_color)
{
    // V12 deliberately has no reveal animation or glow.
    (void)graphics; (void)clip_rect; (void)cursor; (void)radius; (void)center_color;
}

inline bool CursorInControl(HWND control, Gdiplus::PointF* point) noexcept
{
    if (control == nullptr || point == nullptr) return false;
    POINT cursor{};
    if (!GetCursorPos(&cursor) || !ScreenToClient(control, &cursor)) return false;
    RECT client{};
    if (!GetClientRect(control, &client)) return false;
    *point = Gdiplus::PointF(
        static_cast<Gdiplus::REAL>(cursor.x),
        static_cast<Gdiplus::REAL>(cursor.y));
    return cursor.x >= -96 && cursor.y >= -96 &&
        cursor.x <= client.right + 96 && cursor.y <= client.bottom + 96;
}

inline void DrawElevatedPanel(
    Gdiplus::Graphics& graphics,
    const Gdiplus::RectF& rect,
    float radius,
    Gdiplus::Color fill,
    Gdiplus::Color border,
    bool accent_glow = false)
{
    (void)accent_glow;
    DrawRoundedPanel(graphics, rect, radius, fill, border, 1.0f);
}

inline void PaintWindowBackground(HDC dc, const RECT& bounds)
{
    if (!dc) return;
    HBRUSH brush = CreateSolidBrush(BgPrimary); FillRect(dc, &bounds, brush); DeleteObject(brush);
}

inline HBRUSH SharedBackgroundBrush() { static HBRUSH brush = CreateSolidBrush(BgPrimary); return brush; }
inline HBRUSH SharedSurfaceBrush() { static HBRUSH brush = CreateSolidBrush(BgSecondary); return brush; }
inline HBRUSH SharedEditBrush() { static HBRUSH brush = CreateSolidBrush(BgTertiary); return brush; }

inline void ApplyUxTheme(HWND control)
{
    if (control == nullptr) return;
    using SetWindowThemeFn = HRESULT (WINAPI*)(HWND, LPCWSTR, LPCWSTR);
    static HMODULE module = LoadLibraryW(L"uxtheme.dll");
    static auto set_window_theme = module == nullptr
        ? nullptr
        : reinterpret_cast<SetWindowThemeFn>(GetProcAddress(module, "SetWindowTheme"));
    if (set_window_theme != nullptr) (void)set_window_theme(control, L"DarkMode_Explorer", nullptr);
}

inline void RemoveLegacyClientEdge(HWND control)
{
    if (control == nullptr) return;
    const LONG_PTR ex_style = GetWindowLongPtrW(control, GWL_EXSTYLE);
    if ((ex_style & WS_EX_CLIENTEDGE) != 0)
    {
        SetWindowLongPtrW(control, GWL_EXSTYLE, ex_style & ~static_cast<LONG_PTR>(WS_EX_CLIENTEDGE));
        SetWindowPos(control, nullptr, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
}

inline void PrepareButton(HWND button)
{
    if (button == nullptr) return;
    ApplyUxTheme(button);
    const LONG_PTR style = GetWindowLongPtrW(button, GWL_STYLE);
    SetWindowLongPtrW(button, GWL_STYLE,
        (style & ~static_cast<LONG_PTR>(BS_TYPEMASK)) | BS_OWNERDRAW);
    InvalidateRect(button, nullptr, TRUE);
}

inline void PrepareEdit(HWND edit)
{
    RemoveLegacyClientEdge(edit);
    ApplyUxTheme(edit);
}

inline void PrepareListView(HWND list)
{
    if (list == nullptr) return;
    RemoveLegacyClientEdge(list);
    ApplyUxTheme(list);
    ListView_SetBkColor(list, BgSecondary);
    ListView_SetTextBkColor(list, BgSecondary);
    ListView_SetTextColor(list, TextPrimary);
    ListView_SetExtendedListViewStyleEx(list,
        LVS_EX_DOUBLEBUFFER | LVS_EX_FULLROWSELECT,
        LVS_EX_DOUBLEBUFFER | LVS_EX_FULLROWSELECT);
}

inline void PrepareControl(HWND control)
{
    if (control == nullptr) return;
    wchar_t class_name[64]{};
    GetClassNameW(control, class_name, static_cast<int>(std::size(class_name)));
    if (_wcsicmp(class_name, L"Button") == 0)
        PrepareButton(control);
    else if (_wcsicmp(class_name, L"Edit") == 0)
        PrepareEdit(control);
    else if (_wcsicmp(class_name, WC_LISTVIEWW) == 0)
        PrepareListView(control);
    else
        ApplyUxTheme(control);
}

inline BOOL CALLBACK PrepareChildCallback(HWND child, LPARAM)
{
    PrepareControl(child);
    return TRUE;
}

inline void PrepareWindowTree(HWND window)
{
    if (window != nullptr) EnumChildWindows(window, PrepareChildCallback, 0);
}

inline bool PaintOwnerDrawButton(const DRAWITEMSTRUCT* draw, ButtonTone tone = ButtonTone::Neutral)
{
    if (draw == nullptr || draw->CtlType != ODT_BUTTON || draw->hwndItem == nullptr) return false;
    // Owner draw receives the full client rectangle. Clear it first so the
    // anti-aliased rounded panel cannot leave the legacy white button corners.
    const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
    const bool disabled = (draw->itemState & ODS_DISABLED) != 0;
    const bool focused = (draw->itemState & ODS_FOCUS) != 0;
    const bool hot = (draw->itemState & ODS_HOTLIGHT) != 0;
    COLORREF fill = pressed ? BgActive : (hot ? BgHover : BgTertiary);
    COLORREF border = focused ? AccentHover : (hot ? BorderStrong : BorderDefault);
    COLORREF text = disabled ? TextDisabled : TextPrimary;
    if (tone == ButtonTone::Accent)
    {
        fill = pressed ? AccentActive : (hot ? AccentHover : Accent);
        border = pressed ? AccentActive : AccentHover;
        text = RGB(255, 255, 255);
    }
    else if (tone == ButtonTone::Danger)
    {
        fill = pressed ? RGB(92, 27, 40) : (hot ? RGB(75, 29, 40) : RGB(52, 24, 33));
        border = Danger;
    }

    HBRUSH clear_brush = CreateSolidBrush(BgPrimary);
    FillRect(draw->hDC, &draw->rcItem, clear_brush);
    DeleteObject(clear_brush);
    Gdiplus::Graphics graphics(draw->hDC);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    const Gdiplus::RectF rect(
        static_cast<Gdiplus::REAL>(draw->rcItem.left + 2),
        static_cast<Gdiplus::REAL>(draw->rcItem.top + 2),
        static_cast<Gdiplus::REAL>(std::max<LONG>(1, draw->rcItem.right - draw->rcItem.left - 4)),
        static_cast<Gdiplus::REAL>(std::max<LONG>(1, draw->rcItem.bottom - draw->rcItem.top - 4)));
    DrawElevatedPanel(
        graphics,
        rect,
        10.0f,
        GdiColor(fill, disabled ? 170 : 248),
        GdiColor(border),
        tone == ButtonTone::Accent && !disabled);

    // Fluent Reveal Highlight. GetCursorPos lets the native control participate
    // without a web event loop; the radial light is clipped to the button.
    Gdiplus::PointF cursor{};
    if (!disabled && CursorInControl(draw->hwndItem, &cursor))
    {
        const BYTE alpha = hot ? static_cast<BYTE>(72) : static_cast<BYTE>(42);
        DrawRevealHighlight(
            graphics,
            rect,
            cursor,
            76.0f,
            tone == ButtonTone::Danger
                ? GdiColor(Danger, alpha)
                : GdiColor(tone == ButtonTone::Accent ? AccentCyan : AccentHover, alpha));
    }

    wchar_t caption[256]{};
    GetWindowTextW(draw->hwndItem, caption, static_cast<int>(std::size(caption)));
    HGDIOBJ previous_font = nullptr;
    HFONT font = reinterpret_cast<HFONT>(SendMessageW(draw->hwndItem, WM_GETFONT, 0, 0));
    if (font != nullptr) previous_font = SelectObject(draw->hDC, font);
    SetBkMode(draw->hDC, TRANSPARENT);
    SetTextColor(draw->hDC, text);
    RECT text_rect = draw->rcItem;
    DrawTextW(draw->hDC, caption, -1, &text_rect,
        DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    if (previous_font != nullptr) SelectObject(draw->hDC, previous_font);
    return true;
}

inline LRESULT HandleListViewCustomDraw(LPNMLVCUSTOMDRAW custom_draw)
{
    if (custom_draw == nullptr) return CDRF_DODEFAULT;
    if (custom_draw->nmcd.dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
    if (custom_draw->nmcd.dwDrawStage == CDDS_ITEMPREPAINT)
    {
        const bool selected = (custom_draw->nmcd.uItemState & CDIS_SELECTED) != 0;
        const bool hot = (custom_draw->nmcd.uItemState & CDIS_HOT) != 0;
        custom_draw->clrText = TextPrimary;
        custom_draw->clrTextBk = selected ? AccentSubtle : (hot ? BgHover : BgSecondary);
    }
    return CDRF_DODEFAULT;
}

inline LRESULT CALLBACK WindowSkinSubclass(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param, UINT_PTR subclass_id, DWORD_PTR)
{
    switch (message)
    {
    case WM_DRAWITEM:
    {
        const LRESULT app_result = DefSubclassProc(window, message, w_param, l_param);
        if (app_result != 0) return app_result;
        if (PaintOwnerDrawButton(reinterpret_cast<const DRAWITEMSTRUCT*>(l_param), ButtonTone::Neutral)) return TRUE;
        return app_result;
    }
    case WM_ERASEBKGND:
    {
        RECT client{}; GetClientRect(window, &client);
        PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, TextSecondary);
        return reinterpret_cast<LRESULT>(SharedBackgroundBrush());
    }
    case WM_CTLCOLOREDIT:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, TextPrimary);
        SetBkColor(dc, BgTertiary);
        return reinterpret_cast<LRESULT>(SharedEditBrush());
    }
    case WM_CTLCOLORLISTBOX:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, TextPrimary);
        SetBkColor(dc, BgSecondary);
        return reinterpret_cast<LRESULT>(SharedSurfaceBrush());
    }
    case WM_NCDESTROY:
        RemoveWindowSubclass(window, WindowSkinSubclass, subclass_id);
        break;
    default:
        break;
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

inline void InstallWindowSkin(HWND window)
{
    if (window != nullptr) (void)SetWindowSubclass(window, WindowSkinSubclass, WindowSubclassId, 0);
}

inline HBRUSH CreateBackgroundBrush() { return CreateSolidBrush(BgPrimary); }
inline HBRUSH CreateSurfaceBrush() { return CreateSolidBrush(BgSecondary); }
inline HBRUSH CreateEditBrush() { return CreateSolidBrush(BgTertiary); }
} // namespace WebSkin

using ButtonTone = WebSkin::ButtonTone;

constexpr COLORREF kBgTop = WebSkin::BgPrimary;
constexpr COLORREF kBgBottom = WebSkin::BgSolid;
constexpr COLORREF kGlassBg = WebSkin::BgSecondary;
constexpr COLORREF kGlassCard = WebSkin::BgTertiary;
constexpr COLORREF kGlassBorder = WebSkin::BorderStrong;
inline COLORREF& kNeonCyan = WebSkin::AccentCyan;
inline COLORREF& kNeonPurple = WebSkin::AccentHover;
constexpr COLORREF kNeonPink = RGB(231, 132, 183);
constexpr COLORREF kTextWhite = WebSkin::TextPrimary;
constexpr COLORREF kTextSec = WebSkin::TextSecondary;
constexpr COLORREF kTextMuted = WebSkin::TextTertiary;
constexpr COLORREF kAccentGreen = RGB(93, 204, 146);
constexpr COLORREF kDanger = WebSkin::Danger;

enum class AppCategory : int { All = 0, Dev, Accessories, Files, System, Settings };

struct AppItem final
{
    const wchar_t* id;
    const wchar_t* name;
    const wchar_t* desc;
    const wchar_t* exe_path;
    AppCategory category;
    int icon_id;
};

inline constexpr std::array<AppItem, 22> kAllApps{{
    {L"browser", L"Navegador", L"Navegador Win32 in-process do CloudOS com WebView2", L"", AppCategory::Accessories, 1},
    {L"control", L"Central de Comandos", L"Mais de 100 acoes do CloudOS e do Windows em uma central pesquisavel", L"", AppCategory::System, 16},
    {L"workspaces", L"Visão de Trabalho", L"Gerenciar as 4 áreas, janelas, tiling e previews DWM", L"", AppCategory::System, 19},
    {L"projects", L"Projetos", L"Projetos persistentes no CloudOS Drive", L"", AppCategory::Dev, 2},
    {L"wsl", L"WSL / Kali", L"Terminal Linux pela distribuicao WSL configurada", L"wsl.exe", AppCategory::Dev, 4},
    {L"terminal", L"Terminal", L"Terminal nativo via ConPTY", L"cmd.exe", AppCategory::Dev, 3},
    {L"powershell", L"PowerShell", L"PowerShell em terminal ConPTY", L"powershell.exe", AppCategory::Dev, 4},
    {L"notepad", L"Bloco de Notas", L"Editor de texto nativo do CloudOS", L"", AppCategory::Accessories, 5},
    {L"drive", L"CloudOS Drive", L"Armazenamento persistente isolado do CloudOS", L"", AppCategory::Files, 6},
    {L"systemdrive", L"Disco do Sistema", L"Abrir o volume onde o Windows esta instalado", L"explorer.exe", AppCategory::Files, 6},
    {L"files", L"Arquivos", L"Arquivos Windows, CloudOS Drive e WSL", L"", AppCategory::Files, 7},
    {L"paint", L"Paint", L"Editor de imagens do Windows", L"mspaint.exe", AppCategory::Accessories, 8},
    {L"media", L"Midia", L"Abrir o player de midia do Windows", L"", AppCategory::Accessories, 9},
    {L"code", L"Editor de Codigo", L"Abrir VS Code quando disponivel", L"code.cmd", AppCategory::Dev, 10},
    {L"settings", L"Configuracoes", L"Configuracoes nativas do CloudOS", L"", AppCategory::Settings, 11},
    {L"calc", L"Calculadora", L"Calculadora nativa do CloudOS", L"", AppCategory::Accessories, 12},
    {L"sysmon", L"Monitor do Sistema", L"Telemetria nativa do CloudOS", L"", AppCategory::System, 13},
    {L"regedit", L"Registro", L"Editor do Registro do Windows", L"regedit.exe", AppCategory::System, 14},
    {L"snip", L"Captura de Tela", L"Ferramenta de Captura do Windows", L"SnippingTool.exe", AppCategory::Accessories, 15},
    {L"apps", L"Aplicativos", L"Catalogo de aplicativos Windows e CloudOS", L"", AppCategory::System, 16},
    {L"run", L"Executar", L"Executar comando ou aplicativo", L"", AppCategory::System, 17},
    {L"health", L"Saude do Sistema", L"Diagnostico do runtime, WSL e ambiente", L"", AppCategory::System, 18},
}};

struct TaskHit final { HWND window{}; RECT bounds{}; };

enum HotKeyId : int
{
    HotTerminal = 1, HotWslTerminal, HotFiles, HotApps, HotProcesses, HotRun,
    HotTiling, HotFloating, HotFocusNext, HotFocusPrevious, HotClose, HotMinimize,
    HotMaximize, HotSnapLeft, HotSnapRight, HotSnapUp, HotSnapDown, HotSearch, HotExit,
    HotWorkspace1 = 30, HotWorkspace2, HotWorkspace3, HotWorkspace4,
    HotMoveWorkspace1 = 40, HotMoveWorkspace2, HotMoveWorkspace3, HotMoveWorkspace4,
};

inline int Scale(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}
inline int Width(const RECT& r) noexcept { return static_cast<int>(std::max<LONG>(0, r.right - r.left)); }
inline int Height(const RECT& r) noexcept { return static_cast<int>(std::max<LONG>(0, r.bottom - r.top)); }
inline bool Contains(const RECT& r, POINT pt) noexcept
{
    return pt.x >= r.left && pt.x < r.right && pt.y >= r.top && pt.y < r.bottom;
}

inline void DarkWindow(HWND window, bool round = true)
{
    if (window == nullptr) return;
    const BOOL dark = TRUE;
    (void)DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, static_cast<DWORD>(sizeof(dark)));
    if (round)
    {
        const DWM_WINDOW_CORNER_PREFERENCE preference = DWMWCP_ROUND;
        (void)DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &preference, static_cast<DWORD>(sizeof(preference)));
    }
    const COLORREF border = WebSkin::BorderStrong;
    const COLORREF caption = WebSkin::BgSecondary;
    (void)DwmSetWindowAttribute(window, static_cast<DWMWINDOWATTRIBUTE>(34), &border, static_cast<DWORD>(sizeof(border)));
    (void)DwmSetWindowAttribute(window, static_cast<DWMWINDOWATTRIBUTE>(35), &caption, static_cast<DWORD>(sizeof(caption)));
    WebSkin::PrepareWindowTree(window);
    if (round) WebSkin::InstallWindowSkin(window);
}

inline void ApplyWebFlyoutMaterial(HWND window)
{
    if (window == nullptr) return;
    DarkWindow(window, true);
    const DWM_SYSTEMBACKDROP_TYPE transient_backdrop = DWMSBT_TRANSIENTWINDOW;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_SYSTEMBACKDROP_TYPE,
        &transient_backdrop,
        static_cast<DWORD>(sizeof(transient_backdrop)));
}

inline void ApplyWebWindowMaterial(HWND window)
{
    if (window == nullptr) return;
    DarkWindow(window, true);
    const DWM_SYSTEMBACKDROP_TYPE main_backdrop = DWMSBT_MAINWINDOW;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_SYSTEMBACKDROP_TYPE,
        &main_backdrop,
        static_cast<DWORD>(sizeof(main_backdrop)));
}
} // namespace CloudOS
