#pragma once

#include <Windows.h>
#include <sddl.h>

#include <string>

namespace CloudOS
{

class SecurityV21 final
{
public:
    static std::wstring GetCurrentUserSidString();
    static DWORD GetCurrentSessionId();
    static std::wstring GetCommandPipeName();
    static std::wstring GetEventsPipeName();
    static std::wstring GetBrokerMutexName();

    static bool CreatePerUserSecurityAttributes(
        SECURITY_ATTRIBUTES* out_sa,
        PSECURITY_DESCRIPTOR* out_sd);

    static void FreeSecurityDescriptor(PSECURITY_DESCRIPTOR sd);
};

} // namespace CloudOS
