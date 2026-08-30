#pragma once

#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <filesystem>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")

namespace CloudOS
{
class NativeShellContextMenuV7 final
{
public:
    static bool Show(HWND owner, const std::vector<std::wstring>& paths, POINT screen_point)
    {
        if (owner == nullptr || paths.empty() || paths.size() > 128u) return false;

        const std::filesystem::path expected_parent =
            std::filesystem::path(paths.front()).parent_path();
        std::vector<PIDLIST_ABSOLUTE> absolute_pidls;
        std::vector<PCUITEMID_CHILD> child_pidls;
        absolute_pidls.reserve(paths.size());
        child_pidls.reserve(paths.size());

        IShellFolder* parent_folder = nullptr;
        for (const std::wstring& path : paths)
        {
            if (std::filesystem::path(path).parent_path() != expected_parent)
            {
                Cleanup(absolute_pidls, parent_folder);
                return false;
            }

            PIDLIST_ABSOLUTE absolute = nullptr;
            if (FAILED(SHParseDisplayName(path.c_str(), nullptr, &absolute, 0, nullptr)) || absolute == nullptr)
            {
                Cleanup(absolute_pidls, parent_folder);
                return false;
            }

            IShellFolder* current_parent = nullptr;
            PCUITEMID_CHILD child = nullptr;
            if (FAILED(SHBindToParent(
                    absolute,
                    IID_PPV_ARGS(&current_parent),
                    &child)) || current_parent == nullptr || child == nullptr)
            {
                CoTaskMemFree(absolute);
                Cleanup(absolute_pidls, parent_folder);
                return false;
            }

            if (parent_folder == nullptr)
            {
                parent_folder = current_parent;
            }
            else
            {
                current_parent->Release();
            }
            absolute_pidls.push_back(absolute);
            child_pidls.push_back(child);
        }

        IContextMenu* context_menu = nullptr;
        const HRESULT object_result = parent_folder->GetUIObjectOf(
            owner,
            static_cast<UINT>(child_pidls.size()),
            child_pidls.data(),
            IID_IContextMenu,
            nullptr,
            reinterpret_cast<void**>(&context_menu));
        if (FAILED(object_result) || context_menu == nullptr)
        {
            Cleanup(absolute_pidls, parent_folder);
            return false;
        }

        HMENU menu = CreatePopupMenu();
        if (menu == nullptr)
        {
            context_menu->Release();
            Cleanup(absolute_pidls, parent_folder);
            return false;
        }

        constexpr UINT kFirstCommand = 1u;
        constexpr UINT kLastCommand = 0x7FFFu;
        const HRESULT query_result = context_menu->QueryContextMenu(
            menu,
            0,
            kFirstCommand,
            kLastCommand,
            CMF_NORMAL | CMF_EXPLORE);
        if (FAILED(query_result))
        {
            DestroyMenu(menu);
            context_menu->Release();
            Cleanup(absolute_pidls, parent_folder);
            return false;
        }

        MenuMessageBridge bridge{};
        bridge.context_menu = context_menu;
        (void)context_menu->QueryInterface(IID_PPV_ARGS(&bridge.context_menu3));
        if (bridge.context_menu3 == nullptr)
            (void)context_menu->QueryInterface(IID_PPV_ARGS(&bridge.context_menu2));

        constexpr UINT_PTR kSubclassId = 0xC10D7C01u;
        (void)SetWindowSubclass(
            owner,
            &NativeShellContextMenuV7::MenuSubclass,
            kSubclassId,
            reinterpret_cast<DWORD_PTR>(&bridge));

        SetForegroundWindow(owner);
        const UINT command = TrackPopupMenuEx(
            menu,
            TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_LEFTALIGN,
            screen_point.x,
            screen_point.y,
            owner,
            nullptr);

        RemoveWindowSubclass(owner, &NativeShellContextMenuV7::MenuSubclass, kSubclassId);
        PostMessageW(owner, WM_NULL, 0, 0);

        bool invoked = false;
        if (command >= kFirstCommand && command <= kLastCommand)
        {
            CMINVOKECOMMANDINFOEX info{};
            info.cbSize = sizeof(info);
            info.fMask = CMIC_MASK_UNICODE | CMIC_MASK_PTINVOKE;
            info.hwnd = owner;
            info.lpVerb = MAKEINTRESOURCEA(command - kFirstCommand);
            info.lpVerbW = MAKEINTRESOURCEW(command - kFirstCommand);
            info.nShow = SW_SHOWNORMAL;
            info.ptInvoke = screen_point;
            invoked = SUCCEEDED(context_menu->InvokeCommand(
                reinterpret_cast<LPCMINVOKECOMMANDINFO>(&info)));
        }

        if (bridge.context_menu3 != nullptr) bridge.context_menu3->Release();
        if (bridge.context_menu2 != nullptr) bridge.context_menu2->Release();
        DestroyMenu(menu);
        context_menu->Release();
        Cleanup(absolute_pidls, parent_folder);
        return invoked || command == 0u;
    }

private:
    struct MenuMessageBridge final
    {
        IContextMenu* context_menu{};
        IContextMenu2* context_menu2{};
        IContextMenu3* context_menu3{};
    };

    static void Cleanup(
        std::vector<PIDLIST_ABSOLUTE>& pidls,
        IShellFolder* parent_folder) noexcept
    {
        for (PIDLIST_ABSOLUTE pidl : pidls)
            if (pidl != nullptr) CoTaskMemFree(pidl);
        pidls.clear();
        if (parent_folder != nullptr) parent_folder->Release();
    }

    static LRESULT CALLBACK MenuSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR,
        DWORD_PTR reference)
    {
        auto* bridge = reinterpret_cast<MenuMessageBridge*>(reference);
        if (bridge != nullptr)
        {
            switch (message)
            {
            case WM_INITMENUPOPUP:
            case WM_DRAWITEM:
            case WM_MEASUREITEM:
            case WM_MENUCHAR:
                if (bridge->context_menu3 != nullptr)
                {
                    LRESULT result = 0;
                    if (SUCCEEDED(bridge->context_menu3->HandleMenuMsg2(
                            message,
                            w_param,
                            l_param,
                            &result)))
                        return result;
                }
                else if (bridge->context_menu2 != nullptr)
                {
                    if (SUCCEEDED(bridge->context_menu2->HandleMenuMsg(
                            message,
                            w_param,
                            l_param)))
                        return 0;
                }
                break;
            default:
                break;
            }
        }
        return DefSubclassProc(window, message, w_param, l_param);
    }
};
} // namespace CloudOS
