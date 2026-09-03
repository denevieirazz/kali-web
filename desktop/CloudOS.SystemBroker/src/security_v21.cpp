#include "security_v21.h"

#include <userenv.h>

#include <vector>

namespace CloudOS
{
namespace
{
constexpr DWORD kInvalidSessionId = 0xFFFFFFFFu;

std::wstring TokenUserSidString(HANDLE token)
{
    if (token == nullptr || token == INVALID_HANDLE_VALUE) return {};

    DWORD length = 0;
    (void)GetTokenInformation(token, TokenUser, nullptr, 0, &length);
    if (length == 0) return {};

    std::vector<BYTE> buffer;
    try
    {
        buffer.resize(length);
    }
    catch (...)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return {};
    }

    if (!GetTokenInformation(token, TokenUser, buffer.data(), length, &length)) return {};
    const auto* token_user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
    if (token_user == nullptr || token_user->User.Sid == nullptr ||
        !IsValidSid(token_user->User.Sid))
    {
        SetLastError(ERROR_INVALID_SID);
        return {};
    }

    LPWSTR raw_sid = nullptr;
    if (!ConvertSidToStringSidW(token_user->User.Sid, &raw_sid) || raw_sid == nullptr)
        return {};

    std::wstring result(raw_sid);
    LocalFree(raw_sid);
    return result;
}

std::wstring ProcessUserSidString(DWORD process_id)
{
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
    if (process == nullptr) return {};

    HANDLE token = nullptr;
    const BOOL opened = OpenProcessToken(process, TOKEN_QUERY, &token);
    CloseHandle(process);
    if (!opened || token == nullptr) return {};

    std::wstring sid = TokenUserSidString(token);
    CloseHandle(token);
    return sid;
}

bool BuildDenyAllSecurityAttributes(
    SECURITY_ATTRIBUTES* out_sa,
    PSECURITY_DESCRIPTOR* out_sd)
{
    if (out_sa == nullptr || out_sd == nullptr) return false;

    constexpr SIZE_T kDescriptorBytes = SECURITY_DESCRIPTOR_MIN_LENGTH;
    constexpr SIZE_T kAclBytes = sizeof(ACL);
    auto* storage = static_cast<BYTE*>(LocalAlloc(LPTR, kDescriptorBytes + kAclBytes));
    if (storage == nullptr) return false;

    auto* descriptor = reinterpret_cast<PSECURITY_DESCRIPTOR>(storage);
    auto* acl = reinterpret_cast<PACL>(storage + kDescriptorBytes);
    if (!InitializeSecurityDescriptor(descriptor, SECURITY_DESCRIPTOR_REVISION) ||
        !InitializeAcl(acl, static_cast<DWORD>(kAclBytes), ACL_REVISION) ||
        !SetSecurityDescriptorDacl(descriptor, TRUE, acl, FALSE))
    {
        LocalFree(storage);
        return false;
    }

    out_sa->nLength = sizeof(SECURITY_ATTRIBUTES);
    out_sa->lpSecurityDescriptor = descriptor;
    out_sa->bInheritHandle = FALSE;
    *out_sd = descriptor;
    return true;
}
}

std::wstring SecurityV21::GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    {
        std::wstring sid = TokenUserSidString(token);
        CloseHandle(token);
        if (!sid.empty()) return sid;
    }

    // Never invent a valid-looking user SID. A PID-scoped unresolved identity
    // avoids a cross-user mutex/pipe-name collision, while ACL creation below
    // sees this is not an SID and produces a deny-all DACL.
    return L"UNRESOLVED-" + std::to_wstring(GetCurrentProcessId());
}

DWORD SecurityV21::GetCurrentSessionId()
{
    DWORD session_id = kInvalidSessionId;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id))
        return kInvalidSessionId;
    return session_id;
}

std::wstring SecurityV21::GetCommandPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    const DWORD session_id = GetCurrentSessionId();
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." + std::to_wstring(session_id);
}

std::wstring SecurityV21::GetEventsPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    const DWORD session_id = GetCurrentSessionId();
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.Events.v21." + sid + L"." + std::to_wstring(session_id);
}

std::wstring SecurityV21::GetBrokerMutexName()
{
    const std::wstring sid = GetCurrentUserSidString();
    const DWORD session_id = GetCurrentSessionId();
    return L"Local\\CloudOS.SystemBroker.Mutex.v21." + sid + L"." + std::to_wstring(session_id);
}

bool SecurityV21::CreatePerUserSecurityAttributes(
    SECURITY_ATTRIBUTES* out_sa,
    PSECURITY_DESCRIPTOR* out_sd)
{
    if (out_sa == nullptr || out_sd == nullptr) return false;
    *out_sd = nullptr;
    *out_sa = SECURITY_ATTRIBUTES{};

    const std::wstring sid = GetCurrentUserSidString();
    if (sid.rfind(L"S-", 0) == 0)
    {
        // Protected DACL: only the current user and LocalSystem can open the
        // server object. Client PID/token/session is validated again after
        // ConnectNamedPipe before any protocol frame is accepted.
        const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")(A;;GA;;;SY)";
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.c_str(),
                SDDL_REVISION_1,
                &descriptor,
                nullptr) &&
            descriptor != nullptr)
        {
            out_sa->nLength = sizeof(SECURITY_ATTRIBUTES);
            out_sa->lpSecurityDescriptor = descriptor;
            out_sa->bInheritHandle = FALSE;
            *out_sd = descriptor;
            return true;
        }
    }

    // Security descriptor construction must never degrade to a nullptr/default
    // DACL. If identity/SDDL resolution fails, create an empty DACL (deny all)
    // so the Broker becomes unavailable rather than broadly reachable.
    return BuildDenyAllSecurityAttributes(out_sa, out_sd);
}

bool SecurityV21::ValidateNamedPipeClient(HANDLE pipe, DWORD* out_process_id)
{
    if (out_process_id != nullptr) *out_process_id = 0;
    if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return false;
    }

    ULONG client_pid_raw = 0;
    if (!GetNamedPipeClientProcessId(pipe, &client_pid_raw) || client_pid_raw == 0)
        return false;
    const DWORD client_pid = static_cast<DWORD>(client_pid_raw);

    DWORD client_session = kInvalidSessionId;
    const DWORD broker_session = GetCurrentSessionId();
    if (broker_session == kInvalidSessionId ||
        !ProcessIdToSessionId(client_pid, &client_session) ||
        client_session != broker_session)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return false;
    }

    const std::wstring broker_sid = GetCurrentUserSidString();
    const std::wstring client_sid = ProcessUserSidString(client_pid);
    if (broker_sid.rfind(L"S-", 0) != 0 || client_sid.empty() ||
        _wcsicmp(broker_sid.c_str(), client_sid.c_str()) != 0)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return false;
    }

    if (out_process_id != nullptr) *out_process_id = client_pid;
    SetLastError(ERROR_SUCCESS);
    return true;
}

void SecurityV21::FreeSecurityDescriptor(PSECURITY_DESCRIPTOR sd)
{
    if (sd != nullptr) LocalFree(sd);
}

} // namespace CloudOS
