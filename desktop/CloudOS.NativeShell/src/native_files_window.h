#pragma once

#include <Windows.h>

#include <string>
#include <vector>

class CloudOSNativeFilesWindow final {
public:
    static void Open(
        HINSTANCE instance,
        const std::wstring& initial_path = L"");

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    struct Entry final {
        std::wstring name;
        std::wstring full_path;
        bool directory{};
        ULONGLONG size{};
    };

    explicit CloudOSNativeFilesWindow(
        HINSTANCE instance,
        std::wstring initial_path);
    ~CloudOSNativeFilesWindow() = default;

    CloudOSNativeFilesWindow(const CloudOSNativeFilesWindow&) = delete;
    CloudOSNativeFilesWindow& operator=(const CloudOSNativeFilesWindow&) = delete;

    bool Create();
    void Layout();
    void Navigate(const std::wstring& path);
    void NavigateParent();
    void NavigateWslRoot();
    void ActivateSelection();
    void PopulateList();
    std::wstring SelectedPath() const;
    static std::wstring ParentPath(const std::wstring& path);
    static std::wstring JoinPath(
        const std::wstring& directory,
        const std::wstring& name);
    static std::wstring FormatSize(ULONGLONG size);
    static bool IsRootPath(const std::wstring& path);

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND path_edit_{};
    HWND go_button_{};
    HWND up_button_{};
    HWND wsl_button_{};
    HWND list_{};

    std::wstring current_path_;
    std::vector<Entry> entries_;
};
