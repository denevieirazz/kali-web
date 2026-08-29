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

    [ValidateSet('Skip', 'Supported', 'FailClosed')]
    [string] $DualInstanceExpectation = 'Skip',

    [switch] $RequireDistinctChromiumProfiles,

    [ValidateRange(0, 5)]
    [int] $ReopenStressCycles = 0,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-contained-runtime')
)

$ErrorActionPreference = 'Stop'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
$collectorPath = Join-Path (Get-Location) 'scripts\collect-windows-native-containment-evidence.ps1'
$summaryPath = Join-Path $resolvedOutputDirectory "$ProofName-summary.json"
$summaryLogPath = Join-Path $resolvedOutputDirectory "$ProofName-summary.log"
$diagnosticLogPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "CloudOS\logs\browser-$([DateTime]::UtcNow.ToString('yyyyMMdd')).log"
$diagnosticStartLineCount = if (Test-Path -LiteralPath $diagnosticLogPath -PathType Leaf) { @(Get-Content -LiteralPath $diagnosticLogPath).Count } else { 0 }

function Write-Utf8Json {
    param([Parameter(Mandatory)] $Value, [Parameter(Mandatory)] [string] $Path)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 14) + [Environment]::NewLine),
        $utf8NoBom)
}

function Save-DiagnosticDelta {
    $destination = Join-Path $resolvedOutputDirectory "$ProofName-browser-diagnostics.log"
    $allLines = if (Test-Path -LiteralPath $diagnosticLogPath -PathType Leaf) {
        @(Get-Content -LiteralPath $diagnosticLogPath)
    } else { @() }
    $skip = [Math]::Min($diagnosticStartLineCount, $allLines.Count)
    $delta = @($allLines | Select-Object -Skip $skip)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($destination, $delta, $utf8NoBom)
    return [System.IO.Path]::GetFileName($destination)
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
        $cloudOsHostProcess = Get-Process -Id $HostProcessId -ErrorAction Stop
        if ($cloudOsHostProcess.ProcessName -ine 'CloudOS.Host') {
            throw "HostProcessId=$HostProcessId pertence a $($cloudOsHostProcess.ProcessName), não CloudOS.Host."
        }
        return $cloudOsHostProcess
    }

    $cloudOsHostProcesses = @(Get-Process -Name 'CloudOS.Host' -ErrorAction SilentlyContinue)
    if ($cloudOsHostProcesses.Count -ne 1) {
        throw "Era esperado exatamente um CloudOS.Host em execução; encontrados=$($cloudOsHostProcesses.Count). Informe -HostProcessId se necessário."
    }
    return $cloudOsHostProcesses[0]
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

    [DllImport("user32.dll", SetLastError = true)]
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
        {
            var nativeError = Marshal.GetLastWin32Error();
            throw new InvalidOperationException("EnumWindows failed; nativeError=" + nativeError + "; callback=" + (callbackError ?? "none"));
        }
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

function Get-CurrentContainedWindows {
    param(
        [Parameter(Mandatory)] [int] $HostPid,
        [Parameter(Mandatory)] [hashtable] $BaselineKeys
    )
    return @(Get-WindowSnapshot | Where-Object {
        $_.Visible `
            -and $_.ProcessId -ne $HostPid `
            -and $_.OwnerProcessId -eq $HostPid `
            -and -not $BaselineKeys.ContainsKey($_.Key)
    })
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
    $whiteOrBlank = Read-YesNo 'A superfície do aplicativo ficou branca, vazia ou parou de renderizar?'
    $outside = Read-YesNo 'O aplicativo apareceu como janela separada fora do CloudOS no desktop Windows?'
    $altTab = Read-YesNo 'O aplicativo apareceu como item separado no Alt+Tab do Windows?'
    $flash = Read-YesNo 'Você viu algum flash/fuga da janela externa durante esta etapa?'
    return [ordered]@{
        Stage = $Stage
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        VisibleInsideCloudOS = $inside
        WhiteOrBlankSurfaceObserved = $whiteOrBlank
        SeparateExternalDesktopWindow = $outside
        SeparateWindowsAltTabEntry = $altTab
        ExternalEscapeFlashObserved = $flash
        Pass = ($inside -and -not $whiteOrBlank -and -not $outside -and -not $altTab -and -not $flash)
    }
}

function Get-ChromiumProfileEvidence {
    param([Parameter(Mandatory)] [int[]] $ProcessIds)
    $evidence = foreach ($processId in @($ProcessIds | Select-Object -Unique)) {
        $row = $null
        try { $row = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop } catch {}
        if ($null -eq $row) {
            [pscustomobject]@{
                ProcessId = $processId
                CommandLineReadable = $false
                ExecutablePath = $null
                ProfilePath = $null
                IsolationToken = $null
                ValidPerLaunchProfile = $false
            }
            continue
        }

        $commandLine = [string]$row.CommandLine
        $match = [regex]::Match($commandLine, '(?i)(?:^|\s)(?:"--user-data-dir=([^"]+)"|--user-data-dir=([^\s"]+))')
        $profilePath = if ($match.Success) {
            if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
        } else { $null }
        $tokenMatch = if ([string]::IsNullOrWhiteSpace($profilePath)) {
            $null
        } else {
            [regex]::Match($profilePath.TrimEnd('\', '/'), '(?i)[\\/]profiles[\\/]windows[\\/][^\\/]+[\\/]([a-f0-9]{32})$')
        }
        [pscustomobject]@{
            ProcessId = $processId
            CommandLineReadable = -not [string]::IsNullOrWhiteSpace($commandLine)
            ExecutablePath = [string]$row.ExecutablePath
            ProfilePath = $profilePath
            IsolationToken = if ($null -ne $tokenMatch -and $tokenMatch.Success) { $tokenMatch.Groups[1].Value.ToLowerInvariant() } else { $null }
            ValidPerLaunchProfile = ($null -ne $tokenMatch -and $tokenMatch.Success)
        }
    }
    return @($evidence)
}

function Assert-And-RegisterChromiumProfiles {
    param(
        [Parameter(Mandatory)] $Evidence,
        [Parameter(Mandatory)] [string] $Stage,
        [Parameter(Mandatory)] [System.Collections.Generic.HashSet[string]] $SeenProfiles
    )
    $profiles = @($Evidence | Where-Object ValidPerLaunchProfile | ForEach-Object ProfilePath | Select-Object -Unique)
    if ($profiles.Count -eq 0) {
        throw "Nenhum --user-data-dir CloudOS com token de 32 hex foi comprovado em $Stage."
    }
    foreach ($profile in $profiles) {
        if (-not $SeenProfiles.Add([string]$profile)) {
            throw "O perfil Chromium foi reutilizado entre launches em ${Stage}: $profile"
        }
    }
    return $profiles
}

function New-BaselineKeyMap {
    $map = @{}
    foreach ($window in Get-WindowSnapshot) { $map[$window.Key] = $true }
    return $map
}

if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {
    throw "Collector não encontrado: $collectorPath"
}
$seenChromiumProfiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

$currentHead = (git rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[a-f0-9]{40}$') {
    throw 'Não foi possível determinar o HEAD atual do Git.'
}
if ($currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto para a prova física. esperado=$ExpectedHeadSha atual=$currentHead"
}
$branch = (git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível determinar a branch atual.' }

$cloudOsHostProcess = Resolve-HostProcess
$hostStartUtc = $cloudOsHostProcess.StartTime.ToUniversalTime().ToString('o')
Write-Host "CloudOS Host: pid=$($cloudOsHostProcess.Id) start=$hostStartUtc"
Write-Host "Git: branch=$branch sha=$currentHead"
Write-Host "Evidence: $resolvedOutputDirectory"
Write-Host ''

$proof = [ordered]@{
    SchemaVersion = 1
    Collector = 'scripts/run-windows-contained-runtime-physical-proof.ps1'
    StartedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Git = [ordered]@{ Branch = $branch; HeadSha = $currentHead }
    Host = [ordered]@{ ProcessId = $cloudOsHostProcess.Id; ProcessName = $cloudOsHostProcess.ProcessName; StartTimeUtc = $hostStartUtc }
    ProofName = $ProofName
    Open1 = $null
    MoveResize1 = $null
    Close1 = $null
    Open2 = $null
    DualInstance = $null
    Close2 = $null
    StressCycles = @()
    Diagnostics = $null
    DualInstanceExpectation = $DualInstanceExpectation
    RequireDistinctChromiumProfiles = [bool]$RequireDistinctChromiumProfiles
    ReopenStressCycles = $ReopenStressCycles
    Verdict = 'INCOMPLETE'
}
Write-Utf8Json -Value $proof -Path $summaryPath

try {
    $baseline1 = New-BaselineKeyMap
    Wait-Enter 'Abra AGORA o aplicativo Windows pelo Start Menu/App Center do CloudOS. Quando ele estiver visível DENTRO do CloudOS, pressione Enter'
    $windows1 = Wait-NewContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $baseline1 -TimeoutSeconds $OpenTimeoutSeconds
    if ($windows1.Count -eq 0) { throw 'Nenhum novo HWND visível owned pelo CloudOS Host foi detectado no open1.' }
    $pids1 = @($windows1.ProcessId | Select-Object -Unique)
    Invoke-AttachedEvidence -ProcessIds $pids1 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-open1"
    $profileEvidence1 = if ($RequireDistinctChromiumProfiles) { @(Get-ChromiumProfileEvidence -ProcessIds $pids1) } else { @() }
    if ($RequireDistinctChromiumProfiles) {
        [void](Assert-And-RegisterChromiumProfiles -Evidence $profileEvidence1 -Stage 'open1' -SeenProfiles $seenChromiumProfiles)
    }
    $screenshot1 = Join-Path $resolvedOutputDirectory "$ProofName-open1-desktop.png"
    Save-VirtualDesktopScreenshot -Path $screenshot1
    $manual1 = Read-ManualObservation -Stage 'open1'
    $proof.Open1 = [ordered]@{
        ProcessIds = $pids1
        DetectedWindows = @($windows1)
        MachineEvidence = "$ProofName-open1.json"
        MachineLog = "$ProofName-open1.log"
        Screenshot = [System.IO.Path]::GetFileName($screenshot1)
        ChromiumProfileEvidence = @($profileEvidence1)
        ManualObservation = $manual1
    }
    Write-Utf8Json -Value $proof -Path $summaryPath
    if (-not $manual1.Pass) { throw 'A observação física open1 indicou superfície branca/vazia, fuga visual/Alt+Tab ou ausência do conteúdo dentro do CloudOS.' }

    Wait-Enter 'AGORA mova e redimensione a janela interna do aplicativo dentro do CloudOS várias vezes. Quando terminar e o conteúdo estiver estável, pressione Enter'
    Start-Sleep -Milliseconds 750
    $windowsMoveResize1 = Get-CurrentContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $baseline1
    if ($windowsMoveResize1.Count -eq 0) { throw 'O aplicativo perdeu todos os HWNDs contidos após move/resize.' }
    $pidsMoveResize1 = @($windowsMoveResize1.ProcessId | Select-Object -Unique)
    Invoke-AttachedEvidence -ProcessIds $pidsMoveResize1 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-move-resize1"
    $screenshotMoveResize1 = Join-Path $resolvedOutputDirectory "$ProofName-move-resize1-desktop.png"
    Save-VirtualDesktopScreenshot -Path $screenshotMoveResize1
    $manualMoveResize1 = Read-ManualObservation -Stage 'move-resize1'
    $proof.MoveResize1 = [ordered]@{
        ProcessIds = $pidsMoveResize1
        DetectedWindows = @($windowsMoveResize1)
        MachineEvidence = "$ProofName-move-resize1.json"
        MachineLog = "$ProofName-move-resize1.log"
        Screenshot = [System.IO.Path]::GetFileName($screenshotMoveResize1)
        ManualObservation = $manualMoveResize1
    }
    Write-Utf8Json -Value $proof -Path $summaryPath
    if (-not $manualMoveResize1.Pass) { throw 'O gate move/resize detectou superfície branca/vazia ou fuga de containment.' }

    $pidsClose1 = @($pids1 + $pidsMoveResize1 | Select-Object -Unique)
    Wait-Enter 'Feche o aplicativo PELO CLOUDOS. Quando a janela interna desaparecer, pressione Enter'
    [void](Wait-ProcessesExit -ProcessIds $pidsClose1 -TimeoutSeconds $CloseTimeoutSeconds)
    Invoke-AbsentEvidence -ProcessIds $pidsClose1 -Prefix "$ProofName-close1"
    $proof.Close1 = [ordered]@{
        ProcessIds = $pidsClose1
        MachineEvidence = "$ProofName-close1.json"
        MachineLog = "$ProofName-close1.log"
    }
    Write-Utf8Json -Value $proof -Path $summaryPath

    $baseline2 = New-BaselineKeyMap
    Wait-Enter 'REABRA o mesmo aplicativo PELO CLOUDOS. Quando ele estiver visível DENTRO do CloudOS, pressione Enter'
    $windows2 = Wait-NewContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $baseline2 -TimeoutSeconds $OpenTimeoutSeconds
    if ($windows2.Count -eq 0) { throw 'Nenhum novo HWND visível owned pelo CloudOS Host foi detectado no open2.' }
    $pids2 = @($windows2.ProcessId | Select-Object -Unique)
    if (@($pids2 | Where-Object { $pidsClose1 -contains $_ }).Count -gt 0) {
        throw "O reopen reutilizou PID que deveria ter sido encerrado. close1=$($pidsClose1 -join ',') open2=$($pids2 -join ',')"
    }
    Invoke-AttachedEvidence -ProcessIds $pids2 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-open2"
    $profileEvidence2 = if ($RequireDistinctChromiumProfiles) { @(Get-ChromiumProfileEvidence -ProcessIds $pids2) } else { @() }
    if ($RequireDistinctChromiumProfiles) {
        [void](Assert-And-RegisterChromiumProfiles -Evidence $profileEvidence2 -Stage 'open2' -SeenProfiles $seenChromiumProfiles)
    }
    $screenshot2 = Join-Path $resolvedOutputDirectory "$ProofName-open2-desktop.png"
    Save-VirtualDesktopScreenshot -Path $screenshot2
    $manual2 = Read-ManualObservation -Stage 'open2-after-resize-reopen'
    $proof.Open2 = [ordered]@{
        ProcessIds = $pids2
        DetectedWindows = @($windows2)
        MachineEvidence = "$ProofName-open2.json"
        MachineLog = "$ProofName-open2.log"
        Screenshot = [System.IO.Path]::GetFileName($screenshot2)
        ChromiumProfileEvidence = @($profileEvidence2)
        ManualObservation = $manual2
    }
    Write-Utf8Json -Value $proof -Path $summaryPath
    if (-not $manual2.Pass) { throw 'O reopen após move/resize apresentou superfície branca/vazia, fuga visual/Alt+Tab ou ausência do conteúdo.' }

    if ($DualInstanceExpectation -ne 'Skip') {
        $baselineDual = New-BaselineKeyMap
        if ($DualInstanceExpectation -eq 'Supported') {
            Wait-Enter 'Com a primeira instância AINDA ABERTA, abra uma SEGUNDA instância do mesmo aplicativo pelo CloudOS. Quando as duas estiverem visíveis dentro do CloudOS, pressione Enter'
            $windowsDual = Wait-NewContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $baselineDual -TimeoutSeconds $OpenTimeoutSeconds
            if ($windowsDual.Count -eq 0) { throw 'A segunda instância esperada não criou um novo HWND contido.' }
            $pidsDual = @($windowsDual.ProcessId | Select-Object -Unique)
            if (@($pidsDual | Where-Object { $pids2 -contains $_ }).Count -gt 0) {
                throw 'A segunda instância reutilizou PID da primeira instância em vez de criar um launch independente.'
            }
            Invoke-AttachedEvidence -ProcessIds $pidsDual -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-dual"
            $profileEvidenceDual = if ($RequireDistinctChromiumProfiles) { @(Get-ChromiumProfileEvidence -ProcessIds $pidsDual) } else { @() }
            if ($RequireDistinctChromiumProfiles) {
                [void](Assert-And-RegisterChromiumProfiles -Evidence $profileEvidenceDual -Stage 'dual-instance' -SeenProfiles $seenChromiumProfiles)
            }
            $dualScreenshot = Join-Path $resolvedOutputDirectory "$ProofName-dual-desktop.png"
            Save-VirtualDesktopScreenshot -Path $dualScreenshot
            $manualDual = Read-ManualObservation -Stage 'dual-instance-supported'
            if (-not $manualDual.Pass) { throw 'A segunda instância apresentou superfície branca/vazia ou fuga de containment.' }
            $proof.DualInstance = [ordered]@{
                Expectation = 'Supported'
                ProcessIds = $pidsDual
                DetectedWindows = @($windowsDual)
                MachineEvidence = "$ProofName-dual.json"
                MachineLog = "$ProofName-dual.log"
                Screenshot = [System.IO.Path]::GetFileName($dualScreenshot)
                ChromiumProfileEvidence = @($profileEvidenceDual)
                ManualObservation = $manualDual
            }
            Write-Utf8Json -Value $proof -Path $summaryPath

            Wait-Enter 'Feche SOMENTE a segunda instância pelo CloudOS. Quando ela desaparecer e a primeira continuar aberta, pressione Enter'
            [void](Wait-ProcessesExit -ProcessIds $pidsDual -TimeoutSeconds $CloseTimeoutSeconds)
            Invoke-AbsentEvidence -ProcessIds $pidsDual -Prefix "$ProofName-dual-close"
        }
        else {
            Wait-Enter 'Com a primeira instância AINDA ABERTA, tente abrir uma segunda instância pelo CloudOS. Espere a recusa/erro fail-closed e pressione Enter'
            $unexpectedDual = Wait-NewContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $baselineDual -TimeoutSeconds ([Math]::Min(5, $OpenTimeoutSeconds))
            if ($unexpectedDual.Count -gt 0) {
                throw 'O modo FailClosed criou/adotou um novo HWND quando deveria recusar a segunda instância.'
            }
            Invoke-AttachedEvidence -ProcessIds $pids2 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-dual-failclosed-first-still-attached"
            $dualScreenshot = Join-Path $resolvedOutputDirectory "$ProofName-dual-failclosed-desktop.png"
            Save-VirtualDesktopScreenshot -Path $dualScreenshot
            $manualDual = Read-ManualObservation -Stage 'dual-instance-failclosed'
            if (-not $manualDual.Pass) { throw 'A tentativa fail-closed prejudicou a primeira instância ou causou fuga visual.' }
            $proof.DualInstance = [ordered]@{
                Expectation = 'FailClosed'
                UnexpectedWindows = @($unexpectedDual)
                FirstInstanceProcessIds = $pids2
                MachineEvidence = "$ProofName-dual-failclosed-first-still-attached.json"
                MachineLog = "$ProofName-dual-failclosed-first-still-attached.log"
                Screenshot = [System.IO.Path]::GetFileName($dualScreenshot)
                ManualObservation = $manualDual
            }
            Write-Utf8Json -Value $proof -Path $summaryPath
        }
    }

    Wait-Enter 'Feche novamente a primeira instância do aplicativo PELO CLOUDOS. Quando a janela interna desaparecer, pressione Enter'
    [void](Wait-ProcessesExit -ProcessIds $pids2 -TimeoutSeconds $CloseTimeoutSeconds)
    Invoke-AbsentEvidence -ProcessIds $pids2 -Prefix "$ProofName-close2"
    $proof.Close2 = [ordered]@{
        ProcessIds = $pids2
        MachineEvidence = "$ProofName-close2.json"
        MachineLog = "$ProofName-close2.log"
    }

    for ($cycle = 1; $cycle -le $ReopenStressCycles; $cycle++) {
        $stressBaseline = New-BaselineKeyMap
        Wait-Enter "STRESS $cycle/${ReopenStressCycles}: reabra o mesmo aplicativo pelo CloudOS e, quando estiver renderizando normalmente dentro do CloudOS, pressione Enter"
        $stressWindows = Wait-NewContainedWindows -HostPid $cloudOsHostProcess.Id -BaselineKeys $stressBaseline -TimeoutSeconds $OpenTimeoutSeconds
        if ($stressWindows.Count -eq 0) { throw "Stress cycle $cycle não detectou novo HWND contido." }
        $stressPids = @($stressWindows.ProcessId | Select-Object -Unique)
        Invoke-AttachedEvidence -ProcessIds $stressPids -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-stress-$cycle-open"
        $stressProfileEvidence = if ($RequireDistinctChromiumProfiles) { @(Get-ChromiumProfileEvidence -ProcessIds $stressPids) } else { @() }
        if ($RequireDistinctChromiumProfiles) {
            [void](Assert-And-RegisterChromiumProfiles -Evidence $stressProfileEvidence -Stage "stress-$cycle" -SeenProfiles $seenChromiumProfiles)
        }
        $stressManual = Read-ManualObservation -Stage "stress-open-$cycle"
        if (-not $stressManual.Pass) { throw "Stress cycle $cycle apresentou superfície branca/vazia ou fuga de containment." }
        Wait-Enter "STRESS $cycle/${ReopenStressCycles}: feche o aplicativo pelo CloudOS e pressione Enter quando desaparecer"
        [void](Wait-ProcessesExit -ProcessIds $stressPids -TimeoutSeconds $CloseTimeoutSeconds)
        Invoke-AbsentEvidence -ProcessIds $stressPids -Prefix "$ProofName-stress-$cycle-close"
        $proof.StressCycles += [ordered]@{
            Cycle = $cycle
            ProcessIds = $stressPids
            OpenMachineEvidence = "$ProofName-stress-$cycle-open.json"
            CloseMachineEvidence = "$ProofName-stress-$cycle-close.json"
            ChromiumProfileEvidence = @($stressProfileEvidence)
            ManualObservation = $stressManual
        }
        Write-Utf8Json -Value $proof -Path $summaryPath
    }

    $proof.Diagnostics = Save-DiagnosticDelta
    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $proof.Verdict = 'PASS'
    Write-Utf8Json -Value $proof -Path $summaryPath
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($summaryLogPath, @(
        'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: PASS',
        "proof=$ProofName",
        "head=$currentHead",
        "hostPid=$($cloudOsHostProcess.Id)",
        "open1Pids=$($pids1 -join ',')",
        "open2Pids=$($pids2 -join ',')",
        "dualExpectation=$DualInstanceExpectation",
        "stressCycles=$ReopenStressCycles",
        "diagnostics=$($proof.Diagnostics)",
        "summary=$summaryPath"
    ), $utf8NoBom)
    Write-Host ''
    Write-Host 'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: PASS' -ForegroundColor Green
    Write-Host "Summary: $summaryPath"
    Write-Host "Log:     $summaryLogPath"
}
catch {
    $proof.Diagnostics = Save-DiagnosticDelta
    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $proof.Verdict = 'FAIL'
    $proof.Error = $_.Exception.Message
    Write-Utf8Json -Value $proof -Path $summaryPath
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($summaryLogPath, @(
        'CLOUDOS WINDOWS CONTAINED RUNTIME PHYSICAL PROOF: FAIL',
        "proof=$ProofName",
        "head=$currentHead",
        "hostPid=$($cloudOsHostProcess.Id)",
        "error=$($_.Exception.Message)",
        "summary=$summaryPath"
    ), $utf8NoBom)
    throw
}
