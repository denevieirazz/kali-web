#pragma once

#include "protocol_v21.h"

#include <chrono>
#include <mutex>

namespace CloudOS
{

class DiagnosticsV21 final
{
public:
    static void Initialize();
    static JsonObject GetDiagnosticsSnapshot();

private:
    static inline std::once_flag init_once_;
    static inline std::chrono::steady_clock::time_point start_time_;
};

} // namespace CloudOS
