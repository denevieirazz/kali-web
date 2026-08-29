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
constexpr int kBottomBarHeight = 44;
constexpr UINT_PTR kReconcileTimer = 1;
constexpr UINT_PTR kMetricsTimer = 2;

// AETHER is the visual language of the native CloudOS shell, not a product rename.
constexpr COLORREF kBgTop = RGB(10, 14, 26);
constexpr COLORREF kBgBottom = RGB(6, 8, 16);
constexpr COLORREF kGlassBg = RGB(16, 24, 40);
constexpr COLORREF kGlassCard = RGB(22, 32, 54);
constexpr COLORREF kGlassBorder = RGB(45, 90, 140);
constexpr COLORREF kNeonCyan = RGB(56, 189, 248);
constexpr COLORREF kNeonPurple = RGB(168, 85, 247);
constexpr COLORREF kNeonPink = RGB(244, 114, 182);
constexpr COLORREF kTextWhite = RGB(255, 255, 255);
constexpr COLORREF kTextSec = RGB(180, 200, 230);
constexpr COLORREF kTextMuted = RGB(120, 145, 180);
constexpr COLORREF kAccentGreen = RGB(52, 211, 153);
constexpr COLORREF kDanger = RGB(239, 68, 68);

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

// Keep visible names honest: an item must describe what the launcher really opens.
inline constexpr std::array<AppItem, 18> kAllApps{{
    {L"browser", L"Navegador", L"Abrir o navegador padrao do Windows", L"", AppCategory::Accessories, 1},
    {L"projects", L"WSL / Kali", L"Terminal Linux pelo WSL", L"wsl.exe", AppCategory::Dev, 2},
    {L"terminal", L"Terminal", L"Terminal nativo via ConPTY", L"cmd.exe", AppCategory::Dev, 3},
    {L"powershell", L"PowerShell", L"PowerShell em terminal ConPTY", L"powershell.exe", AppCategory::Dev, 4},
    {L"notepad", L"Bloco de Notas", L"Editor de texto nativo do CloudOS", L"", AppCategory::Accessories, 5},
    {L"drive", L"Disco do Sistema", L"Abrir o volume onde o Windows esta instalado", L"explorer.exe", AppCategory::Files, 6},

    {L"files", L"Arquivos", L"Arquivos Windows + WSL no CloudOS", L"", AppCategory::Files, 7},
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
    return pt.x >= r.left && pt.x < r.right && pt.y >= r.top && pt.y < r.bottom;
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

} // namespace CloudOS
