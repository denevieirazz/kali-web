#include "security_v21.h"

#include <userenv.h>

#include <vector>

namespace CloudOS
{

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
    std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = GetCurrentSessionId();
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." + std::to_wstring(session_id);
}

std::wstring SecurityV21::GetEventsPipeName()
{
    std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = GetCurrentSessionId();
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.Events.v21." + sid + L"." + std::to_wstring(session_id);
}

std::wstring SecurityV21::GetBrokerMutexName()
{
    std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = GetCurrentSessionId();
    return L"Global\\CloudOS.SystemBroker.Mutex.v21." + sid + L"." + std::to_wstring(session_id);
}

bool SecurityV21::CreatePerUserSecurityAttributes(
    SECURITY_ATTRIBUTES* out_sa,
    PSECURITY_DESCRIPTOR* out_sd)
{
    if (!out_sa || !out_sd) return false;

    std::wstring sid = GetCurrentUserSidString();
    // SDDL: Discretionary ACL allowing only current user (GA) and SYSTEM (GA)
    // No Everyone (WD), No Authenticated Users (AU)
    std::wstring sddl = L"D:(A;;GA;;;" + sid + L")(A;;GA;;;SY)";

    PSECURITY_DESCRIPTOR sd = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(),
            SDDL_REVISION_1,
            &sd,
            nullptr))
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
    if (sd)
    {
        LocalFree(sd);
    }
}

} // namespace CloudOS
