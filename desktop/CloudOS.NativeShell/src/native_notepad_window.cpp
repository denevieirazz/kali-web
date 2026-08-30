#include "native_notepad_window.h"
#include "native_theme.h"

#include <windows.h>
#include <commdlg.h>
#include <algorithm>
#include <string>
#include <vector>

#pragma comment(lib, "comdlg32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.NativeNotepad.v1";
constexpr int kEditId = 100;
constexpr int kOpenId = 201;
constexpr int kSaveId = 202;
constexpr int kSaveAsId = 203;
constexpr int kClearId = 204;

struct NotepadState final
{
    HWND edit{};
    std::wstring current_path;
    HBRUSH background{CloudOS::WebSkin::CreateBackgroundBrush()};
    HBRUSH editor{CloudOS::WebSkin::CreateEditBrush()};
    HFONT ui_font{};
    HFONT editor_font{};
};

std::wstring PickFile(HWND owner, bool save)
{
    wchar_t buffer[MAX_PATH * 4]{};
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = owner;
    dialog.lpstrFile = buffer;
    dialog.nMaxFile = static_cast<DWORD>(std::size(buffer));
    dialog.lpstrFilter = L"Arquivos de texto\0*.txt;*.log;*.md;*.json;*.csv;*.cpp;*.h\0Todos os arquivos\0*.*\0\0";
    dialog.nFilterIndex = 1;
    dialog.Flags = OFN_EXPLORER | OFN_PATHMUSTEXIST | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    dialog.lpstrDefExt = L"txt";
    const BOOL ok = save ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog);
    return ok ? std::wstring(buffer) : std::wstring{};
}

bool ReadAllText(const std::wstring& path, std::wstring& output)
{
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > 32LL * 1024LL * 1024LL)
    {
        CloseHandle(file);
        return false;
    }

    std::vector<char> bytes(static_cast<std::size_t>(size.QuadPart));
    DWORD read = 0;
    const BOOL read_ok = bytes.empty() || ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr);
    CloseHandle(file);
    if (!read_ok) return false;
    bytes.resize(read);

    if (bytes.size() >= 2 && static_cast<unsigned char>(bytes[0]) == 0xFF && static_cast<unsigned char>(bytes[1]) == 0xFE)
    {
        const wchar_t* text = reinterpret_cast<const wchar_t*>(bytes.data() + 2);
        const std::size_t chars = (bytes.size() - 2) / sizeof(wchar_t);
        output.assign(text, text + chars);
        return true;
    }

    int chars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    UINT code_page = CP_UTF8;
    DWORD flags = MB_ERR_INVALID_CHARS;
    if (chars <= 0)
    {
        code_page = CP_ACP;
        flags = 0;
        chars = MultiByteToWideChar(code_page, flags, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    }
    if (chars < 0) return false;
    output.resize(static_cast<std::size_t>(chars));
    if (chars > 0)
        MultiByteToWideChar(code_page, flags, bytes.data(), static_cast<int>(bytes.size()), output.data(), chars);
    return true;
}

bool WriteAllTextUtf8(const std::wstring& path, const std::wstring& text)
{
    const int bytes_required = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (bytes_required < 0) return false;
    std::vector<char> bytes(static_cast<std::size_t>(bytes_required));
    if (bytes_required > 0)
        WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), bytes.data(), bytes_required, nullptr, nullptr);

    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const BOOL ok = bytes.empty() || WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
    CloseHandle(file);
    return ok && static_cast<std::size_t>(written) == bytes.size();
}

std::wstring ReadEditText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    if (length > 0) GetWindowTextW(edit, text.data(), length + 1);
    text.resize(static_cast<std::size_t>(length));
    return text;
}

void UpdateTitle(HWND window, const NotepadState& state)
{
    if (state.current_path.empty())
    {
        SetWindowTextW(window, L"Bloco de Notas - CloudOS");
        return;
    }
    const std::size_t separator = state.current_path.find_last_of(L"\\/");
    const std::wstring name = separator == std::wstring::npos ? state.current_path : state.current_path.substr(separator + 1);
    SetWindowTextW(window, (name + L" - Bloco de Notas - CloudOS").c_str());
}

void Layout(HWND window, NotepadState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const UINT dpi = GetDpiForWindow(window);
    const int margin = CloudOS::Scale(14, dpi);
    const int toolbar_height = CloudOS::Scale(38, dpi);
    const int gap = CloudOS::Scale(8, dpi);
    int left = margin;
    const struct ButtonDef { int id; const wchar_t* text; int width; } buttons[] = {
        {kOpenId, L"Abrir", 86}, {kSaveId, L"Salvar", 86}, {kSaveAsId, L"Salvar como", 120}, {kClearId, L"Limpar", 86},
    };
    for (const auto& button : buttons)
    {
        HWND control = GetDlgItem(window, button.id);
        if (control != nullptr)
        {
            const int scaled = CloudOS::Scale(button.width, dpi);
            MoveWindow(control, left, margin, scaled, toolbar_height, TRUE);
            left += scaled + gap;
        }
    }
    if (state.edit != nullptr)
    {
        const int client_width = static_cast<int>(client.right - client.left);
        const int client_height = static_cast<int>(client.bottom - client.top);
        const int edit_width = std::max(0, client_width - margin * 2);
        const int edit_height = std::max(0, client_height - (margin * 2 + toolbar_height + gap));
        MoveWindow(state.edit, margin, margin + toolbar_height + gap, edit_width, edit_height, TRUE);
    }
}

bool Save(HWND window, NotepadState& state, bool force_picker)
{
    std::wstring path = state.current_path;
    if (force_picker || path.empty())
    {
        path = PickFile(window, true);
        if (path.empty()) return false;
    }
    const std::wstring text = ReadEditText(state.edit);
    if (!WriteAllTextUtf8(path, text))
    {
        MessageBoxW(window, L"Nao foi possivel salvar o arquivo.", L"CloudOS", MB_OK | MB_ICONERROR);
        return false;
    }
    state.current_path = path;
    UpdateTitle(window, state);
    return true;
}

LRESULT CALLBACK NotepadProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<NotepadState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new NotepadState();
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }

    switch (message)
    {
    case WM_CREATE:
    {
        const auto* create = reinterpret_cast<LPCREATESTRUCTW>(l_param);
        const UINT dpi = GetDpiForWindow(window);
        state->ui_font = CreateFontW(-CloudOS::Scale(14, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
        state->editor_font = CreateFontW(-CloudOS::Scale(14, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            FIXED_PITCH | FF_MODERN, L"Cascadia Mono");

        const struct ButtonDef { int id; const wchar_t* text; } buttons[] = {
            {kOpenId, L"Abrir"}, {kSaveId, L"Salvar"}, {kSaveAsId, L"Salvar como"}, {kClearId, L"Limpar"},
        };
        for (const auto& button : buttons)
        {
            HWND control = CreateWindowExW(0, L"BUTTON", button.text,
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(button.id)), create->hInstance, nullptr);
            SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(state->ui_font), TRUE);
            CloudOS::WebSkin::PrepareButton(control);
        }

        state->edit = CreateWindowExW(
            0, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL | ES_LEFT | ES_MULTILINE |
                ES_AUTOVSCROLL | ES_AUTOHSCROLL | ES_WANTRETURN,
            0, 0, 0, 0, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEditId)), create->hInstance, nullptr);
        SendMessageW(state->edit, WM_SETFONT, reinterpret_cast<WPARAM>(state->editor_font), TRUE);
        SendMessageW(state->edit, EM_SETLIMITTEXT, 32u * 1024u * 1024u, 0);
        CloudOS::WebSkin::PrepareEdit(state->edit);
        Layout(window, *state);
        SetFocus(state->edit);
        return 0;
    }
    case WM_SIZE:
        if (state != nullptr) Layout(window, *state);
        return 0;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr)
        {
            const auto tone = draw->CtlID == kSaveId
                ? CloudOS::ButtonTone::Accent
                : (draw->CtlID == kClearId ? CloudOS::ButtonTone::Danger : CloudOS::ButtonTone::Neutral);
            if (CloudOS::WebSkin::PaintOwnerDrawButton(draw, tone)) return TRUE;
        }
        break;
    }
    case WM_CTLCOLOREDIT:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, CloudOS::WebSkin::TextPrimary);
        SetBkColor(dc, CloudOS::WebSkin::BgTertiary);
        return reinterpret_cast<LRESULT>(state->editor);
    }
    case WM_ERASEBKGND:
    {
        RECT client{}; GetClientRect(window, &client);
        CloudOS::WebSkin::PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_COMMAND:
        if (state == nullptr) break;
        switch (LOWORD(w_param))
        {
        case kOpenId:
        {
            const std::wstring path = PickFile(window, false);
            if (path.empty()) return 0;
            std::wstring text;
            if (!ReadAllText(path, text))
            {
                MessageBoxW(window, L"Nao foi possivel abrir o arquivo.", L"CloudOS", MB_OK | MB_ICONERROR);
                return 0;
            }
            SetWindowTextW(state->edit, text.c_str());
            state->current_path = path;
            UpdateTitle(window, *state);
            return 0;
        }
        case kSaveId: Save(window, *state, false); return 0;
        case kSaveAsId: Save(window, *state, true); return 0;
        case kClearId:
            SetWindowTextW(state->edit, L"");
            state->current_path.clear();
            UpdateTitle(window, *state);
            return 0;
        default: break;
        }
        break;
    case WM_CLOSE:
        DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        if (state != nullptr)
        {
            if (state->background != nullptr) DeleteObject(state->background);
            if (state->editor != nullptr) DeleteObject(state->editor);
            if (state->ui_font != nullptr) DeleteObject(state->ui_font);
            if (state->editor_font != nullptr) DeleteObject(state->editor_font);
        }
        delete state;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        return 0;
    default: break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

bool EnsureNotepadClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = NotepadProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_IBEAM);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) != 0) return true;
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
}

HWND CloudOSNativeNotepadWindow::Open(HINSTANCE instance)
{
    if (!EnsureNotepadClass(instance)) return nullptr;
    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW, kClassName, L"Bloco de Notas - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 880, 660,
        nullptr, nullptr, instance, nullptr);
    if (window != nullptr)
    {
        CloudOS::ApplyWebWindowMaterial(window);
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
    }
    return window;
}
