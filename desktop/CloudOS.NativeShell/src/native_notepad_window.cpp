#include "native_notepad_window.h"

#include <windows.h>
#include <commdlg.h>
#include <algorithm>
#include <fstream>
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
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return false;
    }

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
    if (!read_ok)
    {
        return false;
    }
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
    if (chars < 0)
    {
        return false;
    }
    output.resize(static_cast<std::size_t>(chars));
    if (chars > 0)
    {
        MultiByteToWideChar(code_page, flags, bytes.data(), static_cast<int>(bytes.size()), output.data(), chars);
    }
    return true;
}

bool WriteAllTextUtf8(const std::wstring& path, const std::wstring& text)
{
    int bytes_required = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (bytes_required < 0)
    {
        return false;
    }
    std::vector<char> bytes(static_cast<std::size_t>(bytes_required));
    if (bytes_required > 0)
    {
        WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), bytes.data(), bytes_required, nullptr, nullptr);
    }

    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return false;
    }
    DWORD written = 0;
    const BOOL ok = bytes.empty() || WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
    CloseHandle(file);
    return ok && written == bytes.size();
}

std::wstring ReadEditText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    if (length > 0)
    {
        GetWindowTextW(edit, text.data(), length + 1);
    }
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
    const std::wstring title = name + L" - Bloco de Notas - CloudOS";
    SetWindowTextW(window, title.c_str());
}

void Layout(HWND window, NotepadState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const int margin = 8;
    const int toolbar_height = 34;
    const int gap = 6;
    int left = margin;
    const struct ButtonDef { int id; const wchar_t* text; int width; } buttons[] = {
        {kOpenId, L"Abrir", 82},
        {kSaveId, L"Salvar", 82},
        {kSaveAsId, L"Salvar como", 112},
        {kClearId, L"Limpar", 82},
    };
    for (const auto& button : buttons)
    {
        HWND control = GetDlgItem(window, button.id);
        if (control != nullptr)
        {
            MoveWindow(control, left, margin, button.width, toolbar_height, TRUE);
            left += button.width + gap;
        }
    }
    if (state.edit != nullptr)
    {
        MoveWindow(
            state.edit,
            margin,
            margin + toolbar_height + gap,
            std::max(0, client.right - margin * 2),
            std::max(0, client.bottom - (margin * 2 + toolbar_height + gap)),
            TRUE);
    }
}

bool Save(HWND window, NotepadState& state, bool force_picker)
{
    std::wstring path = state.current_path;
    if (force_picker || path.empty())
    {
        path = PickFile(window, true);
        if (path.empty())
        {
            return false;
        }
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
        HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        const struct ButtonDef { int id; const wchar_t* text; } buttons[] = {
            {kOpenId, L"Abrir"},
            {kSaveId, L"Salvar"},
            {kSaveAsId, L"Salvar como"},
            {kClearId, L"Limpar"},
        };
        for (const auto& button : buttons)
        {
            HWND control = CreateWindowExW(
                0,
                L"BUTTON",
                button.text,
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0,
                window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(button.id)),
                create->hInstance,
                nullptr);
            SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        }

        state->edit = CreateWindowExW(
            WS_EX_CLIENTEDGE,
            L"EDIT",
            L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL | ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL | ES_WANTRETURN,
            0, 0, 0, 0,
            window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEditId)),
            create->hInstance,
            nullptr);
        SendMessageW(state->edit, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(ANSI_FIXED_FONT)), TRUE);
        SendMessageW(state->edit, EM_SETLIMITTEXT, 32u * 1024u * 1024u, 0);
        Layout(window, *state);
        SetFocus(state->edit);
        return 0;
    }

    case WM_SIZE:
        if (state != nullptr)
        {
            Layout(window, *state);
        }
        return 0;

    case WM_COMMAND:
        if (state == nullptr)
        {
            break;
        }
        switch (LOWORD(w_param))
        {
        case kOpenId:
        {
            const std::wstring path = PickFile(window, false);
            if (path.empty())
            {
                return 0;
            }
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
        case kSaveId:
            Save(window, *state, false);
            return 0;
        case kSaveAsId:
            Save(window, *state, true);
            return 0;
        case kClearId:
            SetWindowTextW(state->edit, L"");
            state->current_path.clear();
            UpdateTitle(window, *state);
            return 0;
        default:
            break;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window);
        return 0;

    case WM_DESTROY:
        delete state;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        return 0;

    default:
        break;
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
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) != 0)
    {
        return true;
    }
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
}

HWND CloudOSNativeNotepadWindow::Open(HINSTANCE instance)
{
    if (!EnsureNotepadClass(instance))
    {
        return nullptr;
    }

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Bloco de Notas - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        840,
        620,
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
