# test-system-broker-v21-contract.ps1
# CloudOS V21 — System Broker Architectural & Contract Verification

$ErrorActionPreference = "Stop"
$root = (Get-Item "$PSScriptRoot\..\..").FullName

Write-Host "[Contract-V21] Checking V21 Architectural Constraints..."

# 1. Verify C++ SystemBroker project files exist
$brokerSrc = Join-Path $root "desktop\CloudOS.SystemBroker\src"
$requiredHeaders = @(
    "protocol_v21.h",
    "security_v21.h",
    "event_bus_v21.h",
    "job_manager_v21.h",
    "app_service_v21.h",
    "file_service_v21.h",
    "native_shell_activation_client_v21.h",
    "network_status_v21.h",
    "system_control_v21.h",
    "system_service_v21.h",
    "wsl_service_v21.h",
    "diagnostics_v21.h",
    "broker_server_v21.h"
)
foreach ($h in $requiredHeaders) {
    $p = Join-Path $brokerSrc $h
    if (-not (Test-Path $p)) {
        throw "Missing required SystemBroker header: $h"
    }
}

$requiredSources = @(
    "file_service_v21.cpp",
    "network_status_v21.cpp",
    "system_control_v21.cpp",
    "system_service_v21.cpp",
    "broker_server_v21.cpp"
)
foreach ($source in $requiredSources) {
    $p = Join-Path $brokerSrc $source
    if (-not (Test-Path $p)) {
        throw "Missing required SystemBroker source: $source"
    }
}

# 2. Verify Protocol Constants
$protoContent = Get-Content (Join-Path $brokerSrc "protocol_v21.h") -Raw
if ($protoContent -notmatch "kProtocolVersion\s*=\s*21") {
    throw "kProtocolVersion must be 21"
}
if ($protoContent -notmatch "kMaxPayloadBytes\s*=\s*1048576") {
    throw "kMaxPayloadBytes must be 1048576 (1 MiB)"
}

# 3. Verify No Arbitrary Command APIs in Protocol
$forbiddenApis = @("executeCommand", "runShell", "runPowerShell", "runWslCommand", "cmdExec", "arbitraryCommand")
foreach ($api in $forbiddenApis) {
    if ($protoContent -match $api) {
        throw "FORBIDDEN API detected in protocol: $api"
    }
}

# 4. Verify Per-User Security ACL in SecurityV21
$secContent = Get-Content (Join-Path $brokerSrc "security_v21.cpp") -Raw
if ($secContent -notmatch "D:\(A;;GA;;;") {
    throw "SecurityV21 must construct explicit per-user DACL"
}

# 5. Verify system-control writes propagate failure instead of unconditional success
$serverContent = Get-Content (Join-Path $brokerSrc "broker_server_v21.cpp") -Raw
if ($serverContent -notmatch "system_control_unavailable") {
    throw "System control failures must use the typed system_control_unavailable error"
}
if ($serverContent -notmatch "!SystemServiceV21::Instance\(\)\.SetVolume") {
    throw "BrokerServerV21 must check the SetVolume result"
}
if ($serverContent -notmatch "!SystemServiceV21::Instance\(\)\.SetBrightness") {
    throw "BrokerServerV21 must check the SetBrightness result"
}

# 6. Verify Files stays typed and allowlisted instead of accepting raw paths
$fileServiceContent = Get-Content (Join-Path $brokerSrc "file_service_v21.cpp") -Raw
if ($serverContent -notmatch 'method == "files\.list"') {
    throw "BrokerServerV21 must expose the typed files.list method"
}
if ($serverContent -notmatch "location_not_allowed") {
    throw "files.list must return a typed error for non-allowlisted locations"
}
if ($fileServiceContent -notmatch 'location == "home"' -or
    $fileServiceContent -notmatch 'location == "documents"' -or
    $fileServiceContent -notmatch 'location == "windows-c"') {
    throw "FileServiceV21 allowlist is missing required canonical location ids"
}
if ($fileServiceContent -match 'req\.payload.*path' -or $serverContent -match 'files\.list.*path') {
    throw "files.list must not expose an arbitrary raw-path request contract"
}

# 7. Verify CloudOS Browser/Terminal launch and lifecycle stay under NativeShell authority
$appServiceContent = Get-Content (Join-Path $brokerSrc "app_service_v21.cpp") -Raw
$activationContractPath = Join-Path $root "desktop\CloudOS.NativeCommon\native_shell_activation_v21.h"
$activationClientPath = Join-Path $root "desktop\CloudOS.NativeCommon\native_shell_activation_client_v21.h"
$activationServerPath = Join-Path $root "desktop\CloudOS.NativeShell\src\native_shell_activation_server_v21.h"
$shellBridgePath = Join-Path $root "desktop\CloudOS.NativeShell\src\native_shell_bridge.cpp"
$flutterBridgePath = Join-Path $root "desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp"
$activationContractContent = Get-Content $activationContractPath -Raw
$activationClientContent = Get-Content $activationClientPath -Raw
$activationServerContent = Get-Content $activationServerPath -Raw
$shellBridgeContent = Get-Content $shellBridgePath -Raw
$flutterBridgeContent = Get-Content $flutterBridgePath -Raw

if ($appServiceContent -notmatch "NativeShellActivationClientV21::Activate") {
    throw "CloudOS first-party Browser/Terminal must route through NativeShell activation"
}
if ($appServiceContent -match 'cloudos:browser[\s\S]{0,300}ShellExecuteW') {
    throw "cloudos:browser must not silently dispatch an external browser from SystemBroker"
}
if ($activationClientContent -notmatch "WM_COPYDATA" -or
    $activationClientContent -notmatch "ShellActivationV21::Request") {
    throw "NativeShell activation client must use the typed V21 activation request"
}
if ($activationClientContent -notmatch "FindWindowExW" -or
    $activationClientContent -notmatch "HWND_MESSAGE") {
    throw "NativeShell activation client must resolve the message-only activation endpoint correctly"
}
if ($activationContractContent -notmatch "SurfaceRequest" -or
    $activationContractContent -notmatch "SurfaceAction" -or
    $activationContractContent -notmatch "kSurfaceCopyDataTag") {
    throw "NativeShell lifecycle must use a separate typed V21 surface contract"
}
if ($activationServerContent -notmatch "CloudOSNativeBrowserWindow::Open") {
    throw "NativeShell Browser activation must open the CloudOS WebView2 browser surface"
}
if ($activationServerContent -notmatch "SurfaceAction::Query" -or
    $activationServerContent -notmatch "SurfaceAction::Focus" -or
    $activationServerContent -notmatch "SurfaceAction::Close") {
    throw "NativeShell must implement query/focus/close lifecycle for typed surfaces"
}
if ($shellBridgeContent -notmatch "NativeShellActivationServerV21::Start") {
    throw "NativeShellBridge must start the V21 activation server after shell initialization"
}
if ($shellBridgeContent -notmatch "NativeShellActivationServerV21::Stop") {
    throw "NativeShellBridge must stop the V21 activation server during shell shutdown"
}
if ($flutterBridgeContent -notmatch 'method == "getShellSurfaceStates"' -or
    $flutterBridgeContent -notmatch 'method == "focusShellSurface"' -or
    $flutterBridgeContent -notmatch 'method == "closeShellSurface"') {
    throw "Flutter Native Bridge must expose typed NativeShell lifecycle methods"
}
if ($flutterBridgeContent -match 'cloudos:browser[\s\S]{0,300}https://google\.com' -or
    $flutterBridgeContent -match 'cloudos:terminal[\s\S]{0,300}cmd\.exe') {
    throw "Flutter Native Bridge must not substitute external Browser/Terminal implementations"
}

# 8. Verify native modules are part of the Broker build graph
$brokerProject = Get-Content (Join-Path $root "desktop\CloudOS.SystemBroker\CloudOS.SystemBroker.vcxproj") -Raw
if ($brokerProject -notmatch "file_service_v21\.cpp") {
    throw "FileServiceV21 must be compiled by CloudOS.SystemBroker.vcxproj"
}
if ($brokerProject -notmatch "native_shell_activation_client_v21\.h") {
    throw "NativeShellActivationClientV21 compatibility include must remain visible in CloudOS.SystemBroker.vcxproj"
}
if ($brokerProject -notmatch "system_control_v21\.cpp") {
    throw "SystemControlV21 must be compiled by CloudOS.SystemBroker.vcxproj"
}
if ($brokerProject -notmatch "network_status_v21\.cpp") {
    throw "NetworkStatusV21 must be compiled by CloudOS.SystemBroker.vcxproj"
}
if ($brokerProject -notmatch "dxva2\.lib" -or $brokerProject -notmatch "wbemuuid\.lib") {
    throw "SystemControlV21 native brightness dependencies are missing from the Broker link graph"
}
if ($brokerProject -notmatch "wlanapi\.lib" -or $brokerProject -notmatch "iphlpapi\.lib") {
    throw "NetworkStatusV21 native network dependencies are missing from the Broker link graph"
}

# 9. Verify Documentation Exists
$docV21 = Join-Path $root "docs\native\SYSTEM_BROKER_V21.md"
$docSec = Join-Path $root "docs\native\SYSTEM_BROKER_SECURITY_V21.md"
if (-not (Test-Path $docV21)) {
    throw "Missing docs/native/SYSTEM_BROKER_V21.md"
}
if (-not (Test-Path $docSec)) {
    throw "Missing docs/native/SYSTEM_BROKER_SECURITY_V21.md"
}

Write-Host "[PASS] All V21 System Broker Contract Assertions Passed."