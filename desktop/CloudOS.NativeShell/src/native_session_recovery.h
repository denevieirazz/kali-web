#pragma once

#include <Windows.h>
#include <CommCtrl.h>

#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "native_health_bootstrap_v9.h"
#include "native_lifecycle_v10.h"
#include "native_session_events_v7.h"
#include "native_window_manager.h"

namespace CloudOS
{
class NativeSessionRecovery final
{
public:
    NativeSessionRecovery() noexcept
        : lifecycle_v10_(this)
    {
    }
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

    // Lifecycle V10 observes the same authoritative desktop HWND as session
    // recovery. It supplements the V7 WTS path with power/display revalidation,
    // WTS registration retry and an opt-in deterministic probe used by CI.
    class LifecycleCoordinatorV10 final
    {
    public:
        explicit LifecycleCoordinatorV10(NativeSessionRecovery* owner) noexcept
            : owner_(owner)
        {
            active_ = this;
            hook_ = SetWinEventHook(
                EVENT_OBJECT_CREATE,
                EVENT_OBJECT_SHOW,
                nullptr,
                &LifecycleCoordinatorV10::WinEventCallback,
                GetCurrentProcessId(),
                0,
                WINEVENT_OUTOFCONTEXT);
            TryAttach(FindWindowW(NativeLifecycleV10::DesktopClass, nullptr));
        }

        ~LifecycleCoordinatorV10()
        {
            if (hook_ != nullptr)
            {
                UnhookWinEvent(hook_);
                hook_ = nullptr;
            }
            Detach();
            if (active_ == this)
            {
                active_ = nullptr;
            }
        }

        LifecycleCoordinatorV10(const LifecycleCoordinatorV10&) = delete;
        LifecycleCoordinatorV10& operator=(const LifecycleCoordinatorV10&) = delete;

    private:
        static void CALLBACK WinEventCallback(
            HWINEVENTHOOK,
            DWORD event,
            HWND window,
            LONG object_id,
            LONG child_id,
            DWORD,
            DWORD)
        {
            if ((event != EVENT_OBJECT_CREATE && event != EVENT_OBJECT_SHOW) ||
                object_id != OBJID_WINDOW || child_id != CHILDID_SELF)
            {
                return;
            }
            if (active_ != nullptr)
            {
                active_->TryAttach(window);
            }
        }

        void TryAttach(HWND candidate) noexcept
        {
            if (desktop_ != nullptr && IsWindow(desktop_))
            {
                return;
            }

            HWND desktop = candidate;
            std::array<wchar_t, 128> class_name{};
            if (desktop == nullptr ||
                GetClassNameW(
                    desktop,
                    class_name.data(),
                    static_cast<int>(class_name.size())) <= 0 ||
                std::wstring_view(class_name.data()) != NativeLifecycleV10::DesktopClass)
            {
                desktop = FindWindowW(NativeLifecycleV10::DesktopClass, nullptr);
            }
            if (desktop == nullptr || !IsWindow(desktop))
            {
                return;
            }

            if (SetWindowSubclass(
                    desktop,
                    &LifecycleCoordinatorV10::DesktopSubclass,
                    NativeLifecycleV10::SubclassId,
                    reinterpret_cast<DWORD_PTR>(this)) == FALSE)
            {
                return;
            }

            desktop_ = desktop;
            retry_tick_ = 0;
            if (SetTimer(
                    desktop_,
                    NativeLifecycleV10::RetryTimerId,
                    NativeLifecycleV10::RetryTimerMilliseconds,
                    nullptr) == 0)
            {
                RemoveWindowSubclass(
                    desktop_,
                    &LifecycleCoordinatorV10::DesktopSubclass,
                    NativeLifecycleV10::SubclassId);
                desktop_ = nullptr;
            }
        }

        void Detach() noexcept
        {
            if (desktop_ != nullptr && IsWindow(desktop_))
            {
                KillTimer(desktop_, NativeLifecycleV10::RetryTimerId);
                RemoveWindowSubclass(
                    desktop_,
                    &LifecycleCoordinatorV10::DesktopSubclass,
                    NativeLifecycleV10::SubclassId);
            }
            desktop_ = nullptr;
            retry_tick_ = 0;
        }

        void Checkpoint() noexcept
        {
            HealthBootstrapV9::bootstrap.Pulse();
            if (owner_ == nullptr || owner_->session_window_manager_ == nullptr)
            {
                return;
            }
            owner_->session_window_manager_->Reconcile();
            owner_->Save(*owner_->session_window_manager_);
        }

        void QueueRevalidation(NativeLifecycleV10::RevalidateReason reason) noexcept
        {
            if (desktop_ != nullptr && IsWindow(desktop_))
            {
                (void)PostMessageW(
                    desktop_,
                    NativeLifecycleV10::RevalidateMessage,
                    static_cast<WPARAM>(reason),
                    0);
            }
        }

        void Revalidate(NativeLifecycleV10::RevalidateReason) noexcept
        {
            HealthBootstrapV9::bootstrap.Pulse();
            if (owner_ == nullptr)
            {
                return;
            }

            CloudOSNativeWindowManager* manager = owner_->session_window_manager_;
            if (manager != nullptr)
            {
                manager->Reconcile();
                owner_->ApplyPending(*manager);

                if (owner_->session_window_ == desktop_ &&
                    owner_->session_subclass_attached_ &&
                    !owner_->session_notifications_registered_)
                {
                    owner_->session_notifications_registered_ =
                        NativeSessionEventsV7::Register(desktop_);
                }
            }

            NativeLifecycleV10::RevalidateShellSurfaces(desktop_);

            if (manager != nullptr)
            {
                manager->Reconcile();
                owner_->Save(*manager);
            }
        }

        void Tick() noexcept
        {
            ++retry_tick_;
            if (owner_ == nullptr ||
                owner_->session_window_ != desktop_ ||
                !owner_->session_subclass_attached_ ||
                owner_->session_notifications_registered_ ||
                (retry_tick_ % NativeLifecycleV10::WtsRetryEveryTicks) != 0u)
            {
                return;
            }

            owner_->session_notifications_registered_ =
                NativeSessionEventsV7::Register(desktop_);
        }

        static LRESULT CALLBACK DesktopSubclass(
            HWND window,
            UINT message,
            WPARAM w_param,
            LPARAM l_param,
            UINT_PTR subclass_id,
            DWORD_PTR reference_data)
        {
            auto* self = reinterpret_cast<LifecycleCoordinatorV10*>(reference_data);
            if (self == nullptr)
            {
                return DefSubclassProc(window, message, w_param, l_param);
            }

            if (message == WM_TIMER &&
                w_param == NativeLifecycleV10::RetryTimerId)
            {
                self->Tick();
                return 0;
            }

            if (message == WM_POWERBROADCAST)
            {
                if (NativeLifecycleV10::IsPowerSuspend(w_param))
                {
                    self->Checkpoint();
                }
                else if (NativeLifecycleV10::IsPowerResume(w_param))
                {
                    self->QueueRevalidation(
                        NativeLifecycleV10::RevalidateReason::Resume);
                }
            }
            else if (message == WM_DISPLAYCHANGE || message == WM_DEVICECHANGE)
            {
                self->QueueRevalidation(
                    NativeLifecycleV10::RevalidateReason::Display);
            }
            else if (NativeSessionEventsV7::IsSessionMessage(message))
            {
                if (NativeSessionEventsV7::ShouldCheckpoint(w_param))
                {
                    self->Checkpoint();
                }
                else if (NativeSessionEventsV7::ShouldRefresh(w_param))
                {
                    self->QueueRevalidation(
                        NativeLifecycleV10::RevalidateReason::Session);
                }
            }
            else if (message == NativeLifecycleV10::RevalidateMessage)
            {
                self->Revalidate(
                    static_cast<NativeLifecycleV10::RevalidateReason>(w_param));
                return 0;
            }
            else if (NativeLifecycleV10::IsProbeMessage(message) &&
                NativeLifecycleV10::ProbeEnabled())
            {
                switch (message)
                {
                case NativeLifecycleV10::ProbeSuspendMessage:
                case NativeLifecycleV10::ProbeSessionDisconnectMessage:
                    self->Checkpoint();
                    return TRUE;
                case NativeLifecycleV10::ProbeResumeMessage:
                    self->QueueRevalidation(
                        NativeLifecycleV10::RevalidateReason::Resume);
                    return TRUE;
                case NativeLifecycleV10::ProbeDisplayMessage:
                    self->QueueRevalidation(
                        NativeLifecycleV10::RevalidateReason::Display);
                    return TRUE;
                case NativeLifecycleV10::ProbeSessionReconnectMessage:
                    self->QueueRevalidation(
                        NativeLifecycleV10::RevalidateReason::Session);
                    return TRUE;
                default:
                    break;
                }
            }

            if (message == WM_NCDESTROY)
            {
                KillTimer(window, NativeLifecycleV10::RetryTimerId);
                RemoveWindowSubclass(
                    window,
                    &LifecycleCoordinatorV10::DesktopSubclass,
                    subclass_id);
                self->desktop_ = nullptr;
                self->retry_tick_ = 0;
            }

            return DefSubclassProc(window, message, w_param, l_param);
        }

        inline static LifecycleCoordinatorV10* active_{};
        NativeSessionRecovery* owner_{};
        HWINEVENTHOOK hook_{};
        HWND desktop_{};
        unsigned retry_tick_{};
    };

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
    LifecycleCoordinatorV10 lifecycle_v10_;
};
} // namespace CloudOS
