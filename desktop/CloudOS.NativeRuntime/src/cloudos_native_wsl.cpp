#include "../include/cloudos_native_runtime.h"

#include <combaseapi.h>
#include <wslapi.h>

#include <new>

namespace {

using WslIsDistributionRegisteredFunction = BOOL (WINAPI*)(PCWSTR);
using WslGetDistributionConfigurationFunction = HRESULT (WINAPI*)(
    PCWSTR,
    ULONG*,
    ULONG*,
    WSL_DISTRIBUTION_FLAGS*,
    PSTR**,
    ULONG*);
using WslLaunchFunction = HRESULT (WINAPI*)(
    PCWSTR,
    PCWSTR,
    BOOL,
    HANDLE,
    HANDLE,
    HANDLE,
    HANDLE*);

struct WslApi final {
    HMODULE module = nullptr;
    WslIsDistributionRegisteredFunction is_registered = nullptr;
    WslGetDistributionConfigurationFunction get_configuration = nullptr;
    WslLaunchFunction launch = nullptr;

    WslApi() noexcept {
        module = LoadLibraryExW(
            L"api-ms-win-wsl-api-l1-1-0.dll",
            nullptr,
            LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (module == nullptr) {
            module = LoadLibraryExW(L"wslapi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        }
        if (module == nullptr) return;

        is_registered = reinterpret_cast<WslIsDistributionRegisteredFunction>(
            GetProcAddress(module, "WslIsDistributionRegistered"));
        get_configuration = reinterpret_cast<WslGetDistributionConfigurationFunction>(
            GetProcAddress(module, "WslGetDistributionConfiguration"));
        launch = reinterpret_cast<WslLaunchFunction>(GetProcAddress(module, "WslLaunch"));

        if (is_registered == nullptr || get_configuration == nullptr || launch == nullptr) {
            FreeLibrary(module);
            module = nullptr;
            is_registered = nullptr;
            get_configuration = nullptr;
            launch = nullptr;
        }
    }

    ~WslApi() noexcept {
        if (module != nullptr) FreeLibrary(module);
    }

    bool available() const noexcept {
        return module != nullptr && is_registered != nullptr &&
            get_configuration != nullptr && launch != nullptr;
    }
};

struct WslLease final {
    HANDLE process = nullptr;
    DWORD process_id = 0;

    ~WslLease() noexcept {
        if (process != nullptr && process != INVALID_HANDLE_VALUE) {
            CloseHandle(process);
            process = nullptr;
        }
    }
};

WslApi& wsl_api() noexcept {
    static WslApi api;
    return api;
}

BOOL require_wsl_api(WslApi*& api_out) noexcept {
    auto& api = wsl_api();
    if (!api.available()) {
        SetLastError(ERROR_NOT_SUPPORTED);
        api_out = nullptr;
        return FALSE;
    }
    api_out = &api;
    return TRUE;
}

BOOL wsl_fail_from_hresult(HRESULT result) noexcept {
    DWORD error = ERROR_GEN_FAILURE;
    if (HRESULT_FACILITY(result) == FACILITY_WIN32) {
        error = HRESULT_CODE(result);
    } else if (result == E_INVALIDARG || result == E_POINTER) {
        error = ERROR_INVALID_PARAMETER;
    } else if (result == E_OUTOFMEMORY) {
        error = ERROR_NOT_ENOUGH_MEMORY;
    } else if (result == E_ACCESSDENIED) {
        error = ERROR_ACCESS_DENIED;
    }
    SetLastError(error);
    return FALSE;
}

WslLease* checked_wsl_lease(void* opaque) noexcept {
    return static_cast<WslLease*>(opaque);
}

HANDLE effective_standard_handle(HANDLE supplied, DWORD standard_handle_id) noexcept {
    if (supplied != nullptr && supplied != INVALID_HANDLE_VALUE) return supplied;
    const HANDLE fallback = GetStdHandle(standard_handle_id);
    return fallback == INVALID_HANDLE_VALUE ? nullptr : fallback;
}

void free_wsl_environment(PSTR* environment, ULONG count) noexcept {
    if (environment == nullptr) return;
    for (ULONG index = 0; index < count; ++index) {
        CoTaskMemFree(environment[index]);
    }
    CoTaskMemFree(environment);
}

} // namespace

extern "C" {

__declspec(dllexport) BOOL WINAPI cloudos_native_wsl_is_registered(
    const wchar_t* distribution_name,
    BOOL* registered_out) noexcept {
    if (distribution_name == nullptr || *distribution_name == L'\0' || registered_out == nullptr) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    WslApi* api = nullptr;
    if (!require_wsl_api(api)) return FALSE;
    *registered_out = api->is_registered(distribution_name) ? TRUE : FALSE;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_wsl_get_configuration(
    const wchar_t* distribution_name,
    cloudos_native_wsl_configuration* configuration_out) noexcept {
    if (distribution_name == nullptr || *distribution_name == L'\0' || configuration_out == nullptr) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    WslApi* api = nullptr;
    if (!require_wsl_api(api)) return FALSE;

    ULONG version = 0;
    ULONG default_uid = 0;
    WSL_DISTRIBUTION_FLAGS flags = WSL_DISTRIBUTION_FLAGS_NONE;
    PSTR* environment = nullptr;
    ULONG environment_count = 0;
    const HRESULT result = api->get_configuration(
        distribution_name,
        &version,
        &default_uid,
        &flags,
        &environment,
        &environment_count);
    if (FAILED(result)) return wsl_fail_from_hresult(result);

    configuration_out->version = version;
    configuration_out->default_uid = default_uid;
    configuration_out->flags = static_cast<std::uint32_t>(flags);
    configuration_out->default_environment_variable_count = environment_count;
    free_wsl_environment(environment, environment_count);
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_wsl_launch(
    const wchar_t* distribution_name,
    const wchar_t* command,
    BOOL use_current_working_directory,
    HANDLE standard_input,
    HANDLE standard_output,
    HANDLE standard_error,
    void** lease_out,
    DWORD* process_id_out) noexcept {
    if (distribution_name == nullptr || *distribution_name == L'\0' ||
        lease_out == nullptr || process_id_out == nullptr) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    *lease_out = nullptr;
    *process_id_out = 0;

    WslApi* api = nullptr;
    if (!require_wsl_api(api)) return FALSE;

    auto* lease = new (std::nothrow) WslLease{};
    if (lease == nullptr) {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    HANDLE process = nullptr;
    const HRESULT result = api->launch(
        distribution_name,
        command != nullptr && *command != L'\0' ? command : nullptr,
        use_current_working_directory,
        effective_standard_handle(standard_input, STD_INPUT_HANDLE),
        effective_standard_handle(standard_output, STD_OUTPUT_HANDLE),
        effective_standard_handle(standard_error, STD_ERROR_HANDLE),
        &process);
    if (FAILED(result)) {
        delete lease;
        return wsl_fail_from_hresult(result);
    }

    if (process == nullptr || process == INVALID_HANDLE_VALUE) {
        delete lease;
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    lease->process = process;
    lease->process_id = GetProcessId(process);
    *process_id_out = lease->process_id;
    *lease_out = lease;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_wsl_get_exit_code(
    void* lease,
    DWORD* exit_code_out,
    BOOL* exited_out) noexcept {
    auto* typed = checked_wsl_lease(lease);
    if (typed == nullptr || typed->process == nullptr || exit_code_out == nullptr || exited_out == nullptr) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    DWORD exit_code = STILL_ACTIVE;
    if (!GetExitCodeProcess(typed->process, &exit_code)) return FALSE;
    *exit_code_out = exit_code;
    *exited_out = exit_code == STILL_ACTIVE ? FALSE : TRUE;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_wsl_terminate(
    void* lease,
    DWORD exit_code) noexcept {
    auto* typed = checked_wsl_lease(lease);
    if (typed == nullptr || typed->process == nullptr) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    return TerminateProcess(typed->process, exit_code);
}

__declspec(dllexport) void WINAPI cloudos_native_wsl_release(void* lease) noexcept {
    delete checked_wsl_lease(lease);
}

} // extern "C"
