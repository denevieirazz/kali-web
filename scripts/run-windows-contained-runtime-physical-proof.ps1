[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [ValidateRange(0, 2147483647)]
    [int] $HostProcessId = 0,

    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string] $ProofName = 'windows-app',

    [ValidateRange(5, 120)]
    [int] $OpenTimeoutSeconds = 30,

    [ValidateRange(5, 120)]
    [int] $CloseTimeoutSeconds = 30,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-contained-runtime')
)

$ErrorActionPreference = 'Stop'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
$collectorPath = Join-Path (Get-Location) 'scripts\collect-windows-native-containment-evidence.ps1'
$summaryPath = Join-Path $resolvedOutputDirectory "$ProofName-summary.json"
$summaryLogPath = Join-Path $resolvedOutputDirectory "$ProofName-summary.log"

function Write-Utf8Json {
    param([Parameter(Mandatory)] $Value, [Parameter(Mandatory)] [string] $Path)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 14) + [Environment]::NewLine),
        $utf8NoBom)
}

function Read-YesNo {
    param([Parameter(Mandatory)] [string] $Prompt)
    while ($true) {
        $answer = (Read-Host "$Prompt [s/n]").Trim().ToLowerInvariant()
        if ($answer -eq 's') { return $true }
        if ($answer -eq 'n') { return $false }
        Write-Host 'Responda apenas s ou n.' -ForegroundColor Yellow
    }
}

function Wait-Enter {
    param([Parameter(Mandatory)] [string] $Prompt)
    [void](Read-Host $Prompt)
}

function Resolve-HostProcess {
    if ($HostProcessId -gt 0) {
        $host = Get-Process -Id $HostProcessId -ErrorAction Stop
        if ($host.ProcessName -ine 'CloudOS.Host') {
            throw "HostProcessId=$HostProcessId pertence a $($host.ProcessName), não CloudOS.Host."
        }
        return $host
    }

    $hosts = @(Get-Process -Name 'CloudOS.Host' -ErrorAction SilentlyContinue)
    if ($hosts.Count -ne 1) {
        throw "Era esperado exatamente um CloudOS.Host em execução; encontrados=$($hosts.Count). Informe -HostProcessId se necessário."
    }
    return $hosts[0]
}

if (-not ('CloudOSNativeProofDiscovery' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class CloudOSNativeProofWindow
{
    public IntPtr Handle { get; set; }
    public uint ProcessId { get; set; }
    public IntPtr Owner { get; set; }
    public uint OwnerProcessId { get; set; }
    public bool Visible { get; set; }
    public string ClassName { get; set; }
    public string Title { get; set; }
}

public static class CloudOSNativeProofDiscovery
{
    private const uint GW_OWNER = 4;

    [return: MarshalAs(UnmanagedType.Bool)]
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint command);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr hWnd, StringBuilder className, int count);

    public static CloudOSNativeProofWindow[] Enumerate()
    {
        var result = new List<CloudOSNativeProofWindow>();
        string callbackError = null;
        EnumWindowsProc callback = delegate(IntPtr hWnd, IntPtr ignored)
        {
            try
            {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                IntPtr owner = GetWindow(hWnd, GW_OWNER);
                uint ownerProcessId = 0;
                if (owner != IntPtr.Zero) GetWindowThreadProcessId(owner, out ownerProcessId);
                var title = new StringBuilder(2048);
                var className = new StringBuilder(512);
                GetWindowTextW(hWnd, title, title.Capacity);
                GetClassNameW(hWnd, className, className.Capacity);
                result.Add(new CloudOSNativeProofWindow {
                    Handle = hWnd,
                    ProcessId = processId,
                    Owner = owner,
                    OwnerProcessId = ownerProcessId,
                    Visible = IsWindowVisible(hWnd),
                    ClassName = className.ToString(),
                    Title = title.ToString()
                });
            }
            catch (Exception error)
            {
                callbackError = error.ToString();
            }
            return true;
        };
        if (!EnumWindows(callback, IntPtr.Zero))
            throw new InvalidOperationException("EnumWindows failed; callback=" + (callbackError ?? "none"));
        if (callbackError != null)
            throw new InvalidOperationException("EnumWindows callback failed: " + callbackError);
        return result.ToArray();
    }
}
'@
}

function Get-WindowSnapshot {
    $rows = foreach ($window in [CloudOSNativeProofDiscovery]::Enumerate()) {
        [pscustomobject]@{
            Handle = ('0x{0:X}' -f $window.Handle.ToInt64())
            ProcessId = [int]$window.ProcessId
            OwnerHandle = ('0x{0:X}' -f $window.Owner.ToInt64())
            OwnerProcessId = [int]$window.OwnerProcessId
            Visible = $window.Visible
            ClassName = $window.ClassName
            Title = $window.Title
            Key = "$([int]$window.ProcessId):0x$('{0:X}' -f $window.Handle.ToInt64())"
        }
    }
    return @($rows)
}

function Wait-NewContainedWindows {
    param(
        [Parameter(Mandatory)] [int] $HostPid,
        [Parameter(Mandatory)] [hashtable] $BaselineKeys,
        [Parameter(Mandatory)] [int] $TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Get-WindowSnapshot
        $candidates = @($snapshot | Where-Object {
            $_.Visible `
                -and $_.ProcessId -ne $HostPid `
                -and $_.OwnerProcessId -eq $HostPid `
                -and -not $BaselineKeys.ContainsKey($_.Key)
        })
        if ($candidates.Count -gt 0) {
            Start-Sleep -Milliseconds 750
            $settled = Get-WindowSnapshot
            return @($settled | Where-Object {
                $_.Visible `
                    -and $_.ProcessId -ne $HostPid `
                    -and $_.OwnerProcessId -eq $HostPid `
                    -and -not $BaselineKeys.ContainsKey($_.Key)
            })
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    return @()
}

function Wait-ProcessesExit {
    param([Parameter(Mandatory)] [int[]] $ProcessIds, [Parameter(Mandatory)] [int] $TimeoutSeconds)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $alive = @($ProcessIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 100
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    return $false
}

function Save-VirtualDesktopScreenshot {
    param([Parameter(Mandatory)] [string] $Path)
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'VirtualScreen retornou dimensões inválidas.' }
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Invoke-AttachedEvidence {
    param(
        [Parameter(Mandatory)] [int[]] $ProcessIds,
        [Parameter(Mandatory)] [int] $HostPid,
        [Parameter(Mandatory)] [string] $Prefix
    )
    & $collectorPath `
        -TargetProcessId $ProcessIds `
        -ExpectedState Attached `
        -HostProcessId $HostPid `
        -OutputDirectory $resolvedOutputDirectory `
        -Prefix $Prefix
}

function Invoke-AbsentEvidence {
    param([Parameter(Mandatory)] [int[]] $ProcessIds, [Parameter(Mandatory)] [string] $Prefix)
    & $collectorPath `
        -TargetProcessId $ProcessIds `
        -ExpectedState Absent `
        -OutputDirectory $resolvedOutputDirectory `
        -Prefix $Prefix
}

function Read-ManualObservation {
    param([Parameter(Mandatory)] [string] $Stage)
    Write-Host ''
    Write-Host "OBSERVAÇÃO FÍSICA — $Stage" -ForegroundColor Cyan
    Write-Host 'Olhe o desktop inteiro, depois pressione Alt+Tab e confira a lista. Volte para este PowerShell para responder.'
    $inside = Read-YesNo 'O conteúdo do aplicativo está visível dentro da janela do CloudOS?'
    $outside = Read-YesNo 'O aplicativo apareceu como janela separada fora do CloudOS no desktop Windows?'
    $altTab = Read-YesNo 'O aplicativo apareceu como item separado no Alt+Tab do Windows?'
    $flash = Read-YesNo 'Você viu algum flash/fuga da janela externa durante a abertura?'
    return [ordered]@{
        Stage = $Stage
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        VisibleInsideCloudOS = $inside
        SeparateExternalDesktopWindow = $outside
        SeparateWindowsAltTabEntry = $altTab
        ExternalEscapeFlashObserved = $flash
        Pass = ($inside -and -not $outside -and -not $altTab -and -not $flash)
    }
}

function New-BaselineKeyMap {
    $map = @{}
    foreach ($window in Get-WindowSnapshot) { $map[$window.Key] = $true }
    return $map
}

if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {
    throw "Collector não encontrado: $collectorPath"
}

$currentHead = (git rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[a-f0-9]{40}$') {
    throw 'Não foi possível determinar o HEAD atual do Git.'
}
if ($currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto para a prova física. esperado=$ExpectedHeadSha atual=$currentHead"
}
$branch = (git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível determinar a branch atual.' }

$host = Resolve-HostProcess
$hostStartUtc = $host.StartTime.ToUniversalTime().ToString('o')
Write-Host "CloudOS Host: pid=$($host.Id) start=$hostStartUtc"
Write-Host "Git: branch=$branch sha=$currentHead"
Write-Host "Evidence: $resolvedOutputDirectory"
Write-Host ''

$proof = [ordered]@{
    SchemaVersion = 1
    Collector = 'scripts/run-windows-contained-runtime-physical-proof.ps1'
    StartedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Git = [ordered]@{ Branch = $branch; HeadSha = $currentHead }
    Host = [ordered]@{ ProcessId = $host.Id; ProcessName = $host.ProcessName; StartTimeUtc = $hostStartUtc }
    ProofName = $ProofName
    Open1 = $null
    Close1 = $null
    Open2 = $null
    Close2 = $null
    Verdict = 'INCOMPLETE'
}
Write-Utf8Json -Value $proof -Path $summaryPath

try {
    $baseline1 = New-BaselineKeyMap
    Wait-Enter 'Abra AGORA o aplicativo Windows pelo Start Menu/App Center do CloudOS. Quando ele estiver visível DENTRO do CloudOS, pressione Enter'
    $windows1 = Wait-NewContainedWindows -HostPid $host.Id -BaselineKeys $baseline1 -TimeoutSeconds $OpenTimeoutSeconds
    if ($windows1.Count -eq 0) { throw 'Nenhum novo HWND visível owned pelo CloudOS Host foi detectado no open1.' }
    $pids1 = @($windows1.ProcessId | Select-Object -Unique)
    Invoke-AttachedEvidence -ProcessIds $pids1 -HostPid $host.Id -Prefix "$ProofName-open1"
    $screenshot1 = Join-Path $resolvedOutputDirectory "$ProofName-open1-desktop.png"
    Save-VirtualDesktopScreenshot -Path $screenshot1
    $manual1 = Read-ManualObservation -Stage 'open1'
    $proof.Open1 = [ordered]@{
        ProcessIds = $pids1
        DetectedWindows = @($windows1)
        MachineEvidence = "$ProofName-open1.json"
        MachineLog = "$ProofName-open1.log"
        Screenshot = [System.IO.Path]::GetFileName($screenshot1)
        ManualObservation = $manual1
    }
    Write-Utf8Json -Value $proof -Path $summaryPath
    if (-not $manual1.Pass) { throw 'A observação física open1 indicou fuga visual/Alt+Tab ou ausência do conteúdo dentro do CloudOS.' }

    Wait-Enter 'Feche o aplicativo PELO CLOUDOS. Quando a janela interna desaparecer, pressione Enter'
    [void](Wait-ProcessesExit -ProcessIds $pids1 -TimeoutSeconds $CloseTimeoutSeconds)
    Invoke-AbsentEvidence -ProcessIds $pids1 -Prefix "$ProofName-close1"
    $proof.Close1 = [ordered]@{
        ProcessIds = $pids1
        MachineEvidence = "$ProofName-close1.json"
        MachineLog = "$ProofName-close1.log"
    }
    Write-Utf8Json -Value $proof -Path $summaryPath

    $baseline2 = New-BaselineKeyMap
    Wait-Enter 'REABRA o mesmo aplicativo PELO CLOUDOS. Quando ele estiver visível DENTRO do CloudOS, pressione Enter'
    $windows2 = Wait-NewContainedWindows -HostPid $host.Id -BaselineKeys $baseline2 -TimeoutSeconds $OpenTimeoutSeconds
    if ($windows2.Count -eq 0) { throw 'Nenhum novo HWND visível owned pelo CloudOS Host foi detectado no open2.' }
    $pids2 = @($windows2.ProcessId | Select-Object -Unique)
    if (@($pids2 | Where-Object { $pids1 -contains $_ }).Count -gt 0) {
        throw "O reopen reutilizou PID que deveria ter sido encerrado. open1=$($pids1 -join ',') open2=$($pids2 -join ',')"
    }
    Invoke-AttachedEvidence -ProcessIds $pids2 -HostPid $host.Id -Prefix "$ProofName-open2"
    $screenshot2 = Join-Path $resolvedOutputDirectory "$ProofName-open2-desktop.png"
    Save-VirtualDesktopScreenshot -Path $screenshot2
    $manual2 = Read-ManualObservation -Stage 'open2'
    $proof.Open2 = [ordered]@{
        ProcessIds = $pids2
        DetectedWindows = @($windows2)
        MachineEvidence = "$ProofName-open2.json"
        MachineLog = "$ProofName-open2.log"
        Screenshot = [System.IO.Path]::GetFileName($screenshot2)
        ManualObservation = $manual2
    }
    Write-Utf8Json -Value $proof -Path $summaryPath
    if (-not $manual2.Pass) { throw 'A observação física open2 indicou fuga visual/Alt+Tab ou ausência do conteúdo dentro do CloudOS.' }

    Wait-Enter 'Feche novamente o aplicativo PELO CLOUDOS. Quando a janela interna desaparecer, pressione Enter'
    [void](Wait-ProcessesExit -ProcessIds $pids2 -TimeoutSeconds $CloseTimeoutSeconds)
    Invoke-AbsentEvidence -ProcessIds $pids2 -Prefix "$ProofName-close2"
    $proof.Close2 = [ordered]@{
        ProcessIds = $pids2
        MachineEvidence = "$ProofName-close2.json"
        MachineLog = "$ProofName-close2.log"
    }

    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $proof.Verdict = 'PASS'
    Write-Utf8Json -Value $proof -Path $summaryPath
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($summaryLogPath, @(
        'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: PASS',
        "proof=$ProofName",
        "head=$currentHead",
        "hostPid=$($host.Id)",
        "open1Pids=$($pids1 -join ',')",
        "open2Pids=$($pids2 -join ',')",
        "summary=$summaryPath"
    ), $utf8NoBom)
    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: PASS' -ForegroundColor Green
    Write-Host "Summary: $summaryPath"
    Write-Host "Log:     $summaryLogPath"
}
catch {
    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $proof.Verdict = 'FAIL'
    $proof.Error = $_.Exception.Message
    Write-Utf8Json -Value $proof -Path $summaryPath
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($summaryLogPath, @(
        'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: FAIL',
        "proof=$ProofName",
        "head=$currentHead",
        "hostPid=$($host.Id)",
        "error=$($_.Exception.Message)",
        "summary=$summaryPath"
    ), $utf8NoBom)
    throw
}
