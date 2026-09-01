#include "security_v21.h"

#include <userenv.h>

#include <mutex>
#include <vector>

namespace CloudOS
{

namespace
{
struct StaticDenyAllDescriptor final
{
    SECURITY_DESCRIPTOR descriptor{};
    ACL acl{};
    bool initialized{false};
};

StaticDenyAllDescriptor& DenyAllDescriptor()
{
    static StaticDenyAllDescriptor storage;
    static std::once_flag once;
    std::call_once(once, [&]() {
        if (!InitializeSecurityDescriptor(&storage.descriptor, SECURITY_DESCRIPTOR_REVISION))
        {
            return;
        }
        if (!InitializeAcl(&storage.acl, sizeof(storage.acl), ACL_REVISION))
        {
            return;
        }
        if (!SetSecurityDescriptorDacl(&storage.descriptor, TRUE, &storage.acl, FALSE))
        {
            return;
        }
        storage.initialized = true;
    });
    return storage;
}

bool IsValidSidString(const std::wstring& sid_string)
{
    if (sid_string.empty()) return false;

    PSID sid = nullptr;
    if (!ConvertStringSidToSidW(sid_string.c_str(), &sid) || sid == nullptr)
    {
        return false;
    }

    const bool valid = IsValidSid(sid) != FALSE;
    LocalFree(sid);
    return valid;
}
} // namespace

std::wstring SecurityV21::GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    {
        return L"CURRENT_USER";
    }

    DWORD len = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &len);
    if (len == 0)
    {
        CloseHandle(token);
        return L"CURRENT_USER";
    }

    std::vector<BYTE> buffer(len);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), len, &len))
    {
        CloseHandle(token);
        return L"CURRENT_USER";
    }

    CloseHandle(token);

    auto* token_user = reinterpret_cast<TOKEN_USER*>(buffer.data());
    LPWSTR string_sid = nullptr;
    if (ConvertSidToStringSidW(token_user->User.Sid, &string_sid) && string_sid != nullptr)
    {
        std::wstring result(string_sid);
        LocalFree(string_sid);
        return result;
    }

    return L"CURRENT_USER";
}

DWORD SecurityV21::GetCurrentSessionId()
{
    DWORD session_id = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id))
    {
        return 1;
    }
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
    if (!out_sa || !out_sd) return false;

    *out_sa = {};
    *out_sd = nullptr;

    PSECURITY_DESCRIPTOR sd = nullptr;
    const std::wstring sid = GetCurrentUserSidString();

    if (IsValidSidString(sid))
    {
        // DACL permits only the current user and LocalSystem. There is no
        // Everyone/Authenticated Users ACE and handles are non-inheritable.
        const std::wstring sddl = L"D:(A;;GA;;;" + sid + L")(A;;GA;;;SY)";
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(),
            SDDL_REVISION_1,
            &sd,
            nullptr);
    }

    if (sd == nullptr)
    {
        // Security failures degrade to deny-all, never to default process ACL.
        auto& fallback = DenyAllDescriptor();
        if (!fallback.initialized)
        {
            return false;
        }
        sd = &fallback.descriptor;
    }

    out_sa->nLength = sizeof(SECURITY_ATTRIBUTES);
    out_sa->lpSecurityDescriptor = sd;
    out_sa->bInheritHandle = FALSE;
    *out_sd = sd;
    return true;
}

void SecurityV21::FreeSecurityDescriptor(PSECURITY_DESCRIPTOR sd)
{
    if (!sd) return;

    auto& fallback = DenyAllDescriptor();
    if (sd != &fallback.descriptor)
    {
        LocalFree(sd);
    }
}

} // namespace CloudOS
