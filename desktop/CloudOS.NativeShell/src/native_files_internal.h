#pragma once

#include "native_files_window.h"
#include "native_theme.h"

#include <Windows.h>
#include <CommCtrl.h>
#include <string>

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Files.v4";
constexpr int kSidebarId = 1200;
constexpr int kBackId = 1201;
constexpr int kForwardId = 1202;
constexpr int kUpId = 1203;
constexpr int kPathId = 1204;
constexpr int kGoId = 1205;
constexpr int kRefreshId = 1206;
constexpr int kNewFolderId = 1207;
constexpr int kRenameId = 1208;
constexpr int kDeleteId = 1209;
constexpr int kListId = 1210;
constexpr int kShellHostId = 1211;
constexpr int kStatusId = 1212;

constexpr COLORREF kBg = RGB(8, 12, 22);
constexpr COLORREF kPanel = RGB(13, 20, 34);
constexpr COLORREF kSurface = RGB(18, 27, 45);
constexpr COLORREF kHot = RGB(29, 45, 72);
constexpr COLORREF kBorder = RGB(48, 68, 98);
constexpr COLORREF kAccent = RGB(80, 151, 239);
constexpr COLORREF kText = RGB(237, 243, 252);
constexpr COLORREF kMuted = RGB(148, 166, 193);

constexpr UINT_PTR kAddressSubclassId = 0xC10D;

inline LRESULT CALLBACK AddressEditSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR,
    DWORD_PTR)
{
    if (message == WM_KEYDOWN)
    {
        if (w_param == VK_RETURN)
        {
            HWND parent = GetParent(window);
            if (parent != nullptr)
            {
                SendMessageW(parent, WM_COMMAND, MAKEWPARAM(kGoId, BN_CLICKED), reinterpret_cast<LPARAM>(window));
            }
            return 0;
        }
        if (w_param == VK_ESCAPE)
        {
            HWND parent = GetParent(window);
            if (parent != nullptr)
            {
                SetFocus(parent);
            }
            return 0;
        }
    }
    if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, AddressEditSubclass, kAddressSubclassId);
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

inline bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &CloudOSNativeFilesWindow::WindowProcedure;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
    wc.lpszClassName = kClassName;
    return RegisterClassExW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

inline HWND CreateButton(HINSTANCE instance, HWND parent, const wchar_t* text, int id)
{
    return CreateWindowExW(
        0, L"BUTTON", text,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, parent,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), instance, nullptr);
}

inline bool DirectoryExists(const std::wstring& path)
{
    const DWORD attributes = path.empty() ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

inline bool StartsWithInsensitive(const std::wstring& value, const std::wstring& prefix)
{
    return !prefix.empty() && value.size() >= prefix.size() &&
        _wcsnicmp(value.c_str(), prefix.c_str(), prefix.size()) == 0;
}

inline void ShowError(HWND owner, const wchar_t* message, const std::wstring& detail = {})
{
    std::wstring text(message == nullptr ? L"Operacao indisponivel." : message);
    if (!detail.empty())
    {
        text += L"\n\n";
        text += detail;
    }
    MessageBoxW(owner, text.c_str(), L"Arquivos - CloudOS", MB_OK | MB_ICONWARNING);
}
}
