#include "../include/cloudos_native_runtime.h"

#include <dwmapi.h>

#include <array>
#include <mutex>
#include <new>
#include <unordered_map>

#pragma comment(lib, "dwmapi.lib")

namespace {

constexpr DWORD kWinEventFlags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;

struct WindowWatcher final {
    cloudos_native_window_event_callback callback = nullptr;
    void* context = nullptr;
    std::array<HWINEVENTHOOK, 3> hooks{};
    std::mutex sync;
    std::unordered_map<HWND, DWORD> process_ids;
};

std::mutex g_watchers_sync;
std::unordered_map<HWINEVENTHOOK, WindowWatcher*> g_watchers;

BOOL window_event_fail(DWORD error) noexcept {
    SetLastError(error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : error);
    return FALSE;
}

bool is_top_level_window(HWND window) noexcept {
    return window != nullptr && IsWindow(window) && GetAncestor(window, GA_ROOT) == window;
}

DWORD process_id_for(HWND window) noexcept {
    DWORD process_id = 0;
    if (window != nullptr) GetWindowThreadProcessId(window, &process_id);
    return process_id;
}

cloudos_native_window_event_kind translate_event(DWORD event_type) noexcept {
    switch (event_type) {
        case EVENT_OBJECT_CREATE: return CLOUDOS_NATIVE_WINDOW_CREATED;
        case EVENT_OBJECT_DESTROY: return CLOUDOS_NATIVE_WINDOW_DESTROYED;
        case EVENT_OBJECT_SHOW: return CLOUDOS_NATIVE_WINDOW_SHOWN;
        case EVENT_OBJECT_HIDE: return CLOUDOS_NATIVE_WINDOW_HIDDEN;
        case EVENT_SYSTEM_FOREGROUND: return CLOUDOS_NATIVE_WINDOW_FOREGROUND;
        case EVENT_OBJECT_LOCATIONCHANGE: return CLOUDOS_NATIVE_WINDOW_LOCATION_CHANGED;
        default: return CLOUDOS_NATIVE_WINDOW_UNKNOWN;
    }
}

void CALLBACK on_win_event(
    HWINEVENTHOOK hook,
    DWORD event_type,
    HWND window,
    LONG object_id,
    LONG child_id,
    DWORD,
    DWORD) noexcept {
    WindowWatcher* watcher = nullptr;
    {
        std::lock_guard lock(g_watchers_sync);
        const auto iterator = g_watchers.find(hook);
        if (iterator == g_watchers.end()) return;
        watcher = iterator->second;
    }
    if (watcher == nullptr || watcher->callback == nullptr || window == nullptr) return;

    if (event_type != EVENT_SYSTEM_FOREGROUND) {
        if (object_id != OBJID_WINDOW || child_id != CHILDID_SELF) return;
    }

    const auto kind = translate_event(event_type);
    if (kind == CLOUDOS_NATIVE_WINDOW_UNKNOWN) return;

    DWORD process_id = 0;
    bool should_dispatch = false;
    {
        std::lock_guard lock(watcher->sync);
        if (kind == CLOUDOS_NATIVE_WINDOW_DESTROYED) {
            const auto tracked = watcher->process_ids.find(window);
            if (tracked != watcher->process_ids.end()) {
                process_id = tracked->second;
                watcher->process_ids.erase(tracked);
                should_dispatch = true;
            }
        } else if (is_top_level_window(window)) {
            process_id = process_id_for(window);
            if (process_id != 0 && process_id != GetCurrentProcessId()) {
                watcher->process_ids[window] = process_id;
                should_dispatch = true;
            }
        }
    }

    if (!should_dispatch) return;
    watcher->callback(kind, window, process_id, watcher->context);
}

BOOL install_hook(
    WindowWatcher* watcher,
    std::size_t index,
    DWORD minimum_event,
    DWORD maximum_event) noexcept {
    const auto hook = SetWinEventHook(
        minimum_event,
        maximum_event,
        nullptr,
        &on_win_event,
        0,
        0,
        kWinEventFlags);
    if (hook == nullptr) return FALSE;

    watcher->hooks[index] = hook;
    {
        std::lock_guard lock(g_watchers_sync);
        g_watchers.emplace(hook, watcher);
    }
    return TRUE;
}

void uninstall_hooks(WindowWatcher* watcher) noexcept {
    if (watcher == nullptr) return;
    for (auto& hook : watcher->hooks) {
        if (hook == nullptr) continue;
        {
            std::lock_guard lock(g_watchers_sync);
            g_watchers.erase(hook);
        }
        UnhookWinEvent(hook);
        hook = nullptr;
    }
}

BOOL CALLBACK enumerate_window_callback(HWND window, LPARAM parameter) noexcept {
    auto* request = reinterpret_cast<cloudos_native_window_enumeration_request*>(parameter);
    if (request == nullptr || request->callback == nullptr || !is_top_level_window(window)) return TRUE;

    const DWORD process_id = process_id_for(window);
    if (process_id == 0 || process_id == GetCurrentProcessId()) return TRUE;

    const BOOL visible = IsWindowVisible(window) ? TRUE : FALSE;
    return request->callback(window, process_id, visible, request->context) ? TRUE : FALSE;
}

} // namespace

extern "C" {

__declspec(dllexport) BOOL WINAPI cloudos_native_window_events_start(
    cloudos_native_window_event_callback callback,
    void* context,
    void** watcher_out) noexcept {
    if (callback == nullptr || watcher_out == nullptr) return window_event_fail(ERROR_INVALID_PARAMETER);
    *watcher_out = nullptr;

    auto watcher = std::unique_ptr<WindowWatcher>(new (std::nothrow) WindowWatcher{});
    if (!watcher) return window_event_fail(ERROR_NOT_ENOUGH_MEMORY);
    watcher->callback = callback;
    watcher->context = context;

    // CREATE..HIDE is a compact contiguous range in the WinEvent API.
    if (!install_hook(watcher.get(), 0, EVENT_OBJECT_CREATE, EVENT_OBJECT_HIDE) ||
        !install_hook(watcher.get(), 1, EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND) ||
        !install_hook(watcher.get(), 2, EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE)) {
        const DWORD error = GetLastError();
        uninstall_hooks(watcher.get());
        return window_event_fail(error);
    }

    *watcher_out = watcher.release();
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) void WINAPI cloudos_native_window_events_stop(void* watcher) noexcept {
    auto* typed = static_cast<WindowWatcher*>(watcher);
    if (typed == nullptr) return;
    uninstall_hooks(typed);
    delete typed;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_window_enumerate(
    cloudos_native_window_enumeration_callback callback,
    void* context) noexcept {
    if (callback == nullptr) return window_event_fail(ERROR_INVALID_PARAMETER);
    cloudos_native_window_enumeration_request request{callback, context};
    SetLastError(ERROR_SUCCESS);
    const BOOL result = EnumWindows(&enumerate_window_callback, reinterpret_cast<LPARAM>(&request));
    if (!result && GetLastError() == ERROR_SUCCESS) {
        // A callback is allowed to stop enumeration intentionally.
        return TRUE;
    }
    return result;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_window_extended_frame_bounds(
    HWND window,
    RECT* bounds_out) noexcept {
    if (window == nullptr || bounds_out == nullptr || !IsWindow(window)) {
        return window_event_fail(ERROR_INVALID_PARAMETER);
    }

    RECT bounds{};
    const HRESULT dwm_result = DwmGetWindowAttribute(
        window,
        DWMWA_EXTENDED_FRAME_BOUNDS,
        &bounds,
        sizeof(bounds));
    if (SUCCEEDED(dwm_result)) {
        *bounds_out = bounds;
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    }

    if (!GetWindowRect(window, &bounds)) return FALSE;
    *bounds_out = bounds;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

} // extern "C"
