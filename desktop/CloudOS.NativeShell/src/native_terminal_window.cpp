#include "native_terminal_window.h"

#include "cloudos_native_runtime.h"

#include <dwmapi.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <new>
#include <string_view>
#include <utility>

#pragma comment(lib, "dwmapi.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Terminal.v2";
constexpr UINT kOutputMessage = WM_APP + 0x330;
constexpr std::size_t kMaximumScrollbackCharacters = 200000;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeTerminalWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_IBEAM);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::string ToUtf8(std::wstring_view text)
{
    if (text.empty())
    {
        return {};
    }

    const int required = WideCharToMultiByte(
        CP_UTF8,
        0,
        text.data(),
        static_cast<int>(text.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0)
    {
        return {};
    }

    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            0,
            text.data(),
            static_cast<int>(text.size()),
            result.data(),
            required,
            nullptr,
            nullptr) <= 0)
    {
        return {};
    }
    return result;
}
}

CloudOSNativeTerminalWindow::CloudOSNativeTerminalWindow(
    HINSTANCE instance,
    std::wstring command_line,
    std::wstring title)
    : instance_(instance),
      command_line_(std::move(command_line)),
      title_(std::move(title))
{
}

CloudOSNativeTerminalWindow::~CloudOSNativeTerminalWindow()
{
    StopTerminal();
    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }
}

void CloudOSNativeTerminalWindow::Open(
    HINSTANCE instance,
    const std::wstring& command_line,
    const std::wstring& title)
{
    auto* terminal = new (std::nothrow) CloudOSNativeTerminalWindow(
        instance,
        command_line,
        title);
    if (terminal == nullptr || !terminal->Create())
    {
        const DWORD error = GetLastError();
        delete terminal;

        wchar_t message[220]{};
        swprintf_s(
            message,
            L"Terminal nativo nao iniciou. Win32=%lu",
            error);
        MessageBoxW(
            nullptr,
            message,
            L"CloudOS Terminal",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeTerminalWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        title_.c_str(),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        980,
        640,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    const BOOL dark_mode = TRUE;
    constexpr DWORD immersive_dark_mode_attribute = 20;
    (void)DwmSetWindowAttribute(
        window_,
        immersive_dark_mode_attribute,
        &dark_mode,
        static_cast<DWORD>(sizeof(dark_mode)));

    UpdateFontMetrics();
    if (!StartTerminal())
    {
        const DWORD error = GetLastError();
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
        DestroyWindow(window_);
        window_ = nullptr;
        SetLastError(error);
        return false;
    }

    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetFocus(window_);
    return true;
}

bool CloudOSNativeTerminalWindow::StartTerminal()
{
    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return false;
    }

    const int client_width = static_cast<int>(client.right - client.left);
    const int client_height = static_cast<int>(client.bottom - client.top);
    const SHORT columns = static_cast<SHORT>(std::clamp(
        client_width / std::max(1, cell_width_),
        20,
        240));
    const SHORT rows = static_cast<SHORT>(std::clamp(
        client_height / std::max(1, cell_height_),
        5,
        120));

    if (!cloudos_native_terminal_create(
            command_line_.c_str(),
            nullptr,
            columns,
            rows,
            &terminal_,
            &process_id_))
    {
        return false;
    }

    stopping_.store(false);
    try
    {
        reader_thread_ = std::thread(&CloudOSNativeTerminalWindow::ReaderLoop, this);
    }
    catch (...)
    {
        (void)cloudos_native_terminal_terminate(terminal_, 1);
        cloudos_native_terminal_release(terminal_);
        terminal_ = nullptr;
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return false;
    }
    return true;
}

void CloudOSNativeTerminalWindow::StopTerminal() noexcept
{
    stopping_.store(true);

    if (terminal_ != nullptr)
    {
        DWORD exit_code = 0;
        BOOL exited = FALSE;
        if (cloudos_native_terminal_get_exit_code(terminal_, &exit_code, &exited) && !exited)
        {
            (void)cloudos_native_terminal_terminate(terminal_, 0);
        }
    }

    if (reader_thread_.joinable())
    {
        (void)CancelSynchronousIo(reader_thread_.native_handle());
        reader_thread_.join();
    }

    if (terminal_ != nullptr)
    {
        cloudos_native_terminal_release(terminal_);
        terminal_ = nullptr;
    }
}

void CloudOSNativeTerminalWindow::ReaderLoop()
{
    std::array<char, 8192> buffer{};
    while (!stopping_.load())
    {
        DWORD bytes_read = 0;
        if (!cloudos_native_terminal_read(
                terminal_,
                buffer.data(),
                static_cast<DWORD>(buffer.size()),
                &bytes_read) ||
            bytes_read == 0)
        {
            break;
        }

        ConsumeOutputBytes(buffer.data(), bytes_read);
        if (window_ != nullptr)
        {
            PostMessageW(window_, kOutputMessage, 0, 0);
        }
    }

    if (!stopping_.load() && terminal_ != nullptr)
    {
        DWORD exit_code = 0;
        BOOL exited = FALSE;
        if (cloudos_native_terminal_get_exit_code(terminal_, &exit_code, &exited) && exited)
        {
            wchar_t text[100]{};
            swprintf_s(text, L"\r\n[processo encerrado: %lu]\r\n", exit_code);
            AppendText(text);
        }
    }

    if (window_ != nullptr)
    {
        PostMessageW(window_, kOutputMessage, 0, 0);
    }
}

void CloudOSNativeTerminalWindow::ConsumeOutputBytes(const char* bytes, DWORD size)
{
    for (DWORD index = 0; index < size; ++index)
    {
        const unsigned char value = static_cast<unsigned char>(bytes[index]);
        if (ansi_state_ == 1)
        {
            ansi_state_ = value == '[' ? 2 : 0;
            continue;
        }
        if (ansi_state_ == 2)
        {
            if (value >= 0x40 && value <= 0x7e)
            {
                ansi_state_ = 0;
            }
            continue;
        }
        if (value == 0x1b)
        {
            ansi_state_ = 1;
            continue;
        }
        pending_utf8_.push_back(static_cast<char>(value));
    }
    FlushUtf8Pending();
}

void CloudOSNativeTerminalWindow::FlushUtf8Pending()
{
    while (!pending_utf8_.empty())
    {
        std::size_t valid_length = pending_utf8_.size();
        int required = 0;

        for (std::size_t trim = 0;
            trim <= 3 && trim < pending_utf8_.size();
            ++trim)
        {
            valid_length = pending_utf8_.size() - trim;
            required = MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                pending_utf8_.data(),
                static_cast<int>(valid_length),
                nullptr,
                0);
            if (required > 0)
            {
                break;
            }
        }

        if (required <= 0)
        {
            if (pending_utf8_.size() > 4)
            {
                AppendText(L"?");
                pending_utf8_.erase(pending_utf8_.begin());
                continue;
            }
            return;
        }

        std::wstring wide(static_cast<std::size_t>(required), L'\0');
        if (MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                pending_utf8_.data(),
                static_cast<int>(valid_length),
                wide.data(),
                required) <= 0)
        {
            return;
        }

        std::wstring clean;
        clean.reserve(wide.size());
        for (wchar_t character : wide)
        {
            if (character == L'\r')
            {
                continue;
            }
            if (character == L'\b')
            {
                if (!clean.empty())
                {
                    clean.pop_back();
                }
                continue;
            }
            if (character == L'\n' || character == L'\t' || character >= L' ')
            {
                clean.push_back(character);
            }
        }

        AppendText(clean);
        pending_utf8_.erase(
            pending_utf8_.begin(),
            pending_utf8_.begin() + static_cast<std::ptrdiff_t>(valid_length));
    }
}

void CloudOSNativeTerminalWindow::AppendText(std::wstring_view text)
{
    if (text.empty())
    {
        return;
    }

    std::lock_guard lock(output_mutex_);
    output_.append(text);
    if (output_.size() > kMaximumScrollbackCharacters)
    {
        output_.erase(0, output_.size() - kMaximumScrollbackCharacters);
    }
    scroll_offset_lines_ = 0;
}

void CloudOSNativeTerminalWindow::WriteBytes(const void* bytes, DWORD size)
{
    if (terminal_ == nullptr || bytes == nullptr || size == 0)
    {
        return;
    }

    const auto* data = static_cast<const std::byte*>(bytes);
    DWORD offset = 0;
    while (offset < size)
    {
        DWORD written = 0;
        if (!cloudos_native_terminal_write(
                terminal_,
                data + offset,
                size - offset,
                &written) ||
            written == 0)
        {
            break;
        }
        offset += written;
    }
}

void CloudOSNativeTerminalWindow::WriteUtf8(std::wstring_view text)
{
    const std::string utf8 = ToUtf8(text);
    if (!utf8.empty())
    {
        WriteBytes(utf8.data(), static_cast<DWORD>(utf8.size()));
    }
}

void CloudOSNativeTerminalWindow::PasteClipboard()
{
    if (!OpenClipboard(window_))
    {
        return;
    }

    HANDLE clipboard = GetClipboardData(CF_UNICODETEXT);
    if (clipboard != nullptr)
    {
        const auto* text = static_cast<const wchar_t*>(GlobalLock(clipboard));
        if (text != nullptr)
        {
            WriteUtf8(text);
            GlobalUnlock(clipboard);
        }
    }
    CloseClipboard();
}

void CloudOSNativeTerminalWindow::ResizeTerminal()
{
    if (terminal_ == nullptr || window_ == nullptr)
    {
        return;
    }

    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int client_width = static_cast<int>(client.right - client.left);
    const int client_height = static_cast<int>(client.bottom - client.top);
    const SHORT columns = static_cast<SHORT>(std::clamp(
        client_width / std::max(1, cell_width_),
        20,
        240));
    const SHORT rows = static_cast<SHORT>(std::clamp(
        client_height / std::max(1, cell_height_),
        5,
        120));
    (void)cloudos_native_terminal_resize(terminal_, columns, rows);
}

void CloudOSNativeTerminalWindow::UpdateFontMetrics()
{
    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }

    const UINT dpi = window_ != nullptr ? GetDpiForWindow(window_) : 96;
    font_ = CreateFontW(
        -MulDiv(15, static_cast<int>(dpi), 96),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        FIXED_PITCH | FF_MODERN,
        L"Cascadia Mono");
    if (font_ == nullptr)
    {
        font_ = CreateFontW(
            -MulDiv(15, static_cast<int>(dpi), 96),
            0,
            0,
            0,
            FW_NORMAL,
            FALSE,
            FALSE,
            FALSE,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            FIXED_PITCH | FF_MODERN,
            L"Consolas");
    }
    if (font_ == nullptr)
    {
        return;
    }

    HDC device = GetDC(window_);
    if (device == nullptr)
    {
        return;
    }

    const HGDIOBJ previous = SelectObject(device, font_);
    TEXTMETRICW metrics{};
    if (GetTextMetricsW(device, &metrics))
    {
        cell_width_ = std::max(1, static_cast<int>(metrics.tmAveCharWidth));
        cell_height_ = std::max(
            1,
            static_cast<int>(metrics.tmHeight + metrics.tmExternalLeading));
    }
    SelectObject(device, previous);
    ReleaseDC(window_, device);
}

void CloudOSNativeTerminalWindow::ScrollBy(int lines)
{
    std::lock_guard lock(output_mutex_);
    int total_lines = 1;
    for (wchar_t character : output_)
    {
        if (character == L'\n')
        {
            ++total_lines;
        }
    }
    scroll_offset_lines_ = std::clamp(
        scroll_offset_lines_ + lines,
        0,
        std::max(0, total_lines - 1));
    InvalidateRect(window_, nullptr, FALSE);
}

std::vector<std::wstring> CloudOSNativeTerminalWindow::VisibleLines() const
{
    RECT client{};
    if (window_ == nullptr || !GetClientRect(window_, &client))
    {
        return {};
    }

    const int client_height = static_cast<int>(client.bottom - client.top);
    const std::size_t visible_rows = static_cast<std::size_t>(std::max(
        1,
        client_height / std::max(1, cell_height_)));

    std::vector<std::wstring> all_lines;
    std::size_t offset = 0;
    {
        std::lock_guard lock(output_mutex_);
        offset = static_cast<std::size_t>(std::max(0, scroll_offset_lines_));
        std::size_t start = 0;
        while (start <= output_.size())
        {
            const std::size_t end = output_.find(L'\n', start);
            if (end == std::wstring::npos)
            {
                all_lines.push_back(output_.substr(start));
                break;
            }
            all_lines.push_back(output_.substr(start, end - start));
            start = end + 1;
        }
    }

    if (all_lines.empty())
    {
        return {};
    }

    const std::size_t end = all_lines.size() > offset
        ? all_lines.size() - offset
        : 0;
    const std::size_t begin = end > visible_rows ? end - visible_rows : 0;

    return std::vector<std::wstring>(
        all_lines.begin() + static_cast<std::ptrdiff_t>(begin),
        all_lines.begin() + static_cast<std::ptrdiff_t>(end));
}

void CloudOSNativeTerminalWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC device = BeginPaint(window_, &paint);

    RECT client{};
    GetClientRect(window_, &client);
    HBRUSH background = CreateSolidBrush(RGB(12, 15, 20));
    FillRect(device, &client, background);
    DeleteObject(background);

    SetBkMode(device, TRANSPARENT);
    SetTextColor(device, RGB(232, 236, 242));

    HGDIOBJ previous = nullptr;
    if (font_ != nullptr)
    {
        previous = SelectObject(device, font_);
    }

    int y = 4;
    for (const auto& line : VisibleLines())
    {
        TextOutW(
            device,
            6,
            y,
            line.data(),
            static_cast<int>(line.size()));
        y += cell_height_;
        if (y >= client.bottom)
        {
            break;
        }
    }

    if (previous != nullptr)
    {
        SelectObject(device, previous);
    }
    EndPaint(window_, &paint);
}

LRESULT CloudOSNativeTerminalWindow::HandleMessage(
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case kOutputMessage:
        InvalidateRect(window_, nullptr, FALSE);
        return 0;

    case WM_PAINT:
        Paint();
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_SIZE:
        ResizeTerminal();
        return 0;

    case WM_DPICHANGED:
    {
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        SetWindowPos(
            window_,
            nullptr,
            suggested->left,
            suggested->top,
            suggested->right - suggested->left,
            suggested->bottom - suggested->top,
            SWP_NOZORDER | SWP_NOACTIVATE);
        UpdateFontMetrics();
        ResizeTerminal();
        return 0;
    }

    case WM_MOUSEWHEEL:
        ScrollBy(GET_WHEEL_DELTA_WPARAM(w_param) > 0 ? 3 : -3);
        return 0;

    case WM_RBUTTONUP:
        PasteClipboard();
        return 0;

    case WM_KEYDOWN:
    {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        if (control && shift && (w_param == L'V' || w_param == L'v'))
        {
            PasteClipboard();
            return 0;
        }

        switch (w_param)
        {
        case VK_UP:
            WriteBytes("\x1b[A", 3);
            return 0;
        case VK_DOWN:
            WriteBytes("\x1b[B", 3);
            return 0;
        case VK_RIGHT:
            WriteBytes("\x1b[C", 3);
            return 0;
        case VK_LEFT:
            WriteBytes("\x1b[D", 3);
            return 0;
        case VK_HOME:
            WriteBytes("\x1b[H", 3);
            return 0;
        case VK_END:
            WriteBytes("\x1b[F", 3);
            return 0;
        case VK_DELETE:
            WriteBytes("\x1b[3~", 4);
            return 0;
        case VK_PRIOR:
            ScrollBy(12);
            return 0;
        case VK_NEXT:
            ScrollBy(-12);
            return 0;
        default:
            break;
        }
        break;
    }

    case WM_CHAR:
    {
        const wchar_t character = static_cast<wchar_t>(w_param);
        if (character == L'\b')
        {
            const char erase = 0x7f;
            WriteBytes(&erase, 1);
        }
        else if (character == L'\r')
        {
            const char enter = '\r';
            WriteBytes(&enter, 1);
        }
        else if (character == L'\t')
        {
            const char tab = '\t';
            WriteBytes(&tab, 1);
        }
        else if (character > 0)
        {
            const wchar_t text[2]{character, 0};
            WriteUtf8(text);
        }
        return 0;
    }

    case WM_CLOSE:
        StopTerminal();
        DestroyWindow(window_);
        return 0;

    case WM_NCDESTROY:
        window_ = nullptr;
        delete this;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeTerminalWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeTerminalWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeTerminalWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeTerminalWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
