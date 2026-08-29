#pragma once

#include <Windows.h>

#include <string>
#include <vector>

class CloudOSNativeFilesWindow final
{
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
    struct Entry final
    {
        std::wstring name;
        std::wstring full_path;
        bool directory{};
        bool reparse_point{};
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
    void NavigateCloudOSDriveRoot();
    void OpenCloudOSDriveTrash();
    void ActivateSelection();
    void PopulateList();
    void PopulateCloudOSDriveList();
    void PopulateNativeFileSystemList();
    void CreateNewFolder();
    void DeleteSelection();
    void BeginRename();
    bool CommitRename(int row, const wchar_t* new_name);
    void Refresh();

    [[nodiscard]] bool IsCurrentCloudOSDrive() const;
    bool CurrentDriveSegments(
        std::vector<std::wstring>* segments,
        std::wstring* error = nullptr) const;
    [[nodiscard]] std::wstring SelectedPath() const;

    static std::wstring ParentPath(const std::wstring& path);
    static std::wstring JoinPath(
        const std::wstring& directory,
        const std::wstring& name);
    static std::wstring FormatSize(ULONGLONG size);
    static bool IsRootPath(const std::wstring& path);
    static bool IsWslRootPath(const std::wstring& path);

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND path_edit_{};
    HWND go_button_{};
    HWND up_button_{};
    HWND drive_button_{};
    HWND trash_button_{};
    HWND wsl_button_{};
    HWND refresh_button_{};
    HWND new_folder_button_{};
    HWND delete_button_{};
    HWND list_{};

    std::wstring current_path_;
    std::vector<Entry> entries_;
};
