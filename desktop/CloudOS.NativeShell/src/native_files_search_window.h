#pragma once

#include <Windows.h>

#include <atomic>
#include <cstddef>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{
class CloudOSNativeFilesSearchWindow final
{
public:
    static HWND Open(
        HINSTANCE instance,
        const std::wstring& root,
        const std::wstring& query,
        HWND owner = nullptr);

private:
    struct Result final
    {
        std::wstring name;
        std::wstring path;
        ULONGLONG size{};
        FILETIME modified{};
        bool directory{};
    };

    struct SearchCompletion final
    {
        std::vector<Result> results;
        std::wstring error;
        bool canceled{};
        bool truncated{};
    };

    CloudOSNativeFilesSearchWindow(
        HINSTANCE instance,
        std::wstring root,
        std::wstring query) noexcept;
    ~CloudOSNativeFilesSearchWindow();

    bool Create(HWND owner);
    void Destroy() noexcept;
    void Layout();
    void Paint(HDC dc);
    void StartSearch();
    void CancelSearch() noexcept;
    void JoinWorker() noexcept;
    void ApplyCompletion(SearchCompletion* completion);
    void OpenSelected(bool parent_only);
    void RefreshStatus();

    void WorkerMain(std::wstring root, std::wstring query);
    void SearchDirectory(
        const std::wstring& directory,
        const std::wstring& lowered_query,
        std::size_t depth,
        SearchCompletion* completion);

    static std::wstring Lower(std::wstring value);
    static std::wstring JoinPath(const std::wstring& left, const std::wstring& right);
    static std::wstring ParentPath(const std::wstring& path);
    static std::wstring FormatBytes(ULONGLONG value);
    static std::wstring FormatModified(const FILETIME& value);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND title_{};
    HWND query_label_{};
    HWND list_{};
    HWND open_button_{};
    HWND location_button_{};
    HWND cancel_button_{};
    HWND status_{};
    HFONT font_{};
    HFONT title_font_{};
    HBRUSH background_{};

    std::wstring root_;
    std::wstring query_;
    std::vector<Result> results_;
    std::thread worker_;
    std::atomic_bool cancel_requested_{false};
    bool running_{};
    bool self_delete_{};

public:
    static constexpr std::size_t MaximumResults = 500;
    static constexpr std::size_t MaximumDepth = 24;
    static constexpr std::size_t MaximumQueryCharacters = 512;
};
} // namespace CloudOS
