#include "diagnostics_v21.h"
#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "job_manager_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

namespace CloudOS
{

void DiagnosticsV21::Initialize()
{
    start_time_ = std::chrono::steady_clock::now();
}

JsonObject DiagnosticsV21::GetDiagnosticsSnapshot()
{
    auto now = std::chrono::steady_clock::now();
    int64_t uptime_sec = std::chrono::duration_cast<std::chrono::seconds>(now - start_time_).count();

    JsonObject obj;
    obj["brokerVersion"] = JsonValue("21.0.0");
    obj["protocolVersion"] = JsonValue(kProtocolVersion);
    obj["uptimeSec"] = JsonValue(uptime_sec);
    obj["connectedClients"] = JsonValue(static_cast<int64_t>(EventBusV21::Instance().GetActiveClientCount()));
    obj["activeJobs"] = JsonValue(static_cast<int64_t>(JobManagerV21::Instance().GetActiveJobCount()));
    obj["appsGeneration"] = JsonValue(static_cast<int64_t>(AppServiceV21::Instance().GetGeneration()));
    obj["systemGeneration"] = JsonValue(static_cast<int64_t>(SystemServiceV21::Instance().GetGeneration()));
    obj["wslGeneration"] = JsonValue(static_cast<int64_t>(WslServiceV21::Instance().GetGeneration()));
    obj["wslAvailable"] = JsonValue(WslServiceV21::Instance().IsWslAvailable());
    obj["distroCount"] = JsonValue(static_cast<int64_t>(WslServiceV21::Instance().GetDistributions().size()));
    return obj;
}

} // namespace CloudOS
