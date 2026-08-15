param(
    [switch]$AllowNonCi
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:CI -ne 'true' -and -not $AllowNonCi) {
    throw 'Este smoke usa o perfil local do Windows. Rode-o somente no CI ou em VM/Sandbox descartável com -AllowNonCi.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hostDll = Join-Path $repoRoot 'desktop\CloudOS.Host\bin\Release\net8.0-windows10.0.19041.0\CloudOS.Host.dll'
$clientScript = Join-Path $repoRoot 'scripts\native-browser-host-smoke-client.mjs'
if (-not (Test-Path $hostDll)) { throw "CloudOS.Host não compilado no target esperado: $hostDll" }
if (-not (Test-Path $clientScript)) { throw "Cliente de smoke ausente: $clientScript" }

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$cloudRoot = Join-Path $localAppData 'CloudOS'
if ($env:CI -eq 'true') {
    if (Test-Path $cloudRoot) { Remove-Item $cloudRoot -Recurse -Force }
} elseif (Test-Path $cloudRoot) {
    throw 'Perfil local CloudOS já existe. Use uma VM/Sandbox descartável; o smoke não tocará dados locais existentes.'
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function ConvertTo-SanitizedSmokeText([string]$Text, [string]$EphemeralPassword) {
    $detail = if ($null -eq $Text) { '' } else { [string]$Text }
    if (-not [string]::IsNullOrEmpty($EphemeralPassword)) {
        $detail = $detail.Replace($EphemeralPassword, '<redacted>', [StringComparison]::Ordinal)
    }
    $detail = [regex]::Replace(
        $detail,
        '(?i)(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\s*[:=]\s*|\s+)[^\s,;]+',
        '$1=<redacted>')
    $detail = $detail.Replace("`r", ' ').Replace("`n", ' ')
    if ($detail.Length -gt 512) { $detail = $detail.Substring(0, 512) + '<truncated>' }
    return $detail
}

if (-not ('CloudOSSmoke.WindowApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CloudOSSmoke {
    public static class WindowApi {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        private const uint WM_CLOSE = 0x0010;

        public static IntPtr FindWindow(int processId, string titleFragment) {
            IntPtr found = IntPtr.Zero;
            EnumWindows((hWnd, _) => {
                if (!IsWindowVisible(hWnd)) return true;
                GetWindowThreadProcessId(hWnd, out var pid);
                if (pid != processId) return true;
                var buffer = new StringBuilder(512);
                GetWindowText(hWnd, buffer, buffer.Capacity);
                if (buffer.ToString().IndexOf(titleFragment, StringComparison.OrdinalIgnoreCase) < 0) return true;
                found = hWnd;
                return false;
            }, IntPtr.Zero);
            return found;
        }

        public static bool CloseWindow(IntPtr hWnd) => hWnd != IntPtr.Zero && PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }
}
'@
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Failure) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 250
    }
    throw $Failure
}

function Find-RuntimeManifest([int]$HostPid) {
    $runtimeRoot = Join-Path $cloudRoot 'runtime'
    if (-not (Test-Path $runtimeRoot)) { return $null }
    foreach ($file in Get-ChildItem $runtimeRoot -Filter 'backend-port.json' -Recurse -File -ErrorAction SilentlyContinue) {
        try {
            $manifest = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ([int]$manifest.parentPid -eq $HostPid) { return $manifest }
        } catch {
            Write-Verbose "Manifest runtime ainda não pôde ser lido: $($_.Exception.GetType().Name)"
            continue
        }
    }
    return $null
}

function Get-DescendantPids([int]$RootPid) {
    $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
    $children = @{}
    foreach ($process in $all) {
        $parent = [int]$process.ParentProcessId
        if (-not $children.ContainsKey($parent)) { $children[$parent] = [System.Collections.Generic.List[int]]::new() }
        $children[$parent].Add([int]$process.ProcessId)
    }
    $result = [System.Collections.Generic.HashSet[int]]::new()
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($RootPid)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $children.ContainsKey($current)) { continue }
        foreach ($child in $children[$current]) {
            if ($result.Add($child)) { $queue.Enqueue($child) }
        }
    }
    return @($result)
}

function Get-BrowserReadyCount {
    $logRoot = Join-Path $cloudRoot 'logs'
    if (-not (Test-Path $logRoot)) { return 0 }
    $count = 0
    foreach ($file in Get-ChildItem $logRoot -Filter 'browser-*.log' -File -ErrorAction SilentlyContinue) {
        $count += @(Select-String -Path $file.FullName -Pattern ' webview_ready(?: |$)' -ErrorAction SilentlyContinue).Count
    }
    return $count
}

function Get-SanitizedBrowserLifecycleEvents([string[]]$Lines) {
    $events = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -match '^(?<timestamp>\S+)\s+(?<event>[A-Za-z0-9_-]{1,64})(?:\s|$)') {
            $events.Add("$($Matches.timestamp) $($Matches.event)")
        }
    }
    return @($events)
}

function Assert-BridgeReplyPrecedesInitialization {
    $logRoot = Join-Path $cloudRoot 'logs'
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $logPath = $null
    $lines = @()

    while ([DateTime]::UtcNow -lt $deadline) {
        $candidates = @(Get-ChildItem $logRoot -Filter 'browser-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)
        foreach ($candidate in $candidates) {
            $candidateLines = @(Get-Content $candidate.FullName -ErrorAction SilentlyContinue)
            if (@($candidateLines | Where-Object { $_ -match ' bridge_received(?: |$)' }).Count -eq 0) { continue }
            $logPath = $candidate.FullName
            $lines = $candidateLines
            if (($lines -join "`n") -match ' bridge_replied ok=true' -and
                ($lines -join "`n") -match ' webview_initialization_started(?: |$)') {
                break
            }
        }
        if ($null -ne $logPath -and
            ($lines -join "`n") -match ' bridge_replied ok=true' -and
            ($lines -join "`n") -match ' webview_initialization_started(?: |$)') {
            break
        }
        Start-Sleep -Milliseconds 250
    }

    if ($null -eq $logPath) {
        throw 'Lifecycle Browser ausente: nenhum browser-*.log com bridge_received foi encontrado.'
    }

    $replyIndex = -1
    $initializationIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($replyIndex -lt 0 -and $lines[$index] -match ' bridge_replied ok=true') { $replyIndex = $index }
        if ($initializationIndex -lt 0 -and $lines[$index] -match ' webview_initialization_started(?: |$)') { $initializationIndex = $index }
    }
    if ($replyIndex -lt 0 -or $initializationIndex -lt 0 -or $replyIndex -ge $initializationIndex) {
        $observed = @(Get-SanitizedBrowserLifecycleEvents $lines)
        $summary = if ($observed.Count -eq 0) { '<none>' } else { $observed -join ' | ' }
        throw "Lifecycle Browser inválido. replyIndex=$replyIndex initIndex=$initializationIndex events=$summary"
    }
}

$debugPort = Get-FreePort
$dotnet = (Get-Command dotnet).Source
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $dotnet
$psi.UseShellExecute = $false
$psi.WorkingDirectory = $repoRoot
$psi.ArgumentList.Add($hostDll)
$psi.ArgumentList.Add('--root')
$psi.ArgumentList.Add($repoRoot)
$psi.ArgumentList.Add('--developer-mode')
$psi.Environment['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'] = "--remote-debugging-port=$debugPort"
$hostProcess = [System.Diagnostics.Process]::new()
$hostProcess.StartInfo = $psi

$runtimeManifest = $null
$backendPid = 0
$ownedDescendants = @()
$smokeUsername = 'cloudos.smoke'
$randomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
$smokePassword = 'Aa1!' + [Convert]::ToHexString($randomBytes) + '-z!'
try {
    if (-not $hostProcess.Start()) { throw 'CloudOS.Host não iniciou.' }
    Write-Host "HOST_PID=$($hostProcess.Id)"

    Wait-Until { $script:runtimeManifest = Find-RuntimeManifest $hostProcess.Id; $null -ne $script:runtimeManifest } 45 'Backend runtime não ficou pronto.'
    $runtimeManifest = $script:runtimeManifest
    $backendPid = [int]$runtimeManifest.pid
    $apiBase = [string]$runtimeManifest.apiBase
    if (-not $apiBase.StartsWith('http://127.0.0.1:', [StringComparison]::Ordinal)) { throw 'Backend não está no loopback esperado.' }

    $healthBefore = Invoke-RestMethod -Uri "$apiBase/api/health" -Method Get -TimeoutSec 5
    if (-not $healthBefore) { throw 'Health inicial do backend falhou.' }

    $adminBody = @{
        displayName = 'CloudOS Smoke'
        username = $smokeUsername
        password = $smokePassword
        confirmPassword = $smokePassword
    } | ConvertTo-Json -Compress
    $setupResponse = Invoke-WebRequest `
        -Uri "$apiBase/api/setup/admin" `
        -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Headers @{ Accept = 'application/json' } `
        -Body $adminBody `
        -SkipHttpErrorCheck `
        -TimeoutSec 10
    if ([int]$setupResponse.StatusCode -ne 201) {
        $safeDetail = ConvertTo-SanitizedSmokeText -Text ([string]$setupResponse.Content) -EphemeralPassword $smokePassword
        throw "SETUP_ADMIN_FAILED status=$([int]$setupResponse.StatusCode) detail=$safeDetail"
    }

    $openRaw = & node $clientScript --port $debugPort --action open-twice
    if ($LASTEXITCODE -ne 0) { throw 'Cliente CDP falhou ao abrir Browser concorrentemente.' }
    $open = $openRaw | ConvertFrom-Json
    foreach ($result in @($open.first, $open.second)) {
        if (-not [bool]$result.opened -or -not [bool]$result.windowVisible) {
            throw 'browser.open não confirmou janela visível.'
        }
    }
    $reuseValues = @([bool]$open.first.reused, [bool]$open.second.reused)
    if (@($reuseValues | Where-Object { $_ }).Count -ne 1 -or @($reuseValues | Where-Object { -not $_ }).Count -ne 1) {
        throw 'Duas chamadas concorrentes de browser.open não reutilizaram uma única BrowserWindow.'
    }
    Assert-BridgeReplyPrecedesInitialization

    $firstBrowserHandle = [IntPtr]::Zero
    Wait-Until { $script:firstBrowserHandle = [CloudOSSmoke.WindowApi]::FindWindow($hostProcess.Id, 'Navegador CloudOS'); $script:firstBrowserHandle -ne [IntPtr]::Zero } 10 'BrowserWindow não apareceu após browser.open.'
    $firstBrowserHandle = $script:firstBrowserHandle
    if (-not [CloudOSSmoke.WindowApi]::CloseWindow($firstBrowserHandle)) { throw 'WM_CLOSE da primeira BrowserWindow falhou.' }
    Wait-Until { [CloudOSSmoke.WindowApi]::FindWindow($hostProcess.Id, 'Navegador CloudOS') -eq [IntPtr]::Zero } 15 'Primeira BrowserWindow não fechou.'

    $readyBeforeUi = Get-BrowserReadyCount
    $previousUser = $env:CLOUDOS_SMOKE_USERNAME
    $previousPassword = $env:CLOUDOS_SMOKE_PASSWORD
    try {
        $env:CLOUDOS_SMOKE_USERNAME = $smokeUsername
        $env:CLOUDOS_SMOKE_PASSWORD = $smokePassword
        $uiRaw = & node $clientScript --port $debugPort --action open-via-start
    } finally {
        if ($null -eq $previousUser) { Remove-Item Env:CLOUDOS_SMOKE_USERNAME -ErrorAction SilentlyContinue } else { $env:CLOUDOS_SMOKE_USERNAME = $previousUser }
        if ($null -eq $previousPassword) { Remove-Item Env:CLOUDOS_SMOKE_PASSWORD -ErrorAction SilentlyContinue } else { $env:CLOUDOS_SMOKE_PASSWORD = $previousPassword }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Fluxo Menu Iniciar -> Browser falhou.' }
    $ui = $uiRaw | ConvertFrom-Json
    if (-not $ui.desktopMounted -or -not $ui.launcherSeen -or -not $ui.launcherGone) {
        throw 'Shell/Menu Iniciar/launcher não completaram o fluxo esperado.'
    }

    $browserHandle = [IntPtr]::Zero
    Wait-Until { $script:browserHandle = [CloudOSSmoke.WindowApi]::FindWindow($hostProcess.Id, 'Navegador CloudOS'); $script:browserHandle -ne [IntPtr]::Zero } 10 'BrowserWindow aberta pelo Menu Iniciar não ficou visível.'
    $browserHandle = $script:browserHandle
    Wait-Until { (Get-BrowserReadyCount) -gt $readyBeforeUi } 30 'WebView2 da BrowserWindow aberta pelo Menu Iniciar não ficou pronto.'

    $reuseRaw = & node $clientScript --port $debugPort --action open-once
    if ($LASTEXITCODE -ne 0) { throw 'browser.open após janela aberta falhou.' }
    $reuse = $reuseRaw | ConvertFrom-Json
    if (-not $reuse.opened.opened -or -not $reuse.opened.reused -or -not $reuse.opened.windowVisible) {
        throw 'browser.open após janela aberta não restaurou/reutilizou a BrowserWindow.'
    }
    $handleAfterReuse = [CloudOSSmoke.WindowApi]::FindWindow($hostProcess.Id, 'Navegador CloudOS')
    if ($handleAfterReuse -ne $browserHandle) { throw 'browser.open reutilizado criou/trocou o HWND inesperadamente.' }

    if (-not [CloudOSSmoke.WindowApi]::CloseWindow($browserHandle)) { throw 'WM_CLOSE da BrowserWindow aberta pelo Menu Iniciar falhou.' }
    Wait-Until { [CloudOSSmoke.WindowApi]::FindWindow($hostProcess.Id, 'Navegador CloudOS') -eq [IntPtr]::Zero } 15 'BrowserWindow não fechou.'

    if ($hostProcess.HasExited) { throw 'Fechar Browser encerrou o Shell.' }
    $healthAfterBrowserClose = Invoke-RestMethod -Uri "$apiBase/api/health" -Method Get -TimeoutSec 5
    if (-not $healthAfterBrowserClose) { throw 'Backend parou após fechar Browser.' }

    $pingRaw = & node $clientScript --port $debugPort --action ping
    if ($LASTEXITCODE -ne 0) { throw 'Shell WebView2 ficou indisponível após fechar Browser.' }
    $ping = $pingRaw | ConvertFrom-Json
    if (-not $ping.nativeHost -or $ping.platform -ne 'windows') { throw 'Bridge do Shell não respondeu após fechar Browser.' }

    $ownedDescendants = Get-DescendantPids $hostProcess.Id
    if ($ownedDescendants -notcontains $backendPid) { throw 'Backend não pertence à árvore do Host.' }

    if (-not $hostProcess.CloseMainWindow()) { throw 'MainWindow do Host recusou fechamento gracioso.' }
    Wait-Until { $hostProcess.Refresh(); $hostProcess.HasExited } 30 'Host não encerrou graciosamente.'
    Wait-Until {
        foreach ($pid in $ownedDescendants) {
            if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { return $false }
        }
        return $true
    } 20 'Processos filhos do Host permaneceram após encerramento.'

    Write-Host 'PASS native browser host smoke'
} finally {
    Remove-Item Env:CLOUDOS_SMOKE_USERNAME -ErrorAction SilentlyContinue
    Remove-Item Env:CLOUDOS_SMOKE_PASSWORD -ErrorAction SilentlyContinue
    if ($hostProcess -and -not $hostProcess.HasExited) {
        & taskkill /PID $hostProcess.Id /T /F | Out-Null
        $hostProcess.WaitForExit(10000) | Out-Null
    }
    $hostProcess.Dispose()
    if ($env:CI -eq 'true' -and (Test-Path $cloudRoot)) {
        Remove-Item $cloudRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
