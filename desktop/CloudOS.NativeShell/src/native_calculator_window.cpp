#include "native_calculator_window.h"

#include <windows.h>
#include <array>
#include <cwchar>
#include <string>

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.NativeCalculator.v1";
constexpr int kDisplayId = 100;
constexpr int kButtonBaseId = 200;

struct CalculatorState final
{
    HWND display{};
    double accumulator{};
    wchar_t pending_operator{};
    bool replace_display{true};
};

std::wstring ReadDisplay(HWND display)
{
    const int length = GetWindowTextLengthW(display);
    std::wstring text(static_cast<std::size_t>(length), L'\0');
    if (length > 0)
    {
        GetWindowTextW(display, text.data(), length + 1);
    }
    return text.empty() ? L"0" : text;
}

double DisplayValue(HWND display)
{
    const std::wstring text = ReadDisplay(display);
    wchar_t* end = nullptr;
    const double value = wcstod(text.c_str(), &end);
    return end == text.c_str() ? 0.0 : value;
}

void SetDisplay(HWND display, double value)
{
    wchar_t buffer[128]{};
    swprintf_s(buffer, L"%.12g", value);
    SetWindowTextW(display, buffer);
}

void SetDisplayText(HWND display, const wchar_t* value)
{
    SetWindowTextW(display, value);
}

bool ApplyPending(CalculatorState& state)
{
    if (state.pending_operator == 0)
    {
        state.accumulator = DisplayValue(state.display);
        return true;
    }

    const double rhs = DisplayValue(state.display);
    switch (state.pending_operator)
    {
    case L'+': state.accumulator += rhs; break;
    case L'-': state.accumulator -= rhs; break;
    case L'*': state.accumulator *= rhs; break;
    case L'/':
        if (rhs == 0.0)
        {
            SetDisplayText(state.display, L"Erro");
            state.accumulator = 0.0;
            state.pending_operator = 0;
            state.replace_display = true;
            return false;
        }
        state.accumulator /= rhs;
        break;
    default:
        state.accumulator = rhs;
        break;
    }
    SetDisplay(state.display, state.accumulator);
    return true;
}

void AppendDigit(CalculatorState& state, wchar_t digit)
{
    std::wstring text = ReadDisplay(state.display);
    if (state.replace_display || text == L"Erro")
    {
        text.clear();
        state.replace_display = false;
    }
    if (digit == L'.')
    {
        if (text.find(L'.') != std::wstring::npos)
        {
            return;
        }
        if (text.empty())
        {
            text = L"0";
        }
    }
    if (text == L"0" && digit != L'.')
    {
        text.clear();
    }
    text.push_back(digit);
    SetWindowTextW(state.display, text.c_str());
}

void ResizeControls(HWND window, CalculatorState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const int margin = 12;
    const int gap = 8;
    const int display_height = 56;
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    MoveWindow(state.display, margin, margin, width - margin * 2, display_height, TRUE);

    const int top = margin + display_height + gap;
    const int grid_height = height - top - margin;
    const int cell_width = (width - margin * 2 - gap * 3) / 4;
    const int cell_height = (grid_height - gap * 4) / 5;
    for (int index = 0; index < 20; ++index)
    {
        HWND button = GetDlgItem(window, kButtonBaseId + index);
        if (button == nullptr)
        {
            continue;
        }
        const int row = index / 4;
        const int column = index % 4;
        MoveWindow(
            button,
            margin + column * (cell_width + gap),
            top + row * (cell_height + gap),
            cell_width,
            cell_height,
            TRUE);
    }
}

LRESULT CALLBACK CalculatorProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<CalculatorState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new CalculatorState();
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }

    switch (message)
    {
    case WM_CREATE:
    {
        state->display = CreateWindowExW(
            WS_EX_CLIENTEDGE,
            L"EDIT",
            L"0",
            WS_CHILD | WS_VISIBLE | ES_RIGHT | ES_READONLY | ES_AUTOHSCROLL,
            0, 0, 0, 0,
            window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDisplayId)),
            reinterpret_cast<LPCREATESTRUCTW>(l_param)->hInstance,
            nullptr);
        if (state->display == nullptr)
        {
            return -1;
        }

        HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        SendMessageW(state->display, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);

        constexpr std::array<const wchar_t*, 20> labels = {
            L"C", L"+/-", L"%", L"/",
            L"7", L"8", L"9", L"*",
            L"4", L"5", L"6", L"-",
            L"1", L"2", L"3", L"+",
            L"0", L".", L"<-", L"=",
        };
        for (int index = 0; index < static_cast<int>(labels.size()); ++index)
        {
            HWND button = CreateWindowExW(
                0,
                L"BUTTON",
                labels[static_cast<std::size_t>(index)],
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0,
                window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kButtonBaseId + index)),
                reinterpret_cast<LPCREATESTRUCTW>(l_param)->hInstance,
                nullptr);
            SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        }
        ResizeControls(window, *state);
        return 0;
    }

    case WM_SIZE:
        if (state != nullptr && state->display != nullptr)
        {
            ResizeControls(window, *state);
        }
        return 0;

    case WM_COMMAND:
        if (state != nullptr && HIWORD(w_param) == BN_CLICKED)
        {
            const int index = LOWORD(w_param) - kButtonBaseId;
            if (index < 0 || index >= 20)
            {
                break;
            }
            constexpr std::array<const wchar_t*, 20> labels = {
                L"C", L"+/-", L"%", L"/",
                L"7", L"8", L"9", L"*",
                L"4", L"5", L"6", L"-",
                L"1", L"2", L"3", L"+",
                L"0", L".", L"<-", L"=",
            };
            const std::wstring label = labels[static_cast<std::size_t>(index)];
            if (label.size() == 1 && ((label[0] >= L'0' && label[0] <= L'9') || label[0] == L'.'))
            {
                AppendDigit(*state, label[0]);
            }
            else if (label == L"C")
            {
                state->accumulator = 0.0;
                state->pending_operator = 0;
                state->replace_display = true;
                SetDisplayText(state->display, L"0");
            }
            else if (label == L"+/-")
            {
                SetDisplay(state->display, -DisplayValue(state->display));
            }
            else if (label == L"%")
            {
                SetDisplay(state->display, DisplayValue(state->display) / 100.0);
                state->replace_display = true;
            }
            else if (label == L"<-")
            {
                std::wstring text = ReadDisplay(state->display);
                if (!state->replace_display && text != L"Erro")
                {
                    if (!text.empty())
                    {
                        text.pop_back();
                    }
                    SetWindowTextW(state->display, text.empty() ? L"0" : text.c_str());
                }
            }
            else if (label == L"=")
            {
                if (ApplyPending(*state))
                {
                    state->pending_operator = 0;
                    state->replace_display = true;
                }
            }
            else
            {
                if (!state->replace_display || state->pending_operator == 0)
                {
                    if (!ApplyPending(*state))
                    {
                        return 0;
                    }
                }
                state->pending_operator = label[0];
                state->replace_display = true;
            }
            return 0;
        }
        break;

    case WM_KEYDOWN:
        if (state != nullptr)
        {
            if (w_param >= L'0' && w_param <= L'9')
            {
                AppendDigit(*state, static_cast<wchar_t>(w_param));
                return 0;
            }
            if (w_param == VK_RETURN)
            {
                if (ApplyPending(*state))
                {
                    state->pending_operator = 0;
                    state->replace_display = true;
                }
                return 0;
            }
            if (w_param == VK_ESCAPE)
            {
                state->accumulator = 0.0;
                state->pending_operator = 0;
                state->replace_display = true;
                SetDisplayText(state->display, L"0");
                return 0;
            }
        }
        break;

    case WM_DESTROY:
        delete state;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window, message, w_param, l_param);
}

bool EnsureCalculatorClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = CalculatorProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) != 0)
    {
        return true;
    }
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
}

HWND CloudOSNativeCalculatorWindow::Open(HINSTANCE instance)
{
    if (!EnsureCalculatorClass(instance))
    {
        return nullptr;
    }

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Calculadora - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        390,
        540,
        nullptr,
        nullptr,
        instance,
        nullptr);
    if (window != nullptr)
    {
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
    }
    return window;
}
