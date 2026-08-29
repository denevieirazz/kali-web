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
#include <vector>

namespace CloudOS
{
constexpr int kBottomBarHeight = 44;
constexpr UINT_PTR kReconcileTimer = 1;
constexpr UINT_PTR kMetricsTimer = 2;

// AETHER OS Cyberpunk Glass Palette
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

// 18 Grid Apps matching Aether OS layout
const std::vector<AppItem> kAllApps = {
    {L"browser", L"Nebula Browser", L"Navegador Web", L"msedge.exe", AppCategory::Dev, 1},
    {L"projects", L"Orion Projects", L"Ambiente Linux WSL2", L"wsl.exe", AppCategory::Dev, 2},
    {L"terminal", L"Comms Hub", L"Terminal ConPTY", L"cmd.exe", AppCategory::Dev, 3},
    {L"powershell", L"Quantum Shell", L"PowerShell Terminal", L"powershell.exe", AppCategory::Dev, 4},
    {L"notepad", L"Quantum Mail", L"Editor de Texto", L"notepad.exe", AppCategory::Accessories, 5},
    {L"drive", L"Synapse Drive", L"Disco C: do Sistema", L"explorer.exe", AppCategory::Files, 6},

    {L"files", L"Synapse Files", L"Explorador de Arquivos", L"explorer.exe", AppCategory::Files, 7},
    {L"paint", L"Art Studio", L"Editor de Imagens", L"mspaint.exe", AppCategory::Accessories, 8},
    {L"media", L"Media Player", L"Reprodutor de Mídia", L"wmplayer.exe", AppCategory::Accessories, 9},
    {L"code", L"Code Editor", L"Editor de Código", L"notepad.exe", AppCategory::Dev, 10},
    {L"settings", L"Settings", L"Configurações do Sistema", L"control.exe", AppCategory::Settings, 11},
    {L"calc", L"Calculadora", L"Calculadora Rápida", L"calc.exe", AppCategory::Accessories, 12},

    {L"sysmon", L"Sys Monitor", L"Monitor de Recursos", L"taskmgr.exe", AppCategory::System, 13},
    {L"regedit", L"Registro", L"Editor do Registro", L"regedit.exe", AppCategory::System, 14},
    {L"snip", L"Screen Snip", L"Captura de Tela", L"SnippingTool.exe", AppCategory::Accessories, 15},
    {L"apps", L"App Catalog", L"Catálogo de Apps", L"", AppCategory::System, 16},
    {L"run", L"Quick Run", L"Executar Comando", L"", AppCategory::System, 17},
    {L"more", L"More Apps", L"Todos os Aplicativos", L"", AppCategory::System, 18},
};

struct TaskHit final { HWND window{}; RECT bounds{}; };

enum HotKeyId : int
{
    HotTerminal = 1,
    HotWslTerminal,
    HotFiles,
    HotApps,
    HotProcesses,
    HotRun,
    HotFocusNext,
    HotClose,
    HotMinimize,
    HotExit,
    HotWorkspace1 = 30,
    HotWorkspace2,
    HotWorkspace3,
    HotWorkspace4,
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
    if (window == nullptr) return;
    BOOL dark = TRUE;
    (void)DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
    if (round)
    {
        DWM_WINDOW_CORNER_PREFERENCE preference = DWMWCP_ROUND;
        (void)DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &preference, sizeof(preference));
    }
}

} // namespace CloudOS

