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

    // Validates the OS-reported process behind a connected local named-pipe
    // client. Same-user ACL is necessary but not sufficient: reject remote,
    // vanished and cross-session callers before any RPC frame is accepted.
    static bool ValidateNamedPipeClient(HANDLE pipe, DWORD* out_process_id = nullptr);

    static void FreeSecurityDescriptor(PSECURITY_DESCRIPTOR sd);
};

} // namespace CloudOS
