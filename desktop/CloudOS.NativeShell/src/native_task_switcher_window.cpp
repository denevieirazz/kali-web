#include "native_task_switcher_window.h"

#include "native_theme.h"

#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <string>

#pragma comment(lib, "dwmapi.lib")

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kTaskSwitcherClass[] = L"CloudOS.NativeShell.TaskSwitcher.v2";
constexpr UINT_PTR kCommitTimer = 9201;

void DrawCenteredText(
    Graphics& graphics,
    const std::wstring& text,
    const Font& font,
    const RectF& rectangle,
    const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentCenter);
    format.SetLineAlignment(StringAlignmentCenter);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    graphics.DrawString(text.c_str(), -1, &font, rectangle, &format, &brush);
}
}

CloudOSNativeTaskSwitcherWindow::~CloudOSNativeTaskSwitcherWindow()
{
    Destroy();
}

bool CloudOSNativeTaskSwitcherWindow::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    instance_ = instance;
    window_manager_ = window_manager;

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeTaskSwitcherWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kTaskSwitcherClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kTaskSwitcherClass,
        L"Alternar janelas - CloudOS",
        WS_POPUP | WS_BORDER | WS_CLIPCHILDREN,
        0, 0, 900, 520,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    DarkWindow(window_);
    return true;
}

void CloudOSNativeTaskSwitcherWindow::Destroy()
{
    ClearThumbnails();
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kCommitTimer);
        DestroyWindow(window_);
    }
    window_ = nullptr;
    windows_.clear();
    cells_.clear();
}

void CloudOSNativeTaskSwitcherWindow::ClearThumbnails() noexcept
{
    for (HTHUMBNAIL thumbnail : thumbnails_)
    {
        if (thumbnail != nullptr)
        {
            (void)DwmUnregisterThumbnail(thumbnail);
        }
    }
    thumbnails_.clear();
}

void CloudOSNativeTaskSwitcherWindow::Rebuild()
{
    ClearThumbnails();
    cells_.clear();
    windows_.clear();

    if (window_manager_ == nullptr)
    {
        return;
    }

    windows_ = window_manager_->CurrentWorkspaceWindows();
    windows_.erase(
        std::remove_if(
            windows_.begin(),
            windows_.end(),
            [](const CloudOSManagedWindow& item)
            {
                return item.hwnd == nullptr ||
                    !IsWindow(item.hwnd) ||
                    !IsWindowVisible(item.hwnd);
            }),
        windows_.end());
    if (windows_.size() > 8)
    {
        windows_.resize(8);
    }

    const HWND active = window_manager_->ActiveManagedWindow();
    selected_ = 0;
    for (std::size_t index = 0; index < windows_.size(); ++index)
    {
        if (windows_[index].hwnd == active)
        {
            selected_ = static_cast<int>(index);
            break;
        }
    }
}

void CloudOSNativeTaskSwitcherWindow::LayoutThumbnails()
{
    ClearThumbnails();
    cells_.clear();
    if (window_ == nullptr || windows_.empty())
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    const int margin = Scale(22, dpi);
    const int gap = Scale(14, dpi);
    const int columns = std::min(4, static_cast<int>(windows_.size()));
    const int rows = static_cast<int>((windows_.size() + static_cast<std::size_t>(columns) - 1u) /
        static_cast<std::size_t>(columns));
    const int cell_width = std::max(140, (width - margin * 2 - gap * (columns - 1)) / columns);
    const int cell_height = std::max(120, (height - margin * 2 - gap * (rows - 1)) / rows);
    const int caption_height = Scale(34, dpi);

    thumbnails_.reserve(windows_.size());
    cells_.reserve(windows_.size());

    for (std::size_t index = 0; index < windows_.size(); ++index)
    {
        const int column = static_cast<int>(index % static_cast<std::size_t>(columns));
        const int row = static_cast<int>(index / static_cast<std::size_t>(columns));
        RECT cell{
            margin + column * (cell_width + gap),
            margin + row * (cell_height + gap),
            margin + column * (cell_width + gap) + cell_width,
            margin + row * (cell_height + gap) + cell_height,
        };
        cells_.push_back(cell);

        HTHUMBNAIL thumbnail = nullptr;
        if (FAILED(DwmRegisterThumbnail(window_, windows_[index].hwnd, &thumbnail)))
        {
            thumbnails_.push_back(nullptr);
            continue;
        }

        SIZE source{};
        (void)DwmQueryThumbnailSourceSize(thumbnail, &source);
        const int available_width = std::max(1, cell_width - Scale(16, dpi));
        const int available_height = std::max(1, cell_height - caption_height - Scale(14, dpi));
        int preview_width = available_width;
        int preview_height = available_height;
        if (source.cx > 0 && source.cy > 0)
        {
            const double scale = std::min(
                static_cast<double>(available_width) / static_cast<double>(source.cx),
                static_cast<double>(available_height) / static_cast<double>(source.cy));
            preview_width = std::max(1, static_cast<int>(source.cx * scale));
            preview_height = std::max(1, static_cast<int>(source.cy * scale));
        }

        const int preview_x = cell.left + (cell_width - preview_width) / 2;
        const int preview_y = cell.top + Scale(8, dpi) + (available_height - preview_height) / 2;

        DWM_THUMBNAIL_PROPERTIES properties{};
        properties.dwFlags =
            DWM_TNP_RECTDESTINATION |
            DWM_TNP_VISIBLE |
            DWM_TNP_OPACITY |
            DWM_TNP_SOURCECLIENTAREAONLY;
        properties.rcDestination = RECT{
            preview_x,
            preview_y,
            preview_x + preview_width,
            preview_y + preview_height,
        };
        properties.fVisible = TRUE;
        properties.opacity = 255;
        properties.fSourceClientAreaOnly = FALSE;
        (void)DwmUpdateThumbnailProperties(thumbnail, &properties);
        thumbnails_.push_back(thumbnail);
    }
}

void CloudOSNativeTaskSwitcherWindow::ShowCycle(bool reverse)
{
    if (window_ == nullptr || window_manager_ == nullptr)
    {
        return;
    }

    const bool already_visible = IsWindowVisible(window_) != FALSE;
    if (!already_visible)
    {
        Rebuild();
        if (windows_.empty())
        {
            return;
        }

        HMONITOR monitor = MonitorFromWindow(
            window_manager_->ActiveManagedWindow(),
            MONITOR_DEFAULTTOPRIMARY);
        MONITORINFO info{};
        info.cbSize = sizeof(info);
        GetMonitorInfoW(monitor, &info);

        const UINT dpi = GetDpiForWindow(window_);
        const int width = std::min(Scale(980, dpi), std::max(Scale(540, dpi), info.rcWork.right - info.rcWork.left - Scale(80, dpi)));
        const int height = std::min(Scale(560, dpi), std::max(Scale(320, dpi), info.rcWork.bottom - info.rcWork.top - Scale(100, dpi)));
        const int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
        const int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2;

        SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
        ShowWindow(window_, SW_SHOWNORMAL);
        SetForegroundWindow(window_);
        LayoutThumbnails();
        Cycle(reverse ? -1 : 1);
    }
    else
    {
        Cycle(reverse ? -1 : 1);
    }

    KillTimer(window_, kCommitTimer);
    SetTimer(window_, kCommitTimer, 650, nullptr);
}

void CloudOSNativeTaskSwitcherWindow::Cycle(int delta)
{
    if (windows_.empty())
    {
        return;
    }
    const int count = static_cast<int>(windows_.size());
    selected_ = (selected_ + delta) % count;
    if (selected_ < 0)
    {
        selected_ += count;
    }
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeTaskSwitcherWindow::Commit()
{
    if (window_manager_ != nullptr && selected_ >= 0 && selected_ < static_cast<int>(windows_.size()))
    {
        const HWND target = windows_[static_cast<std::size_t>(selected_)].hwnd;
        Hide();
        window_manager_->FocusWindow(target);
        return;
    }
    Hide();
}

void CloudOSNativeTaskSwitcherWindow::Hide()
{
    if (window_ == nullptr)
    {
        return;
    }
    KillTimer(window_, kCommitTimer);
    ClearThumbnails();
    ShowWindow(window_, SW_HIDE);
}

void CloudOSNativeTaskSwitcherWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    const UINT dpi = GetDpiForWindow(window_);

    HDC memory = CreateCompatibleDC(dc);
    HBITMAP bitmap = CreateCompatibleBitmap(dc, width, height);
    HGDIOBJ old = SelectObject(memory, bitmap);

    Graphics graphics(memory);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    SolidBrush background(Color(246, 21, 23, 28));
    graphics.FillRectangle(&background, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    Font caption_font(L"Segoe UI", static_cast<REAL>(Scale(10, dpi)), FontStyleRegular, UnitPixel);
    SolidBrush white(Color(255, 244, 247, 251));
    SolidBrush secondary(Color(255, 190, 196, 207));

    for (std::size_t index = 0; index < cells_.size() && index < windows_.size(); ++index)
    {
        const RECT& cell = cells_[index];
        const bool selected = static_cast<int>(index) == selected_;
        Pen border(selected ? Color(255, 102, 168, 250) : Color(90, 94, 101, 114), selected ? 3.0f : 1.0f);
        graphics.DrawRectangle(
            &border,
            static_cast<REAL>(cell.left),
            static_cast<REAL>(cell.top),
            static_cast<REAL>(std::max(1, Width(cell) - 1)),
            static_cast<REAL>(std::max(1, Height(cell) - 1)));

        const int caption_height = Scale(32, dpi);
        DrawCenteredText(
            graphics,
            windows_[index].title.empty() ? L"Aplicativo" : windows_[index].title,
            caption_font,
            RectF(
                static_cast<REAL>(cell.left + Scale(6, dpi)),
                static_cast<REAL>(cell.bottom - caption_height),
                static_cast<REAL>(Width(cell) - Scale(12, dpi)),
                static_cast<REAL>(caption_height)),
            selected ? white : secondary);
    }

    BitBlt(dc, 0, 0, width, height, memory, 0, 0, SRCCOPY);
    SelectObject(memory, old);
    DeleteObject(bitmap);
    DeleteDC(memory);
    EndPaint(window_, &paint);
}

LRESULT CloudOSNativeTaskSwitcherWindow::HandleMessage(
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
        if (IsWindowVisible(window_))
        {
            LayoutThumbnails();
        }
        return 0;
    case WM_TIMER:
        if (w_param == kCommitTimer)
        {
            Commit();
            return 0;
        }
        break;
    case WM_KEYDOWN:
        switch (w_param)
        {
        case VK_TAB:
        case VK_RIGHT:
        case VK_DOWN:
            Cycle(1);
            return 0;
        case VK_LEFT:
        case VK_UP:
            Cycle(-1);
            return 0;
        case VK_RETURN:
            Commit();
            return 0;
        case VK_ESCAPE:
            Hide();
            return 0;
        default:
            break;
        }
        break;
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        for (std::size_t index = 0; index < cells_.size(); ++index)
        {
            if (Contains(cells_[index], point))
            {
                selected_ = static_cast<int>(index);
                Commit();
                return 0;
            }
        }
        break;
    }
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE)
        {
            Hide();
        }
        return 0;
    case WM_DESTROY:
        ClearThumbnails();
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeTaskSwitcherWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeTaskSwitcherWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeTaskSwitcherWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
