$ErrorActionPreference = 'Stop'

function Replace-Once {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Old,
        [Parameter(Mandatory)] [string] $New,
        [Parameter(Mandatory)] [string] $Label
    )
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "$Label expected one match, found $count" }
    return $Text.Replace($Old, $New)
}

$bridgePath = 'desktop/CloudOS.Host/Bridge/WebMessageBridge.cs'
$bridge = Get-Content -LiteralPath $bridgePath -Raw
$oldBridge = @'
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("X-CloudOS-Host-Token", _hostLeaseToken);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request);
'@
$newBridge = @'
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("X-CloudOS-Host-Token", _hostLeaseToken);
        var launchGuardRequestJson = NativeManagedProcessClaims.CreateLaunchGuardRequestJson(
            _launchLeasesByProcessId.Values.ToArray());
        request.Content = new StringContent(launchGuardRequestJson, Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request);
'@
$bridge = Replace-Once -Text $bridge -Old $oldBridge -New $newBridge -Label 'launch-guard-request-body'
Set-Content -LiteralPath $bridgePath -Value $bridge -Encoding utf8 -NoNewline

$testsPath = 'desktop/CloudOS.Host.Tests/Program.cs'
$tests = Get-Content -LiteralPath $testsPath -Raw
$tests = Replace-Once -Text $tests `
    -Old "using System.Diagnostics;`nusing System.Runtime.InteropServices;`n" `
    -New "using System.Diagnostics;`nusing System.Globalization;`nusing System.Runtime.InteropServices;`n" `
    -Label 'culture-using'
$tests = Replace-Once -Text $tests `
    -Old "    (`"native lease identity remains stable after disposal`", NativeLeaseIdentitySurvivesDispose),`n" `
    -New "    (`"native lease identity remains stable after disposal`", NativeLeaseIdentitySurvivesDispose),`n    (`"native managed process claims bind PID to creation time`", NativeManagedProcessClaimsBindPidAndCreationTime),`n" `
    -Label 'managed-claim-test-list'

$method = @'
static void NativeManagedProcessClaimsBindPidAndCreationTime()
{
    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    var spec = NativeProcessLaunchSpec.Create(
        processPath,
        FixtureArguments("--native-contained-fixture-wait"),
        AppContext.BaseDirectory);
    using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
    lease.Resume();

    var expectedStart = lease.Process.StartTime
        .ToUniversalTime()
        .ToFileTimeUtc()
        .ToString(CultureInfo.InvariantCulture);
    var claims = NativeManagedProcessClaims.Capture([lease]);
    var claim = claims.SingleOrDefault(item => item.ProcessId == lease.ProcessId);
    Assert(claim is not null, "The active contained root PID must be exported to the launch guard.");
    Assert(claim!.StartTimeFileTimeUtc == expectedStart,
        "A managed process claim must bind PID to the exact Windows process creation time.");

    var json = NativeManagedProcessClaims.CreateLaunchGuardRequestJson([lease]);
    using var document = JsonDocument.Parse(json);
    var managed = document.RootElement.GetProperty("managedProcesses");
    Assert(managed.ValueKind == JsonValueKind.Array && managed.GetArrayLength() >= 1,
        "The Host launch request must contain a managedProcesses array.");
    var serializedClaim = managed.EnumerateArray()
        .FirstOrDefault(item => item.GetProperty("processId").GetInt32() == lease.ProcessId);
    Assert(serializedClaim.ValueKind == JsonValueKind.Object,
        "The launch request must serialize the active contained process claim.");
    Assert(serializedClaim.GetProperty("startTimeFileTimeUtc").GetString() == expectedStart,
        "FILETIME must stay a decimal string across the Host-to-backend JSON boundary.");

    Assert(lease.TryTerminate(3_000, out var terminationError),
        terminationError ?? "The managed-claim fixture Job did not terminate.");
}

'@
$tests = Replace-Once -Text $tests `
    -Old "static void NativeJobChildWindowIsQuarantined()`n" `
    -New ($method + "static void NativeJobChildWindowIsQuarantined()`n") `
    -Label 'managed-claim-test-method'
Set-Content -LiteralPath $testsPath -Value $tests -Encoding utf8 -NoNewline
