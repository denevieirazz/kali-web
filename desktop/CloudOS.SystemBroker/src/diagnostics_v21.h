#pragma once

#include "protocol_v21.h"

#include <chrono>

namespace CloudOS
{

class DiagnosticsV21 final
{
public:
    static void Initialize();
    static JsonObject GetDiagnosticsSnapshot();

private:
    static inline std::chrono::steady_clock::time_point start_time_;
};

} // namespace CloudOS
