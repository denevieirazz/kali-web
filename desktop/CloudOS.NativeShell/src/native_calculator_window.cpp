#include "native_calculator_window.h"
#include "native_theme.h"

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
    HBRUSH background{CloudOS::WebSkin::CreateBackgroundBrush()};
    HBRUSH edit{CloudOS::WebSkin::CreateEditBrush()};
    HFONT ui_font{};
    HFONT display_font{};
};

std::wstring ReadDisplay(HWND display)
{
    const int length = GetWindowTextLengthW(display);
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    if (length > 0) GetWindowTextW(display, text.data(), length + 1);
    text.resize(length > 0 ? static_cast<std::size_t>(length) : 0u);
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

void SetDisplayText(HWND display, const wchar_t* value) { SetWindowTextW(display, value); }

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
    default: state.accumulator = rhs; break;
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
        if (text.find(L'.') != std::wstring::npos) return;
        if (text.empty()) text = L"0";
    }
    if (text == L"0" && digit != L'.') text.clear();
    text.push_back(digit);
    SetWindowTextW(state.display, text.c_str());
}

void ResizeControls(HWND window, CalculatorState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const UINT dpi = GetDpiForWindow(window);
    const int margin = CloudOS::Scale(18, dpi);
    const int gap = CloudOS::Scale(9, dpi);
    const int display_height = CloudOS::Scale(78, dpi);
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
        if (button != nullptr)
        {
            const int row = index / 4;
            const int column = index % 4;
            MoveWindow(button, margin + column * (cell_width + gap), top + row * (cell_height + gap),
                cell_width, cell_height, TRUE);
        }
    }
}

CloudOS::ButtonTone ButtonToneFor(int index)
{
    if (index == 19) return CloudOS::ButtonTone::Accent;
    if (index == 0) return CloudOS::ButtonTone::Danger;
    if (index == 3 || index == 7 || index == 11 || index == 15) return CloudOS::ButtonTone::Accent;
    return CloudOS::ButtonTone::Neutral;
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
        const UINT dpi = GetDpiForWindow(window);
        state->ui_font = CreateFontW(-CloudOS::Scale(16, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
        state->display_font = CreateFontW(-CloudOS::Scale(32, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

        state->display = CreateWindowExW(
            0, L"EDIT", L"0",
            WS_CHILD | WS_VISIBLE | ES_RIGHT | ES_READONLY | ES_AUTOHSCROLL,
            0, 0, 0, 0, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDisplayId)),
            reinterpret_cast<LPCREATESTRUCTW>(l_param)->hInstance, nullptr);
        if (state->display == nullptr) return -1;
        SendMessageW(state->display, WM_SETFONT, reinterpret_cast<WPARAM>(state->display_font), TRUE);
        CloudOS::WebSkin::PrepareEdit(state->display);

        constexpr std::array<const wchar_t*, 20> labels = {
            L"C", L"+/-", L"%", L"/", L"7", L"8", L"9", L"*", L"4", L"5", L"6", L"-",
            L"1", L"2", L"3", L"+", L"0", L".", L"<-", L"=",
        };
        for (int index = 0; index < static_cast<int>(labels.size()); ++index)
        {
            HWND button = CreateWindowExW(0, L"BUTTON", labels[static_cast<std::size_t>(index)],
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kButtonBaseId + index)),
                reinterpret_cast<LPCREATESTRUCTW>(l_param)->hInstance, nullptr);
            SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(state->ui_font), TRUE);
            CloudOS::WebSkin::PrepareButton(button);
        }
        ResizeControls(window, *state);
        return 0;
    }
    case WM_SIZE:
        if (state != nullptr && state->display != nullptr) ResizeControls(window, *state);
        return 0;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr && draw->CtlID >= kButtonBaseId && draw->CtlID < kButtonBaseId + 20)
        {
            if (CloudOS::WebSkin::PaintOwnerDrawButton(draw, ButtonToneFor(static_cast<int>(draw->CtlID) - kButtonBaseId)))
                return TRUE;
        }
        break;
    }
    case WM_CTLCOLOREDIT:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, CloudOS::WebSkin::TextPrimary);
        SetBkColor(dc, CloudOS::WebSkin::BgTertiary);
        return reinterpret_cast<LRESULT>(state->edit);
    }
    case WM_ERASEBKGND:
    {
        RECT client{}; GetClientRect(window, &client);
        CloudOS::WebSkin::PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_COMMAND:
        if (state != nullptr && HIWORD(w_param) == BN_CLICKED)
        {
            const int index = LOWORD(w_param) - kButtonBaseId;
            if (index < 0 || index >= 20) break;
            constexpr std::array<const wchar_t*, 20> labels = {
                L"C", L"+/-", L"%", L"/", L"7", L"8", L"9", L"*", L"4", L"5", L"6", L"-",
                L"1", L"2", L"3", L"+", L"0", L".", L"<-", L"=",
            };
            const std::wstring label = labels[static_cast<std::size_t>(index)];
            if (label.size() == 1 && ((label[0] >= L'0' && label[0] <= L'9') || label[0] == L'.'))
                AppendDigit(*state, label[0]);
            else if (label == L"C")
            {
                state->accumulator = 0.0; state->pending_operator = 0; state->replace_display = true;
                SetDisplayText(state->display, L"0");
            }
            else if (label == L"+/-") SetDisplay(state->display, -DisplayValue(state->display));
            else if (label == L"%") { SetDisplay(state->display, DisplayValue(state->display) / 100.0); state->replace_display = true; }
            else if (label == L"<-")
            {
                std::wstring text = ReadDisplay(state->display);
                if (!state->replace_display && text != L"Erro")
                {
                    if (!text.empty()) text.pop_back();
                    SetWindowTextW(state->display, text.empty() ? L"0" : text.c_str());
                }
            }
            else if (label == L"=")
            {
                if (ApplyPending(*state)) { state->pending_operator = 0; state->replace_display = true; }
            }
            else
            {
                if (!state->replace_display || state->pending_operator == 0)
                {
                    if (!ApplyPending(*state)) return 0;
                }
                state->pending_operator = label[0]; state->replace_display = true;
            }
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if (state != nullptr)
        {
            if (w_param >= L'0' && w_param <= L'9') { AppendDigit(*state, static_cast<wchar_t>(w_param)); return 0; }
            if (w_param == VK_RETURN)
            {
                if (ApplyPending(*state)) { state->pending_operator = 0; state->replace_display = true; }
                return 0;
            }
            if (w_param == VK_ESCAPE)
            {
                state->accumulator = 0.0; state->pending_operator = 0; state->replace_display = true;
                SetDisplayText(state->display, L"0"); return 0;
            }
        }
        break;
    case WM_DESTROY:
        if (state != nullptr)
        {
            if (state->background != nullptr) DeleteObject(state->background);
            if (state->edit != nullptr) DeleteObject(state->edit);
            if (state->ui_font != nullptr) DeleteObject(state->ui_font);
            if (state->display_font != nullptr) DeleteObject(state->display_font);
        }
        delete state;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        return 0;
    default: break;
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
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) != 0) return true;
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
}

HWND CloudOSNativeCalculatorWindow::Open(HINSTANCE instance)
{
    if (!EnsureCalculatorClass(instance)) return nullptr;
    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW, kClassName, L"Calculadora - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 420, 600,
        nullptr, nullptr, instance, nullptr);
    if (window != nullptr)
    {
        CloudOS::ApplyWebWindowMaterial(window);
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
    }
    return window;
}
