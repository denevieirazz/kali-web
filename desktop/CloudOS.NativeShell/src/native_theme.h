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
constexpr COLORREF BgSolid = RGB(5, 7, 12);
constexpr COLORREF BgPrimary = RGB(9, 13, 21);
constexpr COLORREF BgSecondary = RGB(14, 20, 31);
constexpr COLORREF BgTertiary = RGB(22, 29, 44);
constexpr COLORREF BgElevated = RGB(30, 39, 57);
constexpr COLORREF BgHover = RGB(31, 41, 59);
constexpr COLORREF BgActive = RGB(39, 50, 71);
constexpr COLORREF Accent = RGB(124, 92, 255);
constexpr COLORREF AccentHover = RGB(154, 126, 255);
constexpr COLORREF AccentActive = RGB(96, 68, 225);
constexpr COLORREF AccentSubtle = RGB(35, 31, 78);
constexpr COLORREF AccentCyan = RGB(77, 208, 225);
constexpr COLORREF TextPrimary = RGB(245, 247, 252);
constexpr COLORREF TextSecondary = RGB(167, 177, 199);
constexpr COLORREF TextTertiary = RGB(111, 123, 148);
constexpr COLORREF TextDisabled = RGB(69, 79, 100);
constexpr COLORREF BorderDefault = RGB(43, 53, 72);
constexpr COLORREF BorderSubtle = RGB(27, 35, 50);
constexpr COLORREF BorderStrong = RGB(59, 70, 94);
constexpr COLORREF Danger = RGB(235, 92, 108);
constexpr int RadiusSmall = 6;
constexpr int RadiusMedium = 10;
constexpr int RadiusLarge = 14;
constexpr int RadiusXL = 20;
constexpr UINT MotionFrameMilliseconds = 8; // target cadence; compositor decides final refresh cadence.
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
    if (clip_rect.Width <= 0.0f || clip_rect.Height <= 0.0f || radius <= 1.0f) return;

    const float reach = radius * 0.55f;
    if (cursor.X < clip_rect.X - reach || cursor.X > clip_rect.GetRight() + reach ||
        cursor.Y < clip_rect.Y - reach || cursor.Y > clip_rect.GetBottom() + reach)
    {
        return;
    }

    const Gdiplus::GraphicsState state = graphics.Save();
    graphics.SetClip(clip_rect);

    Gdiplus::GraphicsPath halo_path;
    const Gdiplus::RectF halo(
        cursor.X - radius,
        cursor.Y - radius,
        radius * 2.0f,
        radius * 2.0f);
    halo_path.AddEllipse(halo);
    Gdiplus::PathGradientBrush halo_brush(&halo_path);
    halo_brush.SetCenterPoint(cursor);
    halo_brush.SetCenterColor(center_color);
    Gdiplus::Color edge_color(0, center_color.GetR(), center_color.GetG(), center_color.GetB());
    INT surround_count = 1;
    halo_brush.SetSurroundColors(&edge_color, &surround_count);
    graphics.FillEllipse(&halo_brush, halo);
    graphics.Restore(state);
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
    if (rect.Width <= 0.0f || rect.Height <= 0.0f) return;
    Gdiplus::RectF shadow = rect;
    shadow.Y += 4.0f;
    DrawRoundedPanel(
        graphics,
        shadow,
        radius,
        Gdiplus::Color(86, 0, 0, 0),
        Gdiplus::Color(0, 0, 0, 0),
        0.0f);
    if (accent_glow)
    {
        Gdiplus::RectF glow = rect;
        glow.X -= 2.0f;
        glow.Y -= 2.0f;
        glow.Width += 4.0f;
        glow.Height += 4.0f;
        DrawRoundedPanel(
            graphics,
            glow,
            radius + 2.0f,
            Gdiplus::Color(18, 124, 92, 255),
            Gdiplus::Color(46, 154, 126, 255),
            1.0f);
    }
    DrawRoundedPanel(graphics, rect, radius, fill, border, 1.0f);

    // Specular light edge: a small bright edge at the top makes elevation read
    // even on near-black monitors without turning every border neon.
    Gdiplus::Pen highlight(Gdiplus::Color(42, 255, 255, 255), 1.0f);
    const float inset = std::max(8.0f, radius * 0.65f);
    graphics.DrawLine(
        &highlight,
        rect.X + inset,
        rect.Y + 1.0f,
        rect.GetRight() - inset,
        rect.Y + 1.0f);
}

inline void PaintWindowBackground(HDC dc, const RECT& bounds)
{
    if (dc == nullptr || bounds.right <= bounds.left || bounds.bottom <= bounds.top) return;
    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    const Gdiplus::REAL left = static_cast<Gdiplus::REAL>(bounds.left);
    const Gdiplus::REAL top = static_cast<Gdiplus::REAL>(bounds.top);
    const Gdiplus::REAL width = static_cast<Gdiplus::REAL>(bounds.right - bounds.left);
    const Gdiplus::REAL height = static_cast<Gdiplus::REAL>(bounds.bottom - bounds.top);
    Gdiplus::LinearGradientBrush gradient(
        Gdiplus::PointF(left, top),
        Gdiplus::PointF(left + width, top + height),
        GdiColor(BgPrimary), GdiColor(BgSolid));
    graphics.FillRectangle(&gradient, Gdiplus::RectF(left, top, width, height));

    // Ambient light gives native flyouts/windows depth without depending on a
    // web compositor. Alpha remains deliberately subtle so text contrast wins.
    Gdiplus::SolidBrush indigo_glow(Gdiplus::Color(24, 124, 92, 255));
    graphics.FillEllipse(
        &indigo_glow,
        left + width * 0.60f,
        top - height * 0.24f,
        width * 0.62f,
        height * 0.58f);
    Gdiplus::SolidBrush cyan_glow(Gdiplus::Color(12, 77, 208, 225));
    graphics.FillEllipse(
        &cyan_glow,
        left - width * 0.22f,
        top + height * 0.58f,
        width * 0.52f,
        height * 0.48f);
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
constexpr COLORREF kNeonCyan = WebSkin::AccentCyan;
constexpr COLORREF kNeonPurple = WebSkin::AccentHover;
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
