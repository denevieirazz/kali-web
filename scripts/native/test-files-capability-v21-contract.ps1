[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = (Get-Item "$PSScriptRoot\..\..").FullName

$fileHeaderPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\file_service_v21.h'
$fileCppPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\file_service_v21.cpp'
$serverPath = Join-Path $root 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp'
$clientPath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_broker_client_v21.h'
$nativeBridgePath = Join-Path $root 'desktop\CloudOS.FlutterShell\native_bridge\cloudos_flutter_bridge_v20.cpp'
$dartBridgePath = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\services\cloudos_bridge.dart'
$modelPath = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\models\cloud_file_item.dart'
$filesWindowPath = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\files\presentation\files_window.dart'
$gridPath = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\files\presentation\widgets\files_grid.dart'
$listPath = Join-Path $root 'desktop\CloudOS.FlutterShell\lib\features\files\presentation\widgets\files_list.dart'

foreach ($path in @($fileHeaderPath, $fileCppPath, $serverPath, $clientPath, $nativeBridgePath, $dartBridgePath, $modelPath, $filesWindowPath, $gridPath, $listPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Files capability V21 contract input is missing: $path"
    }
}

$fileHeader = Get-Content -LiteralPath $fileHeaderPath -Raw
$fileCpp = Get-Content -LiteralPath $fileCppPath -Raw
$server = Get-Content -LiteralPath $serverPath -Raw
$client = Get-Content -LiteralPath $clientPath -Raw
$nativeBridge = Get-Content -LiteralPath $nativeBridgePath -Raw
$dartBridge = Get-Content -LiteralPath $dartBridgePath -Raw
$model = Get-Content -LiteralPath $modelPath -Raw
$filesWindow = Get-Content -LiteralPath $filesWindowPath -Raw
$grid = Get-Content -LiteralPath $gridPath -Raw
$list = Get-Content -LiteralPath $listPath -Raw

if ($fileHeader -notmatch 'std::string\s+entry_id' -or
    $fileHeader -notmatch 'kCapabilityLifetime\s*=\s*std::chrono::minutes\(30\)' -or
    $fileHeader -notmatch 'kMaxCapabilities\s*=\s*4096') {
    throw 'FileServiceV21 must expose bounded, expiring opaque entry capabilities.'
}
if ($fileCpp -notmatch 'CoCreateGuid' -or
    $fileCpp -notmatch 'ResolveCapability' -or
    $fileCpp -notmatch 'ListEntry' -or
    $fileCpp -notmatch 'OpenEntry') {
    throw 'FileServiceV21 capability issuance/resolution/list/open implementation is incomplete.'
}
if ($server -notmatch 'method == "files\.listEntry"' -or
    $server -notmatch 'method == "files\.openEntry"') {
    throw 'BrokerServerV21 must expose typed files.listEntry and files.openEntry methods.'
}
if ($server -match 'req\.payload\.find\("path"\)' -or
    $server -match 'req\.payload\["path"\]') {
    throw 'BrokerServerV21 must never accept a raw Files path request parameter.'
}
if ($server -notmatch 'req\.payload\.find\("entryId"\)') {
    throw 'Files capability actions must accept entryId rather than a raw path.'
}
if ($client -notmatch 'GetFilesEntry' -or
    $client -notmatch 'OpenFileEntry' -or
    $client -notmatch 'payload\["entryId"\]') {
    throw 'Flutter Broker client must carry only typed Files entry capabilities.'
}
if ($nativeBridge -notmatch 'method == "getFilesEntry"' -or
    $nativeBridge -notmatch 'method == "openFileEntry"' -or
    $nativeBridge -notmatch 'files_capability_actions') {
    throw 'Flutter Native Bridge must expose Files capability navigation/open methods.'
}
if ($dartBridge -notmatch 'loadFilesEntry' -or
    $dartBridge -notmatch 'openFileEntry' -or
    $dartBridge -notmatch "'entryId': entryId") {
    throw 'Dart bridge must use opaque entryId capabilities for Files actions.'
}
if ($model -notmatch 'final String\? entryId') {
    throw 'CloudFileItem must preserve the opaque native entry capability.'
}
if ($filesWindow -notmatch '_openItem' -or
    $filesWindow -notmatch 'loadFilesEntry' -or
    $filesWindow -notmatch 'openFileEntry') {
    throw 'FilesWindow must navigate folders and open files through capability methods.'
}
if ($grid -notmatch 'onDoubleTap' -or $list -notmatch 'onDoubleTap') {
    throw 'Both Files grid and list presentations must expose double-click activation.'
}

Write-Host 'PASS: Files Capability V21 protects expiring opaque entry IDs, path-free action requests and real nested/open UI behavior.'
