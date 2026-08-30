#pragma once

#include <Windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include "native_session_events_v7.h"
#include "native_window_manager.h"

namespace CloudOS
{
class NativeSessionRecovery final
{
public:
    NativeSessionRecovery() = default;
    ~NativeSessionRecovery();

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
    static bool MatchesExternal(const Record& record, const CloudOSManagedWindow& item);
    bool Load();
    bool Write(const std::vector<Record>& records) const;
    void ApplyPending(CloudOSNativeWindowManager& window_manager);
    void AttachSessionNotifications(HWND owner, CloudOSNativeWindowManager& window_manager);
    void DetachSessionNotifications() noexcept;
    static LRESULT CALLBACK SessionNotificationSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);

    std::wstring storage_directory_;
    std::wstring state_path_;
    std::wstring unclean_marker_path_;
    std::vector<Record> loaded_records_;
    std::vector<Record> pending_internal_;
    HWND session_window_{};
    CloudOSNativeWindowManager* session_window_manager_{};
    bool session_notifications_registered_{};
    bool session_subclass_attached_{};
    bool previous_unclean_{};
    bool begun_{};
    unsigned tick_counter_{};
};
} // namespace CloudOS
