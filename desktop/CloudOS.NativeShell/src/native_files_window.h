#pragma once

#include "native_file_preview.h"
#include "native_files_state.h"
#include "native_shell_context_menu_v7.h"
#include "native_shell_view_host.h"

#include <Windows.h>
#include <CommCtrl.h>
#include <Shellapi.h>

#include <cstddef>
#include <string>
#include <vector>

class CloudOSNativeFilesWindow final
{
public:
    static void Open(HINSTANCE instance, const std::wstring& initial_path = L"");
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

private:
    enum class ContentMode { Shell, CloudOSDrive, FallbackFileSystem };

    struct Entry final
    {
        std::wstring name;
        std::wstring full_path;
        bool directory{};
        bool reparse_point{};
        ULONGLONG size{};
        FILETIME modified{};
        int image_index{-1};
    };

    struct SidebarItem final
    {
        std::wstring label;
        std::wstring path;
        bool opens_trash{};
        bool favorite{};
        int image_index{-1};
    };

    struct TabState final
    {
        std::wstring path;
        std::vector<std::wstring> back;
        std::vector<std::wstring> forward;
    };

    explicit CloudOSNativeFilesWindow(HINSTANCE instance, std::wstring initial_path);
    ~CloudOSNativeFilesWindow() = default;
    CloudOSNativeFilesWindow(const CloudOSNativeFilesWindow&) = delete;
    CloudOSNativeFilesWindow& operator=(const CloudOSNativeFilesWindow&) = delete;

    bool Create();
    bool CreateControls();
    void CreateUiResources();
    void CreateFonts();
    void ApplyFonts();
    void DestroyFonts() noexcept;
    void DestroyUiResources() noexcept;
    void ConfigureLists();
    void BuildSidebar();
    void Layout();
    void UpdateStatus();
    void PaintChrome(HDC dc, const RECT& client);

    void LoadV5State();
    void PersistV5State() noexcept;
    void SyncTabStrip();
    void NewTab();
    void CloseActiveTab();
    void SelectTab(std::size_t index);
    void CommitNavigatedPath(const std::wstring& path);
    void ToggleFavorite();
    void TogglePreview();
    void OpenSearch();
    void OpenOperations();
    void RefreshPreview();
    void ShowContentContextMenu(POINT screen_point);
    [[nodiscard]] std::vector<std::wstring> SelectedPaths() const;

    void Navigate(const std::wstring& path);
    bool NavigateShell(const std::wstring& path);
    void NavigateCloudOSDrive(const std::wstring& path);
    void NavigateFallback(const std::wstring& path);
    void NavigateBack();
    void NavigateForward();
    void NavigateParent();
    void OnShellNavigationComplete(const std::wstring& path);
    void SelectSidebarForCurrentPath();
    void ActivateSidebarSelection();

    void PopulateCustomList();
    void PopulateCloudOSDriveList();
    void PopulateFallbackList();
    void RenderCustomList();
    void ActivateCustomSelection();
    void CreateNewFolder();
    void BeginRename();
    bool CommitRename(int row, const wchar_t* new_name);
    void DeleteSelection();
    void Refresh();

    [[nodiscard]] bool IsCurrentCloudOSDrive() const;
    bool CurrentDriveSegments(std::vector<std::wstring>* segments, std::wstring* error = nullptr) const;
    [[nodiscard]] int ShellIconIndex(const std::wstring& path, bool directory, bool use_attributes = false) const;
    [[nodiscard]] int AddSidebarIcon(const std::wstring& path, SHSTOCKICONID fallback_icon);

    static std::wstring KnownFolderPath(REFKNOWNFOLDERID folder_id);
    static std::wstring JoinPath(const std::wstring& directory, const std::wstring& name);
    static std::wstring ParentPath(const std::wstring& path);
    static std::wstring ReadEditText(HWND edit);
    static std::wstring FormatSize(ULONGLONG size);
    static std::wstring FormatModified(const FILETIME& value);
    static std::wstring LeafName(const std::wstring& path);
    static bool PathsEqual(const std::wstring& left, const std::wstring& right) noexcept;
    static bool IsWslRootPath(const std::wstring& path);
    static bool IsRootPath(const std::wstring& path);
    static bool IsSafeLeafName(const wchar_t* text);

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);
    LRESULT DrawOwnerButton(const DRAWITEMSTRUCT& item);
    LRESULT CustomDrawSidebar(const NMLVCUSTOMDRAW& draw);

    HINSTANCE instance_{};
    HWND window_{};
    HWND sidebar_{};
    HWND tab_strip_{};
    HWND new_tab_button_{};
    HWND close_tab_button_{};
    HWND back_button_{};
    HWND forward_button_{};
    HWND up_button_{};
    HWND path_edit_{};
    HWND go_button_{};
    HWND refresh_button_{};
    HWND favorite_button_{};
    HWND search_edit_{};
    HWND search_button_{};
    HWND preview_button_{};
    HWND new_folder_button_{};
    HWND rename_button_{};
    HWND delete_button_{};
    HWND operations_button_{};
    HWND shell_host_{};
    HWND list_{};
    HWND status_{};

    HFONT ui_font_{};
    HFONT title_font_{};
    HFONT caption_font_{};
    HFONT glyph_font_{};
    HBRUSH background_brush_{};
    HBRUSH panel_brush_{};
    HBRUSH surface_brush_{};
    HBRUSH address_brush_{};
    HIMAGELIST sidebar_image_list_{};
    HIMAGELIST system_large_image_list_{};
    UINT dpi_{96};

    RECT address_rect_{};
    RECT content_rect_{};
    RECT preview_rect_{};

    bool shell_available_{};
    bool sidebar_syncing_{};
    bool destroy_deletes_self_{};
    bool initial_path_explicit_{};
    bool preview_visible_{true};
    ContentMode content_mode_{ContentMode::FallbackFileSystem};
    std::wstring current_path_;
    std::wstring suppressed_history_target_;
    std::wstring preview_selection_;
    std::vector<Entry> entries_;
    std::vector<SidebarItem> sidebar_items_;
    CloudOS::NativeFilesPersistedState persisted_state_;
    std::vector<TabState> tab_states_;
    std::size_t active_tab_{};
    UINT_PTR preview_timer_{};
    CloudOS::NativeShellViewHost shell_view_;
    CloudOS::NativeFilePreviewPane preview_;
};