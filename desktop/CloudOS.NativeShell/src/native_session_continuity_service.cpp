#include "native_session_continuity_service.h"

#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_session_continuity_window.h"
#include "native_window_manager.h"
#include "native_workspace_automation.h"
#include "native_workspace_labels.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <unordered_set>

namespace CloudOS
{
namespace
{
constexpr wchar_t kEngineClass[] = L"CloudOS.NativeShell.SessionContinuity.Engine.v3";
constexpr UINT_PTR kEngineTimer = 0xC610;
constexpr UINT kEngineIntervalMs = 2000u;
constexpr int kHotOpenCenter = 0xC611;
constexpr int kHotCheckpoint = 0xC612;
constexpr int kHotRestoreLatest = 0xC613;
constexpr LONG kNormalizedScale = 10000;

RECT NormalizeBounds(const RECT& bounds, const RECT& work)
{
    const LONG width = std::max<LONG>(1, work.right - work.left);
    const LONG height = std::max<LONG>(1, work.bottom - work.top);
    RECT result{};
    result.left = ((bounds.left - work.left) * kNormalizedScale) / width;
    result.top = ((bounds.top - work.top) * kNormalizedScale) / height;
    result.right = ((bounds.right - work.left) * kNormalizedScale) / width;
    result.bottom = ((bounds.bottom - work.top) * kNormalizedScale) / height;
    result.left = std::clamp<LONG>(result.left, -kNormalizedScale, kNormalizedScale * 2);
    result.top = std::clamp<LONG>(result.top, -kNormalizedScale, kNormalizedScale * 2);
    result.right = std::clamp<LONG>(result.right, -kNormalizedScale, kNormalizedScale * 2);
    result.bottom = std::clamp<LONG>(result.bottom, -kNormalizedScale, kNormalizedScale * 2);
    return result;
}

RECT DenormalizeBounds(const RECT& normalized, const RECT& work)
{
    const LONG width = std::max<LONG>(1, work.right - work.left);
    const LONG height = std::max<LONG>(1, work.bottom - work.top);
    RECT result{};
    result.left = work.left + (normalized.left * width) / kNormalizedScale;
    result.top = work.top + (normalized.top * height) / kNormalizedScale;
    result.right = work.left + (normalized.right * width) / kNormalizedScale;
    result.bottom = work.top + (normalized.bottom * height) / kNormalizedScale;
    if (result.right - result.left < 160)
    {
        result.right = result.left + 160;
    }
    if (result.bottom - result.top < 120)
    {
        result.bottom = result.top + 120;
    }
    return result;
}

std::wstring MonitorDevice(HMONITOR monitor)
{
    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    return monitor != nullptr && GetMonitorInfoW(monitor, &info)
        ? std::wstring(info.szDevice)
        : std::wstring{};
}

RECT MonitorWorkByDevice(const std::wstring& device, HWND fallback)
{
    for (const auto& monitor : NativeMonitorManager::Enumerate())
    {
        if (!device.empty() && _wcsicmp(monitor.device.c_str(), device.c_str()) == 0)
        {
            return monitor.work;
        }
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const HMONITOR monitor = MonitorFromWindow(
        fallback != nullptr ? fallback : GetDesktopWindow(),
        MONITOR_DEFAULTTOPRIMARY);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        return info.rcWork;
    }
    RECT work{};
    (void)SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    return work;
}

bool ContainsInsensitive(const std::wstring& text, const std::wstring& pattern)
{
    if (pattern.empty())
    {
        return true;
    }
    auto lower = [](std::wstring value)
    {
        std::transform(
            value.begin(),
            value.end(),
            value.begin(),
            [](wchar_t ch)
            {
                return static_cast<wchar_t>(std::towlower(ch));
            });
        return value;
    };
    return lower(text).find(lower(pattern)) != std::wstring::npos;
}

int MatchScore(
    const WorkspaceWindowIdentity& identity,
    const ContinuityWindowState& state)
{
    int score = 0;
    if (!state.process_name.empty())
    {
        if (_wcsicmp(identity.process_name.c_str(), state.process_name.c_str()) != 0)
        {
            return -1;
        }
        score += 5;
    }
    if (!state.window_class.empty())
    {
        if (_wcsicmp(identity.window_class.c_str(), state.window_class.c_str()) != 0)
        {
            return -1;
        }
        score += 4;
    }
    if (!state.title_hint.empty() && ContainsInsensitive(identity.window_title, state.title_hint))
    {
        score += 2;
    }
    return score;
}

void HashBytes(std::uint64_t* hash, const void* data, std::size_t bytes)
{
    if (hash == nullptr || data == nullptr)
    {
        return;
    }
    const auto* value = static_cast<const unsigned char*>(data);
    for (std::size_t index = 0; index < bytes; ++index)
    {
        *hash ^= value[index];
        *hash *= 1099511628211ull;
    }
}
}

NativeSessionContinuityService& NativeSessionContinuityService::Instance()
{
    static NativeSessionContinuityService instance;
    return instance;
}

NativeSessionContinuityService::NativeSessionContinuityService() = default;

NativeSessionContinuityService::~NativeSessionContinuityService()
{
    if (initialized_)
    {
        const int workspace = manager_ != nullptr ? manager_->CurrentWorkspace() : store_.LastWorkspace();
        store_.SetLastWorkspace(workspace);
        store_.AddEvent(
            ContinuityEventKind::SessionClosedCleanly,
            workspace,
            L"CloudOS encerrado normalmente",
            NativeWorkspaceLabels::Name(workspace));
        (void)store_.Save();
        MarkCleanSession();
    }

    UnregisterHotKeys();
    if (engine_window_ != nullptr && IsWindow(engine_window_))
    {
        KillTimer(engine_window_, kEngineTimer);
        DestroyWindow(engine_window_);
    }
    engine_window_ = nullptr;
    window_.reset();
}

void NativeSessionContinuityService::RegisterManager(CloudOSNativeWindowManager* manager)
{
    NativeSessionContinuityService& service = Instance();
    service.manager_ = manager;
    if (manager != nullptr)
    {
        (void)service.EnsureInitialized(GetModuleHandleW(nullptr));
    }
}

void NativeSessionContinuityService::Open(HINSTANCE instance, HWND owner)
{
    NativeSessionContinuityService& service = Instance();
    if (instance == nullptr)
    {
        instance = GetModuleHandleW(nullptr);
    }
    if (!service.EnsureInitialized(instance))
    {
        return;
    }
    service.owner_ = owner;
    if (service.window_ == nullptr)
    {
        auto window = std::make_unique<NativeSessionContinuityWindow>();
        if (!window->Create(instance, &service))
        {
            return;
        }
        service.window_ = std::move(window);
    }
    service.window_->Show(owner);
}

bool NativeSessionContinuityService::EnsureInitialized(HINSTANCE instance)
{
    if (initialized_)
    {
        return true;
    }
    instance_ = instance != nullptr ? instance : GetModuleHandleW(nullptr);
    if (instance_ == nullptr)
    {
        return false;
    }

    const std::wstring marker = LiveMarkerPath();
    previous_unclean_ = !marker.empty() &&
        GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES;

    (void)store_.Load();
    if (store_.LoadedFromBackup())
    {
        store_.AddEvent(
            ContinuityEventKind::StoreRecoveredFromBackup,
            store_.LastWorkspace(),
            L"Ledger recuperado do backup",
            L"O arquivo principal estava ausente ou inválido; continuity_v3.dat.bak foi carregado.");
    }
    store_.AddEvent(
        ContinuityEventKind::SessionStarted,
        store_.LastWorkspace(),
        previous_unclean_ ? L"Sessão iniciada após interrupção" : L"Sessão iniciada",
        previous_unclean_ ? L"Marker da sessão anterior ainda estava presente." : L"Inicialização limpa.");
    (void)store_.Save();

    MarkLiveSession();
    if (!EnsureEngineWindow(instance_))
    {
        return false;
    }
    initialized_ = true;
    return true;
}

bool NativeSessionContinuityService::EnsureEngineWindow(HINSTANCE instance)
{
    if (engine_window_ != nullptr && IsWindow(engine_window_))
    {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeSessionContinuityService::WindowProcedure;
    window_class.hInstance = instance;
    window_class.lpszClassName = kEngineClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    engine_window_ = CreateWindowExW(
        0,
        kEngineClass,
        L"CloudOS Continuity Engine",
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        nullptr,
        instance,
        this);
    if (engine_window_ == nullptr)
    {
        return false;
    }

    RegisterHotKeys();
    (void)SetTimer(engine_window_, kEngineTimer, kEngineIntervalMs, nullptr);
    return true;
}

void NativeSessionContinuityService::RegisterHotKeys()
{
    if (engine_window_ == nullptr)
    {
        return;
    }
    constexpr UINT modifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;
    (void)RegisterHotKey(engine_window_, kHotOpenCenter, modifiers, 'C');
    (void)RegisterHotKey(engine_window_, kHotCheckpoint, modifiers, 'K');
    (void)RegisterHotKey(engine_window_, kHotRestoreLatest, modifiers, 'L');
}

void NativeSessionContinuityService::UnregisterHotKeys()
{
    if (engine_window_ == nullptr)
    {
        return;
    }
    (void)UnregisterHotKey(engine_window_, kHotOpenCenter);
    (void)UnregisterHotKey(engine_window_, kHotCheckpoint);
    (void)UnregisterHotKey(engine_window_, kHotRestoreLatest);
}

std::wstring NativeSessionContinuityService::LiveMarkerPath() const
{
    const std::wstring directory = NativeSessionContinuityStore::StoreDirectory();
    return directory.empty() ? std::wstring{} : directory + L"\\continuity_v3.live";
}

void NativeSessionContinuityService::MarkLiveSession()
{
    const std::wstring directory = NativeSessionContinuityStore::StoreDirectory();
    const std::wstring marker = LiveMarkerPath();
    if (directory.empty() || marker.empty())
    {
        return;
    }
    (void)CreateDirectoryW(directory.c_str(), nullptr);
    HANDLE file = CreateFileW(
        marker.c_str(),
        GENERIC_WRITE,
        FILE_SHARE_READ,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return;
    }
    const DWORD process_id = GetCurrentProcessId();
    const std::uint64_t now = NativeSessionContinuityStore::FileTimeNow();
    DWORD written = 0;
    (void)WriteFile(file, &process_id, static_cast<DWORD>(sizeof(process_id)), &written, nullptr);
    (void)WriteFile(file, &now, static_cast<DWORD>(sizeof(now)), &written, nullptr);
    (void)FlushFileBuffers(file);
    CloseHandle(file);
}

void NativeSessionContinuityService::MarkCleanSession()
{
    const std::wstring marker = LiveMarkerPath();
    if (!marker.empty())
    {
        (void)DeleteFileW(marker.c_str());
    }
}

std::uint32_t NativeSessionContinuityService::CaptureCheckpoint(
    int workspace,
    const std::wstring& reason)
{
    if (manager_ == nullptr || !store_.Preferences().enabled)
    {
        return 0u;
    }

    workspace = std::clamp(workspace, 0, 3);
    manager_->Reconcile();
    ContinuityCheckpoint checkpoint{};
    checkpoint.id = store_.NextCheckpointId();
    checkpoint.workspace = workspace;
    checkpoint.created_filetime = NativeSessionContinuityStore::FileTimeNow();
    checkpoint.reason = reason.empty() ? L"checkpoint" : reason;

    for (const auto& item : manager_->AllManagedWindows())
    {
        if (item.workspace != workspace || item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }
        RECT bounds{};
        if (!GetWindowRect(item.hwnd, &bounds))
        {
            continue;
        }

        const WorkspaceWindowIdentity identity =
            NativeWorkspaceAutomationEngine::IdentifyWindow(item.hwnd, item.process_id);
        ContinuityWindowState state{};
        state.process_name = identity.process_name;
        state.window_class = identity.window_class;
        state.title_hint = identity.window_title;
        if (state.title_hint.size() > 160u)
        {
            state.title_hint.resize(160u);
        }

        const HMONITOR monitor = MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST);
        state.monitor_device = MonitorDevice(monitor);
        const RECT work = MonitorWorkByDevice(state.monitor_device, item.hwnd);
        state.normalized_bounds = NormalizeBounds(bounds, work);
        state.floating = item.floating;

        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        if (GetWindowPlacement(item.hwnd, &placement))
        {
            state.show_command = placement.showCmd;
        }
        checkpoint.windows.push_back(std::move(state));
    }

    store_.AddCheckpoint(std::move(checkpoint));
    store_.AddEvent(
        ContinuityEventKind::CheckpointCreated,
        workspace,
        L"Checkpoint salvo",
        NativeWorkspaceLabels::Name(workspace) + L" · " + reason);
    store_.SetLastWorkspace(manager_->CurrentWorkspace());
    (void)store_.Save();
    last_workspace_signature_[static_cast<std::size_t>(workspace)] = WorkspaceSignature(workspace);
    last_checkpoint_tick_[static_cast<std::size_t>(workspace)] = GetTickCount64();

    RefreshWindow();
    const ContinuityCheckpoint* latest = store_.LatestCheckpoint(workspace);
    return latest != nullptr ? latest->id : 0u;
}

bool NativeSessionContinuityService::RestoreCheckpoint(std::uint32_t checkpoint_id)
{
    if (manager_ == nullptr || checkpoint_id == 0u)
    {
        return false;
    }
    const ContinuityCheckpoint* source = store_.FindCheckpoint(checkpoint_id);
    if (source == nullptr)
    {
        return false;
    }
    const ContinuityCheckpoint checkpoint = *source;

    if (manager_->CurrentWorkspace() != checkpoint.workspace)
    {
        manager_->SwitchWorkspace(checkpoint.workspace);
    }
    manager_->Reconcile();
    const auto windows = manager_->AllManagedWindows();
    std::unordered_set<HWND> used;
    std::size_t restored = 0u;

    for (const ContinuityWindowState& state : checkpoint.windows)
    {
        HWND best_window = nullptr;
        int best_score = -1;
        for (const auto& item : windows)
        {
            if (item.workspace != checkpoint.workspace ||
                item.hwnd == nullptr ||
                !IsWindow(item.hwnd) ||
                used.contains(item.hwnd))
            {
                continue;
            }
            const WorkspaceWindowIdentity identity =
                NativeWorkspaceAutomationEngine::IdentifyWindow(item.hwnd, item.process_id);
            const int score = MatchScore(identity, state);
            if (score > best_score)
            {
                best_score = score;
                best_window = item.hwnd;
            }
        }

        if (best_window == nullptr || best_score < 4)
        {
            continue;
        }
        const RECT work = MonitorWorkByDevice(state.monitor_device, best_window);
        const RECT bounds = DenormalizeBounds(state.normalized_bounds, work);
        if (manager_->RestoreWindowState(
                best_window,
                checkpoint.workspace,
                state.floating,
                bounds,
                state.show_command))
        {
            used.insert(best_window);
            ++restored;
        }
    }

    const bool success = restored > 0u || checkpoint.windows.empty();
    store_.SetLastWorkspace(checkpoint.workspace);
    store_.AddEvent(
        success ? ContinuityEventKind::CheckpointRestored : ContinuityEventKind::CheckpointFailed,
        checkpoint.workspace,
        success ? L"Checkpoint restaurado" : L"Checkpoint sem correspondências",
        std::to_wstring(restored) + L" de " +
            std::to_wstring(checkpoint.windows.size()) + L" janelas correspondidas.");
    (void)store_.Save();
    last_workspace_signature_[static_cast<std::size_t>(checkpoint.workspace)] =
        WorkspaceSignature(checkpoint.workspace);
    RefreshWindow();

    if (success)
    {
        CloudOSNativeNotificationCenter::Post(
            L"Continuidade restaurada",
            NativeWorkspaceLabels::Name(checkpoint.workspace) + L": " +
                std::to_wstring(restored) + L" janelas reposicionadas.");
    }
    return success;
}

bool NativeSessionContinuityService::RestoreLatest(int workspace)
{
    workspace = std::clamp(workspace, 0, 3);
    const ContinuityCheckpoint* checkpoint = store_.LatestCheckpoint(workspace);
    return checkpoint != nullptr && RestoreCheckpoint(checkpoint->id);
}

bool NativeSessionContinuityService::SaveNow(const std::wstring& reason)
{
    if (manager_ == nullptr)
    {
        return false;
    }
    const int workspace = manager_->CurrentWorkspace();
    const std::uint32_t checkpoint = CaptureCheckpoint(workspace, reason);
    store_.AddEvent(
        ContinuityEventKind::ManualSave,
        workspace,
        L"Estado salvo manualmente",
        L"Checkpoint #" + std::to_wstring(checkpoint));
    const bool saved = store_.Save();
    RefreshWindow();
    return checkpoint != 0u && saved;
}

void NativeSessionContinuityService::ClearJournal()
{
    store_.ClearJournal();
    store_.AddEvent(
        ContinuityEventKind::SettingsChanged,
        manager_ != nullptr ? manager_->CurrentWorkspace() : store_.LastWorkspace(),
        L"Journal limpo");
    (void)store_.Save();
    RefreshWindow();
}

void NativeSessionContinuityService::ClearCheckpoints()
{
    store_.ClearCheckpoints();
    store_.AddEvent(
        ContinuityEventKind::SettingsChanged,
        manager_ != nullptr ? manager_->CurrentWorkspace() : store_.LastWorkspace(),
        L"Checkpoints removidos");
    (void)store_.Save();
    last_workspace_signature_.fill(0u);
    last_checkpoint_tick_.fill(0u);
    RefreshWindow();
}

void NativeSessionContinuityService::PreferencesChanged()
{
    store_.Trim();
    store_.AddEvent(
        ContinuityEventKind::SettingsChanged,
        manager_ != nullptr ? manager_->CurrentWorkspace() : store_.LastWorkspace(),
        L"Preferências de continuidade atualizadas");
    (void)store_.Save();
    RefreshWindow();
}

void NativeSessionContinuityService::RefreshWindow()
{
    if (window_ != nullptr)
    {
        window_->Refresh();
    }
}

void NativeSessionContinuityService::HandleInitialResume()
{
    if (initial_resume_done_ || manager_ == nullptr)
    {
        return;
    }
    initial_resume_done_ = true;

    const ContinuityPreferences& preferences = store_.Preferences();
    if (!preferences.enabled)
    {
        return;
    }

    if (preferences.restore_last_workspace && manager_->CurrentWorkspace() != store_.LastWorkspace())
    {
        manager_->SwitchWorkspace(store_.LastWorkspace());
    }
    observed_workspace_ = manager_->CurrentWorkspace();

    if (previous_unclean_ && preferences.restore_after_unclean)
    {
        const bool restored = RestoreLatest(observed_workspace_);
        store_.AddEvent(
            ContinuityEventKind::SessionRecovered,
            observed_workspace_,
            restored ? L"Continuidade pós-crash aplicada" : L"Continuidade pós-crash sem checkpoint",
            NativeWorkspaceLabels::Name(observed_workspace_));
        (void)store_.Save();
        if (restored)
        {
            CloudOSNativeNotificationCenter::Post(
                L"Session Continuity V3",
                L"O último checkpoint de " + NativeWorkspaceLabels::Name(observed_workspace_) +
                    L" foi reaplicado após uma sessão interrompida.");
        }
    }
}

void NativeSessionContinuityService::HandleWorkspaceChange(int current_workspace)
{
    if (observed_workspace_ < 0)
    {
        observed_workspace_ = current_workspace;
        return;
    }
    if (current_workspace == observed_workspace_)
    {
        return;
    }

    const int previous = observed_workspace_;
    if (store_.Preferences().enabled && store_.Preferences().auto_checkpoint)
    {
        (void)CaptureCheckpoint(previous, L"saída da área");
    }
    observed_workspace_ = current_workspace;
    store_.SetLastWorkspace(current_workspace);
    store_.AddEvent(
        ContinuityEventKind::WorkspaceChanged,
        current_workspace,
        L"Área ativa alterada",
        NativeWorkspaceLabels::Name(previous) + L" → " + NativeWorkspaceLabels::Name(current_workspace));
    (void)store_.Save();
}

void NativeSessionContinuityService::HandleFocusChange(int current_workspace)
{
    if (!store_.Preferences().record_focus_history)
    {
        observed_foreground_ = GetForegroundWindow();
        return;
    }
    const HWND foreground = GetForegroundWindow();
    if (foreground == nullptr || foreground == observed_foreground_)
    {
        return;
    }
    observed_foreground_ = foreground;
    if (manager_ == nullptr || manager_->WorkspaceFor(foreground) != current_workspace)
    {
        return;
    }

    const WorkspaceWindowIdentity identity = NativeWorkspaceAutomationEngine::IdentifyWindow(foreground);
    if (identity.window_title.empty())
    {
        return;
    }
    store_.AddEvent(
        ContinuityEventKind::WindowFocusChanged,
        current_workspace,
        identity.window_title,
        identity.process_name);
    if ((store_.Journal().size() % 8u) == 0u)
    {
        (void)store_.Save();
    }
}

std::uint64_t NativeSessionContinuityService::WorkspaceSignature(int workspace) const
{
    if (manager_ == nullptr)
    {
        return 0u;
    }
    std::uint64_t hash = 1469598103934665603ull;
    for (const auto& item : manager_->AllManagedWindows())
    {
        if (item.workspace != workspace || item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }
        const auto raw = reinterpret_cast<std::uintptr_t>(item.hwnd);
        HashBytes(&hash, &raw, sizeof(raw));
        HashBytes(&hash, &item.floating, sizeof(item.floating));
        RECT bounds{};
        if (GetWindowRect(item.hwnd, &bounds))
        {
            HashBytes(&hash, &bounds, sizeof(bounds));
        }
        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        if (GetWindowPlacement(item.hwnd, &placement))
        {
            HashBytes(&hash, &placement.showCmd, sizeof(placement.showCmd));
        }
    }
    return hash;
}

void NativeSessionContinuityService::HandleAutoCheckpoint(int current_workspace)
{
    const ContinuityPreferences& preferences = store_.Preferences();
    if (!preferences.enabled || !preferences.auto_checkpoint)
    {
        return;
    }
    const std::size_t index = static_cast<std::size_t>(std::clamp(current_workspace, 0, 3));
    const ULONGLONG now = GetTickCount64();
    const ULONGLONG interval = static_cast<ULONGLONG>(
        std::clamp<std::uint32_t>(preferences.checkpoint_interval_seconds, 5u, 3600u)) * 1000ull;
    if (last_checkpoint_tick_[index] != 0u && now - last_checkpoint_tick_[index] < interval)
    {
        return;
    }

    const std::uint64_t signature = WorkspaceSignature(current_workspace);
    if (last_workspace_signature_[index] == signature && last_checkpoint_tick_[index] != 0u)
    {
        last_checkpoint_tick_[index] = now;
        return;
    }
    (void)CaptureCheckpoint(current_workspace, L"autosave");
}

void NativeSessionContinuityService::Tick()
{
    if (manager_ == nullptr || !initialized_)
    {
        return;
    }
    manager_->Reconcile();
    HandleInitialResume();
    const int workspace = manager_->CurrentWorkspace();
    HandleWorkspaceChange(workspace);
    HandleFocusChange(workspace);
    HandleAutoCheckpoint(workspace);
    RefreshWindow();
}

LRESULT CALLBACK NativeSessionContinuityService::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeSessionContinuityService*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(l_param);
        self = static_cast<NativeSessionContinuityService*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}

LRESULT NativeSessionContinuityService::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_TIMER:
        if (w_param == kEngineTimer)
        {
            Tick();
            return 0;
        }
        break;
    case WM_HOTKEY:
        switch (static_cast<int>(w_param))
        {
        case kHotOpenCenter:
            Open(instance_, owner_);
            return 0;
        case kHotCheckpoint:
            if (manager_ != nullptr)
            {
                (void)SaveNow(L"atalho global");
                CloudOSNativeNotificationCenter::Post(
                    L"Checkpoint criado",
                    NativeWorkspaceLabels::Name(manager_->CurrentWorkspace()));
            }
            return 0;
        case kHotRestoreLatest:
            if (manager_ != nullptr)
            {
                (void)RestoreLatest(manager_->CurrentWorkspace());
            }
            return 0;
        default:
            break;
        }
        break;
    case WM_DESTROY:
        if (window == engine_window_)
        {
            engine_window_ = nullptr;
        }
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
