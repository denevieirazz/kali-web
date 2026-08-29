#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <dwmapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <string_view>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "dwmapi.lib")

using Microsoft::WRL::ComPtr;

namespace
{
constexpr wchar_t kWindowClassName[] = L"CloudOS.NativeShell.Window.v1";
constexpr float kTaskbarHeight = 58.0f;
constexpr float kStartButtonSize = 42.0f;
constexpr float kStartMenuWidth = 360.0f;
constexpr float kStartMenuHeight = 430.0f;

class CloudOSShell final
{
public:
    explicit CloudOSShell(HINSTANCE instance) noexcept : instance_(instance) {}

    bool Initialize(int showCommand)
    {
        const WNDCLASSEXW windowClass{
            .cbSize = sizeof(WNDCLASSEXW),
            .style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS,
            .lpfnWndProc = &CloudOSShell::WindowProcedure,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = instance_,
            .hIcon = LoadIconW(nullptr, IDI_APPLICATION),
            .hCursor = LoadCursorW(nullptr, IDC_ARROW),
            .hbrBackground = nullptr,
            .lpszMenuName = nullptr,
            .lpszClassName = kWindowClassName,
            .hIconSm = LoadIconW(nullptr, IDI_APPLICATION),
        };

        if (RegisterClassExW(&windowClass) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        {
            return false;
        }

        window_ = CreateWindowExW(
            WS_EX_APPWINDOW,
            kWindowClassName,
            L"CloudOS Native",
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            1440,
            900,
            nullptr,
            nullptr,
            instance_,
            this);

        if (window_ == nullptr)
        {
            return false;
        }

        const BOOL darkMode = TRUE;
        static constexpr DWORD immersiveDarkModeAttribute = 20;
        (void)DwmSetWindowAttribute(
            window_,
            immersiveDarkModeAttribute,
            &darkMode,
            sizeof(darkMode));

        if (!InitializeGraphics())
        {
            return false;
        }

        ShowWindow(window_, showCommand == SW_HIDE ? SW_SHOW : SW_MAXIMIZE);
        UpdateWindow(window_);
        return true;
    }

    int Run()
    {
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0)
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return static_cast<int>(message.wParam);
    }

private:
    bool InitializeGraphics()
    {
        if (FAILED(D2D1CreateFactory(
                D2D1_FACTORY_TYPE_SINGLE_THREADED,
                IID_PPV_ARGS(d2dFactory_.ReleaseAndGetAddressOf()))))
        {
            return false;
        }

        if (FAILED(DWriteCreateFactory(
                DWRITE_FACTORY_TYPE_SHARED,
                __uuidof(IDWriteFactory),
                reinterpret_cast<IUnknown**>(dwriteFactory_.ReleaseAndGetAddressOf()))))
        {
            return false;
        }

        const HRESULT titleResult = dwriteFactory_->CreateTextFormat(
            L"Segoe UI",
            nullptr,
            DWRITE_FONT_WEIGHT_SEMI_BOLD,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            28.0f,
            L"pt-BR",
            titleFormat_.ReleaseAndGetAddressOf());
        if (FAILED(titleResult))
        {
            return false;
        }

        const HRESULT bodyResult = dwriteFactory_->CreateTextFormat(
            L"Segoe UI",
            nullptr,
            DWRITE_FONT_WEIGHT_NORMAL,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            15.0f,
            L"pt-BR",
            bodyFormat_.ReleaseAndGetAddressOf());
        if (FAILED(bodyResult))
        {
            return false;
        }

        const HRESULT menuResult = dwriteFactory_->CreateTextFormat(
            L"Segoe UI",
            nullptr,
            DWRITE_FONT_WEIGHT_SEMI_BOLD,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            17.0f,
            L"pt-BR",
            menuFormat_.ReleaseAndGetAddressOf());
        return SUCCEEDED(menuResult);
    }

    bool CreateDeviceResources()
    {
        if (renderTarget_ != nullptr)
        {
            return true;
        }

        RECT client{};
        if (!GetClientRect(window_, &client))
        {
            return false;
        }

        const auto width = static_cast<UINT32>(std::max<LONG>(1, client.right - client.left));
        const auto height = static_cast<UINT32>(std::max<LONG>(1, client.bottom - client.top));

        const HRESULT renderResult = d2dFactory_->CreateHwndRenderTarget(
            D2D1::RenderTargetProperties(),
            D2D1::HwndRenderTargetProperties(window_, D2D1::SizeU(width, height)),
            renderTarget_.ReleaseAndGetAddressOf());
        if (FAILED(renderResult))
        {
            return false;
        }

        struct BrushDefinition
        {
            D2D1_COLOR_F color;
            ComPtr<ID2D1SolidColorBrush>* brush;
        };

        const std::array<BrushDefinition, 7> brushes{{
            {D2D1::ColorF(0x10131A), &backgroundBrush_},
            {D2D1::ColorF(0x171B24, 0.97f), &taskbarBrush_},
            {D2D1::ColorF(0x252B38), &panelBrush_},
            {D2D1::ColorF(0x3A4355), &borderBrush_},
            {D2D1::ColorF(0xF4F7FB), &primaryTextBrush_},
            {D2D1::ColorF(0x9AA6B6), &secondaryTextBrush_},
            {D2D1::ColorF(0x5B8CFF), &accentBrush_},
        }};

        for (const auto& definition : brushes)
        {
            if (FAILED(renderTarget_->CreateSolidColorBrush(
                    definition.color,
                    definition.brush->ReleaseAndGetAddressOf())))
            {
                DiscardDeviceResources();
                return false;
            }
        }

        return true;
    }

    void DiscardDeviceResources() noexcept
    {
        accentBrush_.Reset();
        secondaryTextBrush_.Reset();
        primaryTextBrush_.Reset();
        borderBrush_.Reset();
        panelBrush_.Reset();
        taskbarBrush_.Reset();
        backgroundBrush_.Reset();
        renderTarget_.Reset();
    }

    void Paint()
    {
        PAINTSTRUCT paint{};
        BeginPaint(window_, &paint);

        if (!CreateDeviceResources())
        {
            EndPaint(window_, &paint);
            return;
        }

        renderTarget_->BeginDraw();
        renderTarget_->Clear(backgroundBrush_->GetColor());

        const auto size = renderTarget_->GetSize();
        DrawDesktop(size.width, size.height);

        const HRESULT result = renderTarget_->EndDraw();
        if (result == D2DERR_RECREATE_TARGET)
        {
            DiscardDeviceResources();
        }

        EndPaint(window_, &paint);
    }

    void DrawDesktop(float width, float height)
    {
        const auto workspaceBottom = std::max(0.0f, height - kTaskbarHeight);

        const D2D1_ROUNDED_RECT statusCard{
            .rect = D2D1::RectF(28.0f, 26.0f, 465.0f, 144.0f),
            .radiusX = 16.0f,
            .radiusY = 16.0f,
        };
        renderTarget_->FillRoundedRectangle(statusCard, panelBrush_.Get());
        renderTarget_->DrawRoundedRectangle(statusCard, borderBrush_.Get(), 1.0f);

        DrawTextLine(L"CloudOS Native", titleFormat_.Get(), primaryTextBrush_.Get(), 48.0f, 46.0f, 390.0f, 42.0f);
        DrawTextLine(L"C++ / Win32 / Direct2D / DirectWrite", bodyFormat_.Get(), secondaryTextBrush_.Get(), 49.0f, 91.0f, 390.0f, 28.0f);

        const D2D1_ROUNDED_RECT nativeChip{
            .rect = D2D1::RectF(28.0f, 162.0f, 245.0f, 202.0f),
            .radiusX = 12.0f,
            .radiusY = 12.0f,
        };
        renderTarget_->FillRoundedRectangle(nativeChip, panelBrush_.Get());
        renderTarget_->DrawRoundedRectangle(nativeChip, accentBrush_.Get(), 1.0f);
        DrawTextLine(L"WEB RUNTIME: OFF", menuFormat_.Get(), primaryTextBrush_.Get(), 45.0f, 171.0f, 190.0f, 25.0f);

        const D2D1_RECT_F taskbar = D2D1::RectF(0.0f, workspaceBottom, width, height);
        renderTarget_->FillRectangle(taskbar, taskbarBrush_.Get());
        renderTarget_->DrawLine(
            D2D1::Point2F(0.0f, workspaceBottom),
            D2D1::Point2F(width, workspaceBottom),
            borderBrush_.Get(),
            1.0f);

        const auto start = StartButtonRect(width, height);
        const D2D1_ROUNDED_RECT startBackground{
            .rect = start,
            .radiusX = 10.0f,
            .radiusY = 10.0f,
        };
        renderTarget_->FillRoundedRectangle(startBackground, startMenuOpen_ ? panelBrush_.Get() : taskbarBrush_.Get());
        renderTarget_->DrawRoundedRectangle(startBackground, startMenuOpen_ ? accentBrush_.Get() : borderBrush_.Get(), 1.0f);
        DrawWindowsGlyph(start);

        DrawTextLine(L"CloudOS.NativeShell.exe", bodyFormat_.Get(), secondaryTextBrush_.Get(), start.right + 14.0f, workspaceBottom + 19.0f, 250.0f, 24.0f);

        if (startMenuOpen_)
        {
            DrawStartMenu(width, height);
        }
    }

    void DrawStartMenu(float width, float height)
    {
        const auto start = StartButtonRect(width, height);
        const float left = std::max(18.0f, start.left - 14.0f);
        const float bottom = start.top - 12.0f;
        const float top = std::max(18.0f, bottom - kStartMenuHeight);
        const D2D1_ROUNDED_RECT panel{
            .rect = D2D1::RectF(left, top, left + kStartMenuWidth, bottom),
            .radiusX = 20.0f,
            .radiusY = 20.0f,
        };
        renderTarget_->FillRoundedRectangle(panel, panelBrush_.Get());
        renderTarget_->DrawRoundedRectangle(panel, borderBrush_.Get(), 1.0f);

        DrawTextLine(L"CloudOS", titleFormat_.Get(), primaryTextBrush_.Get(), left + 24.0f, top + 24.0f, 250.0f, 40.0f);
        DrawTextLine(L"Runtime nativo do Windows", bodyFormat_.Get(), secondaryTextBrush_.Get(), left + 25.0f, top + 66.0f, 285.0f, 28.0f);

        const std::array<std::wstring_view, 4> items{
            L"Terminal nativo (ConPTY)",
            L"Arquivos",
            L"Processos",
            L"Configurações",
        };

        float y = top + 125.0f;
        for (const auto item : items)
        {
            const D2D1_ROUNDED_RECT row{
                .rect = D2D1::RectF(left + 18.0f, y, left + kStartMenuWidth - 18.0f, y + 54.0f),
                .radiusX = 12.0f,
                .radiusY = 12.0f,
            };
            renderTarget_->DrawRoundedRectangle(row, borderBrush_.Get(), 1.0f);
            DrawTextLine(item, menuFormat_.Get(), primaryTextBrush_.Get(), left + 36.0f, y + 16.0f, kStartMenuWidth - 72.0f, 26.0f);
            y += 64.0f;
        }
    }

    void DrawWindowsGlyph(const D2D1_RECT_F& bounds)
    {
        constexpr float gap = 2.5f;
        constexpr float tile = 8.0f;
        const float centerX = (bounds.left + bounds.right) * 0.5f;
        const float centerY = (bounds.top + bounds.bottom) * 0.5f;
        const float left = centerX - tile - gap * 0.5f;
        const float top = centerY - tile - gap * 0.5f;

        renderTarget_->FillRectangle(D2D1::RectF(left, top, left + tile, top + tile), accentBrush_.Get());
        renderTarget_->FillRectangle(D2D1::RectF(left + tile + gap, top, left + tile * 2.0f + gap, top + tile), accentBrush_.Get());
        renderTarget_->FillRectangle(D2D1::RectF(left, top + tile + gap, left + tile, top + tile * 2.0f + gap), accentBrush_.Get());
        renderTarget_->FillRectangle(D2D1::RectF(left + tile + gap, top + tile + gap, left + tile * 2.0f + gap, top + tile * 2.0f + gap), accentBrush_.Get());
    }

    void DrawTextLine(
        const std::wstring_view text,
        IDWriteTextFormat* format,
        ID2D1Brush* brush,
        float x,
        float y,
        float width,
        float height)
    {
        const auto layout = D2D1::RectF(x, y, x + width, y + height);
        renderTarget_->DrawTextW(
            text.data(),
            static_cast<UINT32>(text.size()),
            format,
            layout,
            brush,
            D2D1_DRAW_TEXT_OPTIONS_CLIP);
    }

    D2D1_RECT_F StartButtonRect(float width, float height) const noexcept
    {
        const float taskbarTop = std::max(0.0f, height - kTaskbarHeight);
        const float left = std::max(16.0f, width * 0.5f - 160.0f);
        const float top = taskbarTop + (kTaskbarHeight - kStartButtonSize) * 0.5f;
        return D2D1::RectF(left, top, left + kStartButtonSize, top + kStartButtonSize);
    }

    void Resize(UINT width, UINT height)
    {
        if (renderTarget_ != nullptr && width > 0 && height > 0)
        {
            const HRESULT result = renderTarget_->Resize(D2D1::SizeU(width, height));
            if (FAILED(result))
            {
                DiscardDeviceResources();
            }
        }
        InvalidateRect(window_, nullptr, FALSE);
    }

    void ToggleStartMenu()
    {
        startMenuOpen_ = !startMenuOpen_;
        InvalidateRect(window_, nullptr, FALSE);
    }

    void ToggleFullscreen()
    {
        if (!fullscreen_)
        {
            savedStyle_ = static_cast<DWORD>(GetWindowLongPtrW(window_, GWL_STYLE));
            savedPlacement_.length = sizeof(WINDOWPLACEMENT);
            if (!GetWindowPlacement(window_, &savedPlacement_))
            {
                return;
            }

            MONITORINFO monitorInfo{.cbSize = sizeof(MONITORINFO)};
            if (!GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitorInfo))
            {
                return;
            }

            SetWindowLongPtrW(window_, GWL_STYLE, static_cast<LONG_PTR>(savedStyle_ & ~WS_OVERLAPPEDWINDOW));
            SetWindowPos(
                window_,
                HWND_TOP,
                monitorInfo.rcMonitor.left,
                monitorInfo.rcMonitor.top,
                monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left,
                monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top,
                SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
            fullscreen_ = true;
        }
        else
        {
            SetWindowLongPtrW(window_, GWL_STYLE, static_cast<LONG_PTR>(savedStyle_));
            SetWindowPlacement(window_, &savedPlacement_);
            SetWindowPos(
                window_,
                nullptr,
                0,
                0,
                0,
                0,
                SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER);
            fullscreen_ = false;
        }
        InvalidateRect(window_, nullptr, FALSE);
    }

    LRESULT HandleMessage(UINT message, WPARAM wParam, LPARAM lParam)
    {
        switch (message)
        {
        case WM_PAINT:
            Paint();
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_SIZE:
            Resize(LOWORD(lParam), HIWORD(lParam));
            return 0;

        case WM_DPICHANGED:
        {
            const auto* suggested = reinterpret_cast<const RECT*>(lParam);
            SetWindowPos(
                window_,
                nullptr,
                suggested->left,
                suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOACTIVATE | SWP_NOZORDER);
            DiscardDeviceResources();
            InvalidateRect(window_, nullptr, FALSE);
            return 0;
        }

        case WM_LBUTTONUP:
        {
            if (renderTarget_ == nullptr)
            {
                return 0;
            }
            const auto size = renderTarget_->GetSize();
            const auto start = StartButtonRect(size.width, size.height);
            const float x = static_cast<float>(GET_X_LPARAM(lParam));
            const float y = static_cast<float>(GET_Y_LPARAM(lParam));
            if (x >= start.left && x <= start.right && y >= start.top && y <= start.bottom)
            {
                ToggleStartMenu();
            }
            else if (startMenuOpen_)
            {
                startMenuOpen_ = false;
                InvalidateRect(window_, nullptr, FALSE);
            }
            return 0;
        }

        case WM_KEYDOWN:
            if (wParam == VK_F11)
            {
                ToggleFullscreen();
                return 0;
            }
            if (wParam == VK_ESCAPE && startMenuOpen_)
            {
                startMenuOpen_ = false;
                InvalidateRect(window_, nullptr, FALSE);
                return 0;
            }
            break;

        case WM_DISPLAYCHANGE:
            InvalidateRect(window_, nullptr, FALSE);
            return 0;

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;

        default:
            break;
        }

        return DefWindowProcW(window_, message, wParam, lParam);
    }

    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
    {
        CloudOSShell* shell = nullptr;
        if (message == WM_NCCREATE)
        {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            shell = static_cast<CloudOSShell*>(create->lpCreateParams);
            shell->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(shell));
        }
        else
        {
            shell = reinterpret_cast<CloudOSShell*>(GetWindowLongPtrW(window, GWLP_USERDATA));
        }

        return shell != nullptr
            ? shell->HandleMessage(message, wParam, lParam)
            : DefWindowProcW(window, message, wParam, lParam);
    }

    HINSTANCE instance_{};
    HWND window_{};
    bool startMenuOpen_{};
    bool fullscreen_{};
    DWORD savedStyle_{WS_OVERLAPPEDWINDOW};
    WINDOWPLACEMENT savedPlacement_{.length = sizeof(WINDOWPLACEMENT)};

    ComPtr<ID2D1Factory> d2dFactory_;
    ComPtr<IDWriteFactory> dwriteFactory_;
    ComPtr<IDWriteTextFormat> titleFormat_;
    ComPtr<IDWriteTextFormat> bodyFormat_;
    ComPtr<IDWriteTextFormat> menuFormat_;
    ComPtr<ID2D1HwndRenderTarget> renderTarget_;
    ComPtr<ID2D1SolidColorBrush> backgroundBrush_;
    ComPtr<ID2D1SolidColorBrush> taskbarBrush_;
    ComPtr<ID2D1SolidColorBrush> panelBrush_;
    ComPtr<ID2D1SolidColorBrush> borderBrush_;
    ComPtr<ID2D1SolidColorBrush> primaryTextBrush_;
    ComPtr<ID2D1SolidColorBrush> secondaryTextBrush_;
    ComPtr<ID2D1SolidColorBrush> accentBrush_;
};
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand)
{
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool uninitializeCom = SUCCEEDED(comResult);

    CloudOSShell shell(instance);
    if (!shell.Initialize(showCommand))
    {
        if (uninitializeCom)
        {
            CoUninitialize();
        }
        MessageBoxW(nullptr, L"O CloudOS Native não conseguiu inicializar o runtime gráfico Win32.", L"CloudOS Native", MB_OK | MB_ICONERROR);
        return 1;
    }

    const int exitCode = shell.Run();
    if (uninitializeCom)
    {
        CoUninitialize();
    }
    return exitCode;
}
