#pragma once

#include <Windows.h>

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

class CloudOSNativeAppsWindow final
{
public:
    enum class AppKind
    {
        External,
        InstalledWindows,
        LinuxGui,
        Calculator,
        Notepad,
        Settings,
        SystemMonitor,
        EnvDoctor,
    };

    struct AppEntry final
    {
        std::wstring name;
        std::wstring path;
        AppKind kind{AppKind::External};
        std::wstring platform{L"Windows"};
        std::wstring source;
        std::wstring uninstall_command;
        std::wstring distro;
        std::wstring desktop_id;
        std::wstring package_manager;
        std::wstring package_id;
        bool can_launch{true};
        bool can_uninstall{};
    };

    static void Open(HINSTANCE instance);
    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    explicit CloudOSNativeAppsWindow(HINSTANCE instance);
    ~CloudOSNativeAppsWindow() = default;

    CloudOSNativeAppsWindow(const CloudOSNativeAppsWindow&) = delete;
    CloudOSNativeAppsWindow& operator=(const CloudOSNativeAppsWindow&) = delete;

    bool Create();
    void Layout();
    void LoadCatalog();
    void EnumerateFolder(const std::wstring& folder, int depth);
    void ApplyFilter();
    void LaunchSelection();
    void UpdateSelection();
    void UninstallSelection();
    void InstallFromSearch();
    void RefreshCatalog();
    void UpdateActionState();

    static std::wstring ReadText(HWND edit);
    static bool ContainsInsensitive(
        std::wstring_view text,
        std::wstring_view query);

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND search_edit_{};
    HWND list_{};
    HWND launch_button_{};
    HWND install_button_{};
    HWND update_button_{};
    HWND uninstall_button_{};
    HWND refresh_button_{};
    std::vector<AppEntry> catalog_;
    std::vector<std::size_t> visible_indices_;
};
