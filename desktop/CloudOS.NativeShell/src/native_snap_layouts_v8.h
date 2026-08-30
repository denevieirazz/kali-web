#pragma once

#include <windows.h>
#include <dwmapi.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstddef>
#include <new>
#include <string>
#include <vector>

#include "native_theme.h"
#include "native_window_manager.h"

#pragma comment(lib, "dwmapi.lib")

namespace CloudOS
{
// Native Snap Layouts V8 deliberately stays in the CloudOS process. It detects
// a real maximize hit through WM_NCHITTEST/HTMAXBUTTON with SendMessageTimeout,
// then presents a WS_EX_NOACTIVATE flyout owned by the shell. No cross-process
// subclassing, hooks injected into applications or SetParent are used.
namespace SnapLayoutsV8
{
constexpr wchar_t kEngineClass[] = L"CloudOS.NativeShell.SnapLayoutsEngine.v8";
constexpr wchar_t kPopupClass[] = L"CloudOS.NativeShell.SnapLayouts.v8";
constexpr UINT_PTR kPollTimer = 0xC508u;
constexpr UINT kPollMilliseconds = 80u;
constexpr ULONGLONG kHoverDelayMilliseconds = 420u;
constexpr ULONGLONG kDismissDelayMilliseconds = 260u;

struct Choice final
{
    RECT preview{};
    RECT target{};
};

struct State final
{
    HINSTANCE instance{};
    HWND engine{};
    HWND popup{};
    HWND target{};
    HWND hover_target{};
    ULONGLONG hover_started{};
    ULONGLONG last_valid_hover{};
    int hovered_choice{-1};
    std::vector<Choice> choices;
};

inline State& GetState() noexcept
{
    static State state;
    return state;
}

inline int RectWidth(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.right - rect.left));
}

inline int RectHeight(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.bottom - rect.top));
}

inline bool HasClassPrefix(HWND window, const wchar_t* prefix) noexcept
{
    if (window == nullptr || prefix == nullptr) return false;
    wchar_t class_name[160]{};
    const int length = GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
    if (length <= 0) return false;
    const std::wstring value(class_name, static_cast<std::size_t>(length));
    const std::wstring expected(prefix);
    return value.size() >= expected.size() &&
        _wcsnicmp(value.c_str(), expected.c_str(), expected.size()) == 0;
}

inline bool IsCandidate(HWND window) noexcept
{
    if (window == nullptr || !IsWindow(window) || !IsWindowVisible(window) ||
        GetAncestor(window, GA_ROOT) != window)
    {
        return false;
    }
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & WS_DISABLED) != 0 || (style & WS_CAPTION) == 0 ||
        (ex_style & WS_EX_TOOLWINDOW) != 0)
    {
        return false;
    }
    if (HasClassPrefix(window, L"CloudOS.NativeShell.Taskbar") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.Start") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.QuickSettings") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.Notification") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.TaskPreview") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.SnapLayouts") ||
        HasClassPrefix(window, L"CloudOS.NativeShell.SnapAssist"))
    {
        return false;
    }
    return true;
}

inline bool HitMaxButton(HWND window, POINT screen_point) noexcept
{
    if (!IsCandidate(window)) return false;
    DWORD_PTR result = 0;
    const LPARAM packed = MAKELPARAM(
        static_cast<SHORT>(screen_point.x),
        static_cast<SHORT>(screen_point.y));
    if (SendMessageTimeoutW(
            window,
            WM_NCHITTEST,
            0,
            packed,
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            32,
            &result) == 0)
    {
        return false;
    }
    return static_cast<LRESULT>(result) == HTMAXBUTTON;
}

inline RECT WorkAreaFor(HWND window) noexcept
{
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) return info.rcWork;
    RECT fallback{};
    (void)SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
    return fallback;
}

inline RECT CellRect(const RECT& card, int column, int columns, int row, int rows, int gap) noexcept
{
    const int total_width = RectWidth(card) - gap * (columns - 1);
    const int total_height = RectHeight(card) - gap * (rows - 1);
    const int cell_width = std::max(1, total_width / std::max(1, columns));
    const int cell_height = std::max(1, total_height / std::max(1, rows));
    const int left = card.left + column * (cell_width + gap);
    const int top = card.top + row * (cell_height + gap);
    const int right = column == columns - 1 ? card.right : left + cell_width;
    const int bottom = row == rows - 1 ? card.bottom : top + cell_height;
    return RECT{left, top, right, bottom};
}

inline void AddChoice(State& state, const RECT& preview, const RECT& target)
{
    state.choices.push_back(Choice{preview, target});
}

inline std::vector<RECT> CardRects(HWND popup)
{
    RECT client{};
    GetClientRect(popup, &client);
    const UINT dpi = GetDpiForWindow(popup);
    const int margin = Scale(14, dpi);
    const int gap = Scale(10, dpi);
    const int title_height = Scale(48, dpi);
    const int card_width = std::max(1, (RectWidth(client) - margin * 2 - gap) / 2);
    const int available_height = std::max(1, RectHeight(client) - title_height - margin * 2 - gap);
    const int card_height = std::max(1, available_height / 2);
    const int left = margin;
    const int top = margin + title_height;
    return {
        RECT{left, top, left + card_width, top + card_height},
        RECT{left + card_width + gap, top, client.right - margin, top + card_height},
        RECT{left, top + card_height + gap, left + card_width, client.bottom - margin},
        RECT{left + card_width + gap, top + card_height + gap, client.right - margin, client.bottom - margin}};
}

inline void BuildChoices(HWND popup, HWND target)
{
    State& state = GetState();
    state.choices.clear();
    if (popup == nullptr || target == nullptr) return;
    const std::vector<RECT> cards = CardRects(popup);
    if (cards.size() != 4u) return;

    const UINT dpi = GetDpiForWindow(popup);
    const int gap = Scale(5, dpi);
    const RECT work = WorkAreaFor(target);
    const int width = RectWidth(work);
    const int height = RectHeight(work);
    const int half_w = width / 2;
    const int half_h = height / 2;
    const int third_w = width / 3;

    // Layout 1: equal halves.
    AddChoice(state, CellRect(cards[0], 0, 2, 0, 1, gap),
        RECT{work.left, work.top, work.left + half_w, work.bottom});
    AddChoice(state, CellRect(cards[0], 1, 2, 0, 1, gap),
        RECT{work.left + half_w, work.top, work.right, work.bottom});

    // Layout 2: equal thirds.
    AddChoice(state, CellRect(cards[1], 0, 3, 0, 1, gap),
        RECT{work.left, work.top, work.left + third_w, work.bottom});
    AddChoice(state, CellRect(cards[1], 1, 3, 0, 1, gap),
        RECT{work.left + third_w, work.top, work.right - third_w, work.bottom});
    AddChoice(state, CellRect(cards[1], 2, 3, 0, 1, gap),
        RECT{work.right - third_w, work.top, work.right, work.bottom});

    // Layout 3: two-thirds + one-third.
    const RECT two_thirds_preview = RECT{
        cards[2].left,
        cards[2].top,
        cards[2].left + (RectWidth(cards[2]) * 2) / 3 - gap / 2,
        cards[2].bottom};
    const RECT one_third_preview = RECT{
        two_thirds_preview.right + gap,
        cards[2].top,
        cards[2].right,
        cards[2].bottom};
    AddChoice(state, two_thirds_preview,
        RECT{work.left, work.top, work.left + (width * 2) / 3, work.bottom});
    AddChoice(state, one_third_preview,
        RECT{work.left + (width * 2) / 3, work.top, work.right, work.bottom});

    // Layout 4: quarters.
    AddChoice(state, CellRect(cards[3], 0, 2, 0, 2, gap),
        RECT{work.left, work.top, work.left + half_w, work.top + half_h});
    AddChoice(state, CellRect(cards[3], 1, 2, 0, 2, gap),
        RECT{work.left + half_w, work.top, work.right, work.top + half_h});
    AddChoice(state, CellRect(cards[3], 0, 2, 1, 2, gap),
        RECT{work.left, work.top + half_h, work.left + half_w, work.bottom});
    AddChoice(state, CellRect(cards[3], 1, 2, 1, 2, gap),
        RECT{work.left + half_w, work.top + half_h, work.right, work.bottom});
}

inline void Hide() noexcept
{
    State& state = GetState();
    if (state.popup != nullptr && IsWindow(state.popup)) ShowWindow(state.popup, SW_HIDE);
    state.hovered_choice = -1;
    state.target = nullptr;
}

inline bool EnsurePopup();

inline void ShowFor(HWND target)
{
    State& state = GetState();
    if (!IsCandidate(target) || !EnsurePopup()) return;
    state.target = target;
    state.hovered_choice = -1;

    const UINT dpi = GetDpiForWindow(target);
    const int width = Scale(420, dpi);
    const int height = Scale(252, dpi);
    RECT frame{};
    if (FAILED(DwmGetWindowAttribute(
            target,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &frame,
            sizeof(frame))))
    {
        GetWindowRect(target, &frame);
    }
    const RECT work = WorkAreaFor(target);
    int x = frame.right - width - Scale(10, dpi);
    int y = frame.top + Scale(36, dpi);
    x = std::clamp(x, work.left + Scale(8, dpi), std::max(work.left + Scale(8, dpi), work.right - width - Scale(8, dpi)));
    y = std::clamp(y, work.top + Scale(8, dpi), std::max(work.top + Scale(8, dpi), work.bottom - height - Scale(8, dpi)));

    SetWindowPos(
        state.popup,
        HWND_TOPMOST,
        x,
        y,
        width,
        height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    ApplyWebFlyoutMaterial(state.popup);
    BuildChoices(state.popup, target);
    InvalidateRect(state.popup, nullptr, FALSE);
}

inline void ApplyChoice(std::size_t index)
{
    State& state = GetState();
    if (state.target == nullptr || !IsWindow(state.target) || index >= state.choices.size())
    {
        Hide();
        return;
    }
    const HWND target = state.target;
    const RECT destination = state.choices[index].target;
    if (IsZoomed(target)) ShowWindow(target, SW_RESTORE);
    const BOOL moved = SetWindowPos(
        target,
        HWND_TOP,
        destination.left,
        destination.top,
        std::max(1, RectWidth(destination)),
        std::max(1, RectHeight(destination)),
        SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
    if (moved != FALSE)
    {
        if (CloudOSNativeWindowManager* manager = NativeSnapAssist::ActiveWindowManager(); manager != nullptr)
        {
            manager->SetWindowFloating(target, true);
            manager->Reconcile();
            manager->FocusWindow(target);
        }
        else
        {
            SetForegroundWindow(target);
        }
    }
    Hide();
}

inline void PaintPopup(HWND window)
{
    State& state = GetState();
    PAINTSTRUCT paint{};
    HDC screen = BeginPaint(window, &paint);
    if (screen == nullptr) return;
    RECT client{};
    GetClientRect(window, &client);
    const int width = std::max(1, RectWidth(client));
    const int height = std::max(1, RectHeight(client));
    HDC memory = CreateCompatibleDC(screen);
    HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory, bitmap);

    WebSkin::PaintWindowBackground(memory, client);
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(window);

    Gdiplus::Font title_font(
        L"Segoe UI Variable Display",
        static_cast<Gdiplus::REAL>(Scale(16, dpi)),
        Gdiplus::FontStyleBold,
        Gdiplus::UnitPixel);
    Gdiplus::Font meta_font(
        L"Segoe UI Variable Text",
        static_cast<Gdiplus::REAL>(Scale(9, dpi)),
        Gdiplus::FontStyleRegular,
        Gdiplus::UnitPixel);
    Gdiplus::SolidBrush title(WebSkin::GdiColor(WebSkin::TextPrimary));
    Gdiplus::SolidBrush meta(WebSkin::GdiColor(WebSkin::TextTertiary));
    graphics.DrawString(
        L"Organizar janela",
        -1,
        &title_font,
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(Scale(16, dpi)), static_cast<Gdiplus::REAL>(Scale(11, dpi))),
        &title);
    graphics.DrawString(
        L"Escolha uma zona · sem sair do aplicativo",
        -1,
        &meta_font,
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(Scale(17, dpi)), static_cast<Gdiplus::REAL>(Scale(32, dpi))),
        &meta);

    const std::vector<RECT> cards = CardRects(window);
    for (const RECT& card : cards)
    {
        WebSkin::DrawElevatedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(card.left),
                static_cast<Gdiplus::REAL>(card.top),
                static_cast<Gdiplus::REAL>(std::max(1, RectWidth(card))),
                static_cast<Gdiplus::REAL>(std::max(1, RectHeight(card)))),
            static_cast<Gdiplus::REAL>(Scale(12, dpi)),
            WebSkin::GdiColor(WebSkin::BgSecondary, 235),
            WebSkin::GdiColor(WebSkin::BorderDefault, 210));
    }

    for (std::size_t index = 0; index < state.choices.size(); ++index)
    {
        const RECT& rect = state.choices[index].preview;
        const bool hot = state.hovered_choice == static_cast<int>(index);
        WebSkin::DrawRoundedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(rect.left),
                static_cast<Gdiplus::REAL>(rect.top),
                static_cast<Gdiplus::REAL>(std::max(1, RectWidth(rect))),
                static_cast<Gdiplus::REAL>(std::max(1, RectHeight(rect)))),
            static_cast<Gdiplus::REAL>(Scale(7, dpi)),
            WebSkin::GdiColor(hot ? WebSkin::AccentSubtle : WebSkin::BgElevated, hot ? 255 : 230),
            WebSkin::GdiColor(hot ? WebSkin::AccentCyan : WebSkin::BorderStrong, hot ? 245 : 190),
            hot ? 1.5f : 1.0f);
        if (hot)
        {
            Gdiplus::PointF cursor(
                static_cast<Gdiplus::REAL>((rect.left + rect.right) / 2),
                static_cast<Gdiplus::REAL>((rect.top + rect.bottom) / 2));
            WebSkin::DrawRevealHighlight(
                graphics,
                Gdiplus::RectF(
                    static_cast<Gdiplus::REAL>(rect.left),
                    static_cast<Gdiplus::REAL>(rect.top),
                    static_cast<Gdiplus::REAL>(std::max(1, RectWidth(rect))),
                    static_cast<Gdiplus::REAL>(std::max(1, RectHeight(rect)))),
                cursor,
                static_cast<float>(Scale(70, dpi)),
                WebSkin::GdiColor(WebSkin::AccentCyan, 58));
        }
    }

    BitBlt(screen, 0, 0, width, height, memory, 0, 0, SRCCOPY);
    SelectObject(memory, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory);
    EndPaint(window, &paint);
}

inline void Poll()
{
    State& state = GetState();
    POINT cursor{};
    if (!GetCursorPos(&cursor)) return;
    const ULONGLONG now = GetTickCount64();

    if (state.popup != nullptr && IsWindowVisible(state.popup))
    {
        RECT popup_bounds{};
        GetWindowRect(state.popup, &popup_bounds);
        if (PtInRect(&popup_bounds, cursor))
        {
            state.last_valid_hover = now;
            return;
        }
    }

    HWND candidate = WindowFromPoint(cursor);
    candidate = candidate != nullptr ? GetAncestor(candidate, GA_ROOT) : nullptr;
    if (candidate != nullptr && HitMaxButton(candidate, cursor))
    {
        state.last_valid_hover = now;
        if (state.hover_target != candidate)
        {
            state.hover_target = candidate;
            state.hover_started = now;
        }
        else if (now - state.hover_started >= kHoverDelayMilliseconds &&
                 (state.popup == nullptr || !IsWindowVisible(state.popup) || state.target != candidate))
        {
            ShowFor(candidate);
        }
        return;
    }

    state.hover_target = nullptr;
    state.hover_started = 0;
    if (state.popup != nullptr && IsWindowVisible(state.popup) &&
        now - state.last_valid_hover >= kDismissDelayMilliseconds)
    {
        Hide();
    }
}

inline LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    State& state = GetState();
    if (window == state.engine)
    {
        if (message == WM_TIMER && w_param == kPollTimer)
        {
            Poll();
            return 0;
        }
        return DefWindowProcW(window, message, w_param, l_param);
    }

    switch (message)
    {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_NCHITTEST:
        return HTCLIENT;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
        PaintPopup(window);
        return 0;
    case WM_MOUSEMOVE:
    {
        TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window, 0};
        (void)TrackMouseEvent(&tracking);
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        int hovered = -1;
        for (std::size_t index = 0; index < state.choices.size(); ++index)
        {
            if (PtInRect(&state.choices[index].preview, point))
            {
                hovered = static_cast<int>(index);
                break;
            }
        }
        if (hovered != state.hovered_choice)
        {
            state.hovered_choice = hovered;
            InvalidateRect(window, nullptr, FALSE);
        }
        state.last_valid_hover = GetTickCount64();
        SetCursor(LoadCursorW(nullptr, hovered >= 0 ? IDC_HAND : IDC_ARROW));
        return 0;
    }
    case WM_MOUSELEAVE:
        state.hovered_choice = -1;
        InvalidateRect(window, nullptr, FALSE);
        return 0;
    case WM_LBUTTONUP:
        if (state.hovered_choice >= 0)
        {
            ApplyChoice(static_cast<std::size_t>(state.hovered_choice));
        }
        return 0;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE) Hide();
        return 0;
    default:
        return DefWindowProcW(window, message, w_param, l_param);
    }
}

inline bool EnsurePopup()
{
    State& state = GetState();
    if (state.popup != nullptr && IsWindow(state.popup)) return true;
    state.popup = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
        kPopupClass,
        L"Snap Layouts - CloudOS",
        WS_POPUP | WS_CLIPCHILDREN,
        0, 0, 1, 1,
        nullptr, nullptr, state.instance, nullptr);
    return state.popup != nullptr;
}

inline bool Initialize() noexcept
{
    State& state = GetState();
    if (state.engine != nullptr && IsWindow(state.engine)) return true;
    state.instance = GetModuleHandleW(nullptr);
    if (state.instance == nullptr) return false;

    WNDCLASSEXW engine_class{};
    engine_class.cbSize = sizeof(engine_class);
    engine_class.lpfnWndProc = WindowProcedure;
    engine_class.hInstance = state.instance;
    engine_class.lpszClassName = kEngineClass;
    if (RegisterClassExW(&engine_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    WNDCLASSEXW popup_class{};
    popup_class.cbSize = sizeof(popup_class);
    popup_class.style = CS_HREDRAW | CS_VREDRAW;
    popup_class.lpfnWndProc = WindowProcedure;
    popup_class.hInstance = state.instance;
    popup_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    popup_class.hbrBackground = nullptr;
    popup_class.lpszClassName = kPopupClass;
    if (RegisterClassExW(&popup_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    state.engine = CreateWindowExW(
        0,
        kEngineClass,
        L"",
        0,
        0, 0, 0, 0,
        HWND_MESSAGE,
        nullptr,
        state.instance,
        nullptr);
    if (state.engine == nullptr) return false;
    return SetTimer(state.engine, kPollTimer, kPollMilliseconds, nullptr) != 0;
}

inline void Shutdown() noexcept
{
    State& state = GetState();
    if (state.engine != nullptr && IsWindow(state.engine))
    {
        KillTimer(state.engine, kPollTimer);
        DestroyWindow(state.engine);
    }
    if (state.popup != nullptr && IsWindow(state.popup)) DestroyWindow(state.popup);
    state.engine = nullptr;
    state.popup = nullptr;
    state.target = nullptr;
    state.hover_target = nullptr;
    state.choices.clear();
}

class Bootstrap final
{
public:
    Bootstrap() noexcept { (void)Initialize(); }
    ~Bootstrap() { Shutdown(); }
    Bootstrap(const Bootstrap&) = delete;
    Bootstrap& operator=(const Bootstrap&) = delete;
};

inline Bootstrap bootstrap;
} // namespace SnapLayoutsV8
} // namespace CloudOS
