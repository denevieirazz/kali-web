#include "security_v21.h"

#include <userenv.h>

#include <vector>

namespace CloudOS
{

std::wstring SecurityV21::GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};

    DWORD len = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &len);
    if (len == 0)
    {
        CloseHandle(token);
        return {};
    }

    std::vector<BYTE> buffer(len);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), len, &len))
    {
        CloseHandle(token);
        return {};
    }
    CloseHandle(token);

    const auto* token_user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
    if (!token_user->User.Sid || !IsValidSid(token_user->User.Sid)) return {};

    LPWSTR string_sid = nullptr;
    if (ConvertSidToStringSidW(token_user->User.Sid, &string_sid) && string_sid != nullptr)
    {
        std::wstring result(string_sid);
        LocalFree(string_sid);
        return result;
    }
    return {};
}

DWORD SecurityV21::GetCurrentSessionId()
{
    DWORD session_id = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id)) return 0;
    return session_id;
}

std::wstring SecurityV21::GetCommandPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    if (sid.empty()) return {};
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." + std::to_wstring(GetCurrentSessionId());
}

std::wstring SecurityV21::GetEventsPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    if (sid.empty()) return {};
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.Events.v21." + sid + L"." + std::to_wstring(GetCurrentSessionId());
}

std::wstring SecurityV21::GetBrokerMutexName()
{
    const std::wstring sid = GetCurrentUserSidString();
    if (sid.empty()) return {};
    return L"Local\\CloudOS.SystemBroker.Mutex.v21." + sid + L"." + std::to_wstring(GetCurrentSessionId());
}

bool SecurityV21::CreatePerUserSecurityAttributes(
    SECURITY_ATTRIBUTES* out_sa,
    PSECURITY_DESCRIPTOR* out_sd)
{
    if (!out_sa || !out_sd) return false;
    *out_sd = nullptr;

    const std::wstring sid = GetCurrentUserSidString();
    if (sid.empty()) return false;

    // Explicit DACL: current user + LocalSystem only. Never fall back to a
    // process-default DACL if identity resolution fails.
    const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")(A;;GA;;;SY)";

    PSECURITY_DESCRIPTOR sd = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(), SDDL_REVISION_1, &sd, nullptr))
    {
        return false;
    }

    out_sa->nLength = sizeof(SECURITY_ATTRIBUTES);
    out_sa->lpSecurityDescriptor = sd;
    out_sa->bInheritHandle = FALSE;
    *out_sd = sd;
    return true;
}

void SecurityV21::FreeSecurityDescriptor(PSECURITY_DESCRIPTOR sd)
{
    if (sd) LocalFree(sd);
}

} // namespace CloudOS
