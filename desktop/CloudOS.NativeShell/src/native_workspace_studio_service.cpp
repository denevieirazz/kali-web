#include "native_workspace_studio_service.h"

#include "native_notification_center.h"
#include "native_wallpaper_manager.h"
#include "native_window_manager.h"
#include "native_workspace_studio_window.h"

#include <algorithm>
#include <array>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kEngineClass[] = L"CloudOS.NativeShell.WorkspaceStudioEngine.v2";
constexpr UINT_PTR kEngineTimer = 0x575332;

constexpr int kHotOpenStudio = 3310;
constexpr int kHotQuickSnapshot = 3311;
constexpr int kHotRestoreSnapshot = 3312;
constexpr int kHotReapplyRules = 3313;
constexpr UINT kModifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
constexpr UINT kStrongModifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;

std::wstring QuickSnapshotName(const NativeWorkspaceStudioStore& store, int workspace)
{
    SYSTEMTIME time{};
    GetLocalTime(&time);
    wchar_t buffer[96]{};
    swprintf_s(
        buffer,
        L"%s · %02u:%02u:%02u",
        store.WorkspaceName(workspace).c_str(),
        time.wHour,
        time.wMinute,
        time.wSecond);
    return buffer;
}
}

NativeWorkspaceStudioService& NativeWorkspaceStudioService::Instance()
{
    static NativeWorkspaceStudioService service;
    return service;
}

void NativeWorkspaceStudioService::RegisterManager(CloudOSNativeWindowManager* manager)
{
    auto& service = Instance();
    service.manager_ = manager;
    service.instance_ = GetModuleHandleW(nullptr);
    if (!service.store_loaded_)
    {
        (void)service.store_.Load();
        service.store_loaded_ = true;
    }
    (void)service.EnsureEngineWindow(service.instance_);
}

void NativeWorkspaceStudioService::Open(HINSTANCE instance, HWND owner)
{
    Instance().OpenWindow(instance, owner);
}

NativeWorkspaceStudioService::NativeWorkspaceStudioService() = default;

NativeWorkspaceStudioService::~NativeWorkspaceStudioService()
{
    UnregisterHotKeys();
    if (engine_window_ != nullptr)
    {
        KillTimer(engine_window_, kEngineTimer);
        DestroyWindow(engine_window_);
        engine_window_ = nullptr;
    }
    studio_window_.reset();
}

NativeWorkspaceStudioStore& NativeWorkspaceStudioService::Store() noexcept
{
    return store_;
}

NativeWorkspaceAutomationEngine& NativeWorkspaceStudioService::Automation() noexcept
{
    return automation_;
}

CloudOSNativeWindowManager* NativeWorkspaceStudioService::Manager() const noexcept
{
    return manager_;
}

HWND NativeWorkspaceStudioService::EngineWindow() const noexcept
{
    return engine_window_;
}

bool NativeWorkspaceStudioService::Save()
{
    return store_.Save();
}

void NativeWorkspaceStudioService::Reload()
{
    (void)store_.Load();
    automation_.ResetRuntimeState();
    observed_revision_v12_=~0ull; NotifyModelChangedV12();
    if (studio_window_ != nullptr)
    {
        studio_window_->RefreshAll();
    }
}

void NativeWorkspaceStudioService::ReapplyRules()
{
    if (manager_ == nullptr)
    {
        return;
    }
    manager_->Reconcile();
    automation_.ReapplyAllRules(*manager_, store_);
    CloudOSNativeNotificationCenter::Post(
        L"Workspace Studio",
        L"As regras de janela foram reavaliadas.");
}

void NativeWorkspaceStudioService::ApplyCurrentProfile()
{
    if (manager_ == nullptr)
    {
        return;
    }
    const int workspace = std::clamp(manager_->CurrentWorkspace(), 0, kWorkspaceStudioCount - 1);
    const WorkspaceProfile& profile = store_.Profiles()[static_cast<std::size_t>(workspace)];

    if (profile.apply_wallpaper && !profile.wallpaper_path.empty())
    {
        (void)NativeWallpaperManager::Apply(profile.wallpaper_path);
    }

    if (profile.auto_tile || profile.layout != WorkspaceLayoutPreset::Free)
    {
        NativeWorkspaceLayoutEngine::ApplyPreset(*manager_, workspace, profile.layout);
    }
    else
    {
        manager_->SetTilingEnabled(false);
    }

    if (profile.auto_launch)
    {
        automation_.LaunchWorkspaceEntries(
            instance_ != nullptr ? instance_ : GetModuleHandleW(nullptr),
            owner_ != nullptr ? owner_ : engine_window_,
            workspace,
            store_);
    }
}

void NativeWorkspaceStudioService::CaptureQuickSnapshot()
{
    if (manager_ == nullptr)
    {
        return;
    }
    manager_->Reconcile();
    const int workspace = std::clamp(manager_->CurrentWorkspace(), 0, kWorkspaceStudioCount - 1);
    WorkspaceSnapshot snapshot = NativeWorkspaceLayoutEngine::Capture(
        *manager_,
        store_,
        workspace,
        QuickSnapshotName(store_, workspace));
    const std::size_t count = snapshot.windows.size();
    store_.Snapshots().push_back(std::move(snapshot));
    (void)store_.Save();

    std::wstring message = L"Snapshot rápido salvo com ";
    message += std::to_wstring(count);
    message += count == 1 ? L" janela." : L" janelas.";
    CloudOSNativeNotificationCenter::Post(L"Workspace Studio", message);
    if (studio_window_ != nullptr)
    {
        studio_window_->RefreshAll();
    }
}

void NativeWorkspaceStudioService::RestoreLatestSnapshot()
{
    if (manager_ == nullptr)
    {
        return;
    }
    const int workspace = std::clamp(manager_->CurrentWorkspace(), 0, kWorkspaceStudioCount - 1);
    const WorkspaceSnapshot* latest = nullptr;
    for (const auto& snapshot : store_.Snapshots())
    {
        if (snapshot.workspace != workspace)
        {
            continue;
        }
        if (latest == nullptr || snapshot.created_filetime > latest->created_filetime)
        {
            latest = &snapshot;
        }
    }
    if (latest == nullptr)
    {
        CloudOSNativeNotificationCenter::Post(
            L"Workspace Studio",
            L"Não existe snapshot salvo para esta área.");
        return;
    }

    const bool restored = NativeWorkspaceLayoutEngine::Restore(*manager_, *latest);
    CloudOSNativeNotificationCenter::Post(
        L"Workspace Studio",
        restored ? L"O snapshot mais recente foi restaurado." : L"Nenhuma janela atual corresponde ao snapshot.");
}

void NativeWorkspaceStudioService::OpenWindow(HINSTANCE instance, HWND owner)
{
    instance_ = instance != nullptr ? instance : GetModuleHandleW(nullptr);
    owner_ = owner;
    if (!store_loaded_)
    {
        (void)store_.Load();
        store_loaded_ = true;
    }
    (void)EnsureEngineWindow(instance_);

    if (studio_window_ == nullptr)
    {
        studio_window_ = std::make_unique<NativeWorkspaceStudioWindow>(this);
    }
    if (studio_window_->Hwnd() == nullptr && !studio_window_->Create(instance_))
    {
        MessageBoxW(owner, L"Não foi possível criar o Workspace Studio.", L"CloudOS", MB_OK | MB_ICONERROR);
        return;
    }
    studio_window_->Show(owner);
}

bool NativeWorkspaceStudioService::EnsureEngineWindow(HINSTANCE instance)
{
    if (engine_window_ != nullptr && IsWindow(engine_window_))
    {
        return true;
    }
    instance_ = instance != nullptr ? instance : GetModuleHandleW(nullptr);

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.hInstance = instance_;
    window_class.lpfnWndProc = &NativeWorkspaceStudioService::WindowProcedure;
    window_class.lpszClassName = kEngineClass;
    (void)RegisterClassExW(&window_class);

    engine_window_ = CreateWindowExW(
        0,
        kEngineClass,
        L"CloudOS Workspace Studio Engine",
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        nullptr,
        instance_,
        this);
    if (engine_window_ == nullptr)
    {
        return false;
    }

    NotifyModelChangedV12();
    RegisterHotKeys();
    return true;
}

void NativeWorkspaceStudioService::Tick()
{
    if (manager_ == nullptr || engine_window_ == nullptr)
    {
        return;
    }
    const auto revision=manager_->RevisionV12();
    if(observed_revision_v12_==revision) return;
    observed_revision_v12_=revision;
    automation_.Tick(
        instance_ != nullptr ? instance_ : GetModuleHandleW(nullptr),
        owner_ != nullptr ? owner_ : engine_window_,
        *manager_,
        store_);
    if (studio_window_ != nullptr && studio_window_->Hwnd() != nullptr && IsWindowVisible(studio_window_->Hwnd()))
    {
        studio_window_->RefreshAll();
    }
}

void NativeWorkspaceStudioService::RegisterHotKeys()
{
    if (engine_window_ == nullptr)
    {
        return;
    }
    (void)RegisterHotKey(engine_window_, kHotOpenStudio, kModifiers, L'G');
    (void)RegisterHotKey(engine_window_, kHotQuickSnapshot, kStrongModifiers, L'S');
    (void)RegisterHotKey(engine_window_, kHotRestoreSnapshot, kStrongModifiers, L'R');
    (void)RegisterHotKey(engine_window_, kHotReapplyRules, kStrongModifiers, L'A');
}

void NativeWorkspaceStudioService::UnregisterHotKeys()
{
    if (engine_window_ == nullptr)
    {
        return;
    }
    UnregisterHotKey(engine_window_, kHotOpenStudio);
    UnregisterHotKey(engine_window_, kHotQuickSnapshot);
    UnregisterHotKey(engine_window_, kHotRestoreSnapshot);
    UnregisterHotKey(engine_window_, kHotReapplyRules);
}

LRESULT NativeWorkspaceStudioService::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    (void)l_param;
    switch (message)
    {
    case WM_APP+0x61C: Tick(); return 0;
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
        case kHotOpenStudio:
            OpenWindow(instance_, owner_);
            return 0;
        case kHotQuickSnapshot:
            CaptureQuickSnapshot();
            return 0;
        case kHotRestoreSnapshot:
            RestoreLatestSnapshot();
            return 0;
        case kHotReapplyRules:
            ReapplyRules();
            return 0;
        default:
            break;
        }
        break;
    case WM_DESTROY:
        KillTimer(window, kEngineTimer);
        UnregisterHotKeys();
        if (engine_window_ == window)
        {
            engine_window_ = nullptr;
        }
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK NativeWorkspaceStudioService::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeWorkspaceStudioService*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<NativeWorkspaceStudioService*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->engine_window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
