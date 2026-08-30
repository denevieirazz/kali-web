#pragma once

#include <Windows.h>

#include <cstdint>
#include <string>
#include <vector>

class CloudOSNativeWindowManager;

namespace CloudOS
{
class NativeSessionRecovery final
{
public:
    NativeSessionRecovery() = default;
    ~NativeSessionRecovery() = default;

    NativeSessionRecovery(const NativeSessionRecovery&) = delete;
    NativeSessionRecovery& operator=(const NativeSessionRecovery&) = delete;

    bool BeginSession();
    void Restore(
        HINSTANCE instance,
        HWND owner,
        CloudOSNativeWindowManager& window_manager);
    void Tick(CloudOSNativeWindowManager& window_manager);
    void Save(const CloudOSNativeWindowManager& window_manager);
    void MarkCleanExit(const CloudOSNativeWindowManager& window_manager);

    [[nodiscard]] bool PreviousSessionUnclean() const noexcept
    {
        return previous_unclean_;
    }

private:
    struct Record final
    {
        std::wstring class_name;
        std::wstring title;
        std::wstring app_id;
        DWORD process_id{};
        int workspace{};
        bool floating{};
        RECT bounds{};
        UINT show_command{SW_SHOWNORMAL};
        int attempts{};
    };

    static std::wstring AppIdFor(HWND window, const std::wstring& class_name, const std::wstring& title);
    static std::wstring ClassName(HWND window);
    static bool MatchesExternal(const Record& record, const struct CloudOSManagedWindow& item);
    bool Load();
    bool Write(const std::vector<Record>& records) const;
    void ApplyPending(CloudOSNativeWindowManager& window_manager);

    std::wstring storage_directory_;
    std::wstring state_path_;
    std::wstring unclean_marker_path_;
    std::vector<Record> loaded_records_;
    std::vector<Record> pending_internal_;
    bool previous_unclean_{};
    bool begun_{};
    unsigned tick_counter_{};
};
} // namespace CloudOS
