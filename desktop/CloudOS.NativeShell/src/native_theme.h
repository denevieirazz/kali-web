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
#include <string>
#include <string_view>

namespace CloudOS
{
constexpr int kBottomBarHeight = 48;
constexpr UINT_PTR kReconcileTimer = 1;
constexpr UINT_PTR kMetricsTimer = 2;

// Native mirror of frontend/src/index.css.  The Win32 shell keeps the native
// runtime/WindowManager, but the visual language comes from the old web UI.
namespace WebSkin
{
constexpr COLORREF BgSolid = RGB(10, 10, 15);       // #0a0a0f
constexpr COLORREF BgPrimary = RGB(17, 17, 24);     // #111118
constexpr COLORREF BgSecondary = RGB(26, 26, 36);   // #1a1a24
constexpr COLORREF BgTertiary = RGB(34, 34, 46);    // #22222e
constexpr COLORREF BgElevated = RGB(42, 42, 56);    // #2a2a38
constexpr COLORREF BgHover = RGB(34, 34, 45);
constexpr COLORREF BgActive = RGB(40, 40, 53);
constexpr COLORREF Accent = RGB(99, 102, 241);      // #6366f1
constexpr COLORREF AccentHover = RGB(129, 140, 248);// #818cf8
constexpr COLORREF AccentActive = RGB(79, 70, 229); // #4f46e5
constexpr COLORREF AccentSubtle = RGB(31, 31, 66);
constexpr COLORREF TextPrimary = RGB(240, 240, 245); // #f0f0f5
constexpr COLORREF TextSecondary = RGB(160, 160, 184);// #a0a0b8
constexpr COLORREF TextTertiary = RGB(107, 107, 130); // #6b6b82
constexpr COLORREF TextDisabled = RGB(69, 69, 90);
constexpr COLORREF BorderDefault = RGB(43, 43, 56);
constexpr COLORREF BorderSubtle = RGB(31, 31, 42);
constexpr COLORREF BorderStrong = RGB(55, 55, 70);
constexpr COLORREF Danger = RGB(219, 99, 106);
constexpr int RadiusSmall = 4;
constexpr int RadiusMedium = 8;
constexpr int RadiusLarge = 12;
constexpr int RadiusXL = 16;

inline Gdiplus::Color GdiColor(COLORREF color, BYTE alpha = 255) noexcept
{
    return Gdiplus::Color(
        alpha,
        GetRValue(color),
        GetGValue(color),
        GetBValue(color));
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
    {
        path.AddRectangle(rect);
    }
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
} // namespace WebSkin

// Compatibility names used by the existing native surfaces.  Mapping them to
// the web palette immediately pulls Taskbar/Desktop/other GDI+ surfaces toward
// the same visual identity without touching their behavior.
constexpr COLORREF kBgTop = WebSkin::BgPrimary;
constexpr COLORREF kBgBottom = WebSkin::BgSolid;
constexpr COLORREF kGlassBg = WebSkin::BgSecondary;
constexpr COLORREF kGlassCard = WebSkin::BgTertiary;
constexpr COLORREF kGlassBorder = WebSkin::BorderStrong;
constexpr COLORREF kNeonCyan = WebSkin::Accent;
constexpr COLORREF kNeonPurple = WebSkin::AccentHover;
constexpr COLORREF kNeonPink = RGB(213, 151, 171);
constexpr COLORREF kTextWhite = WebSkin::TextPrimary;
constexpr COLORREF kTextSec = WebSkin::TextSecondary;
constexpr COLORREF kTextMuted = WebSkin::TextTertiary;
constexpr COLORREF kAccentGreen = RGB(102, 187, 141);
constexpr COLORREF kDanger = WebSkin::Danger;

enum class AppCategory : int
{
    All = 0,
    Dev,
    Accessories,
    Files,
    System,
    Settings,
};

struct AppItem final
{
    const wchar_t* id;
    const wchar_t* name;
    const wchar_t* desc;
    const wchar_t* exe_path;
    AppCategory category;
    int icon_id;
};

// The catalog describes what each item actually launches.
inline constexpr std::array<AppItem, 21> kAllApps{{
    {L"browser", L"Navegador", L"Navegador Win32 in-process do CloudOS com WebView2", L"", AppCategory::Accessories, 1},
    {L"control", L"Central de Comandos", L"Mais de 100 acoes do CloudOS e do Windows em uma central pesquisavel", L"", AppCategory::System, 16},
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

struct TaskHit final
{
    HWND window{};
    RECT bounds{};
};

enum HotKeyId : int
{
    HotTerminal = 1,
    HotWslTerminal,
    HotFiles,
    HotApps,
    HotProcesses,
    HotRun,
    HotTiling,
    HotFloating,
    HotFocusNext,
    HotFocusPrevious,
    HotClose,
    HotMinimize,
    HotMaximize,
    HotSnapLeft,
    HotSnapRight,
    HotSnapUp,
    HotSnapDown,
    HotSearch,
    HotExit,
    HotWorkspace1 = 30,
    HotWorkspace2,
    HotWorkspace3,
    HotWorkspace4,
    HotMoveWorkspace1 = 40,
    HotMoveWorkspace2,
    HotMoveWorkspace3,
    HotMoveWorkspace4,
};

inline int Scale(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

inline int Width(const RECT& r) noexcept
{
    return static_cast<int>(std::max<LONG>(0, r.right - r.left));
}

inline int Height(const RECT& r) noexcept
{
    return static_cast<int>(std::max<LONG>(0, r.bottom - r.top));
}

inline bool Contains(const RECT& r, POINT pt) noexcept
{
    return pt.x >= r.left && pt.x < r.right &&
        pt.y >= r.top && pt.y < r.bottom;
}

inline void DarkWindow(HWND window, bool round = true)
{
    if (window == nullptr)
    {
        return;
    }

    const BOOL dark = TRUE;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_USE_IMMERSIVE_DARK_MODE,
        &dark,
        static_cast<DWORD>(sizeof(dark)));

    if (round)
    {
        const DWM_WINDOW_CORNER_PREFERENCE preference = DWMWCP_ROUND;
        (void)DwmSetWindowAttribute(
            window,
            DWMWA_WINDOW_CORNER_PREFERENCE,
            &preference,
            static_cast<DWORD>(sizeof(preference)));
    }
}

inline void ApplyWebFlyoutMaterial(HWND window)
{
    if (window == nullptr)
    {
        return;
    }

    DarkWindow(window, true);

    // Windows 11: DWMWA_BORDER_COLOR (34) and DWMWA_SYSTEMBACKDROP_TYPE (38).
    // Numeric attributes keep the code buildable with older Windows 10 SDK
    // headers while failing harmlessly on unsupported Windows builds.
    const COLORREF border = WebSkin::BorderStrong;
    (void)DwmSetWindowAttribute(
        window,
        static_cast<DWMWINDOWATTRIBUTE>(34),
        &border,
        static_cast<DWORD>(sizeof(border)));

    const int transient_backdrop = 3; // DWMSBT_TRANSIENTWINDOW / Acrylic-like.
    (void)DwmSetWindowAttribute(
        window,
        static_cast<DWMWINDOWATTRIBUTE>(38),
        &transient_backdrop,
        static_cast<DWORD>(sizeof(transient_backdrop)));
}
} // namespace CloudOS
