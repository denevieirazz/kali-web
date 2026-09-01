#pragma once

// Generated Windows runner compatibility shim.
//
// cloudos_flutter_bridge_v20.cpp is authored in native_bridge/, where
// ../../CloudOS.NativeCommon resolves to desktop/CloudOS.NativeCommon.
// The Flutter CI/local host generator copies that same .cpp into windows/runner/;
// from there the identical relative include resolves through this directory.
// Keep the implementation authoritative in desktop/CloudOS.NativeCommon.
#include "../../CloudOS.NativeCommon/native_shell_activation_client_v21.h"