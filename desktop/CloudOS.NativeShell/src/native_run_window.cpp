#include "native_run_window.h"

#include <shellapi.h>

#include <algorithm>
#include <new>
#include <string>
#include <vector>

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Run.v2";
constexpr int kEditId = 1001;
constexpr int kRunId = 1002;
constexpr int kCancelId = 1003;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeRunWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring ReadText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    if (length <= 0)
    {
        return {};
    }

    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    GetWindowTextW(edit, text.data(), length + 1);
    text.resize(static_cast<std::size_t>(length));
    return text;
}
}

CloudOSNativeRunWindow::CloudOSNativeRunWindow(HINSTANCE instance)
    : instance_(instance)
{
}

void CloudOSNativeRunWindow::Open(HINSTANCE instance)
{
    auto* run = new (std::nothrow) CloudOSNativeRunWindow(instance);
    if (run == nullptr || !run->Create())
    {
        delete run;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Executar.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeRunWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        kClassName,
        L"Executar - CloudOS",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        620,
        170,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kEditId),
        instance_,
        nullptr);
    launch_button_ = CreateWindowW(
        L"BUTTON",
        L"Executar",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kRunId),
        instance_,
        nullptr);
    cancel_button_ = CreateWindowW(
        L"BUTTON",
        L"Cancelar",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kCancelId),
        instance_,
        nullptr);

    if (edit_ == nullptr || launch_button_ == nullptr || cancel_button_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    const auto font = reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT));
    SendMessageW(edit_, WM_SETFONT, font, TRUE);
    SendMessageW(launch_button_, WM_SETFONT, font, TRUE);
    SendMessageW(cancel_button_, WM_SETFONT, font, TRUE);

    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetFocus(edit_);
    return true;
}

void CloudOSNativeRunWindow::Layout()
{
    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int width = client.right - client.left;
    MoveWindow(edit_, 16, 20, std::max(100, width - 32), 30, TRUE);
    MoveWindow(launch_button_, std::max(16, width - 216), 65, 96, 30, TRUE);
    MoveWindow(cancel_button_, std::max(116, width - 112), 65, 96, 30, TRUE);
}

void CloudOSNativeRunWindow::Launch()
{
    const std::wstring command = ReadText(edit_);
    if (command.empty())
    {
        return;
    }

    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (CreateProcessW(
            nullptr,
            mutable_command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_UNICODE_ENVIRONMENT,
            nullptr,
            nullptr,
            &startup,
            &process))
    {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        DestroyWindow(window_);
        return;
    }

    const DWORD create_error = GetLastError();
    HINSTANCE shell_result = ShellExecuteW(
        window_,
        L"open",
        command.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(shell_result) > 32)
    {
        DestroyWindow(window_);
        return;
    }

    wchar_t message[220]{};
    swprintf_s(
        message,
        L"Nao foi possivel executar o comando. Win32=%lu",
        create_error);
    MessageBoxW(window_, message, L"CloudOS", MB_OK | MB_ICONERROR);
}

LRESULT CloudOSNativeRunWindow::HandleMessage(
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;

    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kRunId:
            Launch();
            return 0;
        case kCancelId:
            DestroyWindow(window_);
            return 0;
        default:
            break;
        }
        break;

    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE)
        {
            DestroyWindow(window_);
            return 0;
        }
        break;

    case WM_CLOSE:
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

LRESULT CALLBACK CloudOSNativeRunWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeRunWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeRunWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeRunWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
