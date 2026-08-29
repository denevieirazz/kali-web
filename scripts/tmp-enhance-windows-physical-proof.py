from pathlib import Path

proof_path = Path('scripts/run-windows-contained-runtime-physical-proof.ps1')
test_path = Path('backend/test/windows-physical-proof-contract.test.js')
proof = proof_path.read_text(encoding='utf-8')
tests = test_path.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


proof = replace_once(
    proof,
    "    [ValidateRange(5, 120)]\n    [int] $CloseTimeoutSeconds = 30,\n\n    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\\windows-contained-runtime')\n",
    "    [ValidateRange(5, 120)]\n    [int] $CloseTimeoutSeconds = 30,\n\n    [ValidateSet('Skip', 'Supported', 'FailClosed')]\n    [string] $DualInstanceExpectation = 'Skip',\n\n    [switch] $RequireDistinctChromiumProfiles,\n\n    [ValidateRange(0, 5)]\n    [int] $ReopenStressCycles = 0,\n\n    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\\windows-contained-runtime')\n",
    'proof-parameters'
)

proof = replace_once(
    proof,
    "$summaryLogPath = Join-Path $resolvedOutputDirectory \"$ProofName-summary.log\"\n",
    "$summaryLogPath = Join-Path $resolvedOutputDirectory \"$ProofName-summary.log\"\n"
    "$diagnosticLogPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) \"CloudOS\\logs\\browser-$([DateTime]::UtcNow.ToString('yyyyMMdd')).log\"\n"
    "$diagnosticStartLineCount = if (Test-Path -LiteralPath $diagnosticLogPath -PathType Leaf) { @(Get-Content -LiteralPath $diagnosticLogPath).Count } else { 0 }\n",
    'diagnostic-checkpoint'
)

proof = replace_once(
    proof,
    "function Read-YesNo {\n",
    r'''function Save-DiagnosticDelta {
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
''',
    'diagnostic-delta-function'
)

proof = replace_once(
    proof,
    "function Wait-ProcessesExit {\n",
    r'''function Get-CurrentContainedWindows {
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
''',
    'current-contained-windows'
)

old_manual = r'''function Read-ManualObservation {
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
'''
new_manual = r'''function Read-ManualObservation {
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
'''
proof = replace_once(proof, old_manual, new_manual, 'manual-white-surface')

proof = replace_once(
    proof,
    "function New-BaselineKeyMap {\n",
    r'''function Get-ChromiumProfileEvidence {
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
            throw "O perfil Chromium foi reutilizado entre launches em $Stage: $profile"
        }
    }
    return $profiles
}

function New-BaselineKeyMap {
''',
    'chromium-profile-proof'
)

proof = replace_once(
    proof,
    "if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {\n    throw \"Collector não encontrado: $collectorPath\"\n}\n",
    "if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {\n    throw \"Collector não encontrado: $collectorPath\"\n}\n"
    "$seenChromiumProfiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)\n",
    'profile-seen-set'
)

proof = replace_once(
    proof,
    "    Open1 = $null\n    Close1 = $null\n    Open2 = $null\n    Close2 = $null\n    Verdict = 'INCOMPLETE'\n",
    "    Open1 = $null\n    MoveResize1 = $null\n    Close1 = $null\n    Open2 = $null\n    DualInstance = $null\n    Close2 = $null\n    StressCycles = @()\n    Diagnostics = $null\n    DualInstanceExpectation = $DualInstanceExpectation\n    RequireDistinctChromiumProfiles = [bool]$RequireDistinctChromiumProfiles\n    ReopenStressCycles = $ReopenStressCycles\n    Verdict = 'INCOMPLETE'\n",
    'proof-schema-stages'
)

old_open1 = r'''    $pids1 = @($windows1.ProcessId | Select-Object -Unique)
    Invoke-AttachedEvidence -ProcessIds $pids1 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-open1"
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
'''
new_open1 = r'''    $pids1 = @($windows1.ProcessId | Select-Object -Unique)
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
'''
proof = replace_once(proof, old_open1, new_open1, 'open1-move-resize')

old_open2 = r'''    $pids2 = @($windows2.ProcessId | Select-Object -Unique)
    if (@($pids2 | Where-Object { $pids1 -contains $_ }).Count -gt 0) {
        throw "O reopen reutilizou PID que deveria ter sido encerrado. open1=$($pids1 -join ',') open2=$($pids2 -join ',')"
    }
    Invoke-AttachedEvidence -ProcessIds $pids2 -HostPid $cloudOsHostProcess.Id -Prefix "$ProofName-open2"
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
'''
new_open2 = r'''    $pids2 = @($windows2.ProcessId | Select-Object -Unique)
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
'''
proof = replace_once(proof, old_open2, new_open2, 'open2-dual')

proof = replace_once(
    proof,
    "    $proof.Close2 = [ordered]@{\n        ProcessIds = $pids2\n        MachineEvidence = \"$ProofName-close2.json\"\n        MachineLog = \"$ProofName-close2.log\"\n    }\n\n    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')\n",
    r'''    $proof.Close2 = [ordered]@{
        ProcessIds = $pids2
        MachineEvidence = "$ProofName-close2.json"
        MachineLog = "$ProofName-close2.log"
    }

    for ($cycle = 1; $cycle -le $ReopenStressCycles; $cycle++) {
        $stressBaseline = New-BaselineKeyMap
        Wait-Enter "STRESS $cycle/$ReopenStressCycles: reabra o mesmo aplicativo pelo CloudOS e, quando estiver renderizando normalmente dentro do CloudOS, pressione Enter"
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
        Wait-Enter "STRESS $cycle/$ReopenStressCycles: feche o aplicativo pelo CloudOS e pressione Enter quando desaparecer"
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
''',
    'stress-and-diagnostics'
)

proof = replace_once(
    proof,
    "    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')\n    $proof.Verdict = 'FAIL'\n",
    "    $proof.Diagnostics = Save-DiagnosticDelta\n    $proof.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')\n    $proof.Verdict = 'FAIL'\n",
    'failure-diagnostics'
)

proof = replace_once(
    proof,
    "        \"open2Pids=$($pids2 -join ',')\",\n        \"summary=$summaryPath\"\n",
    "        \"open2Pids=$($pids2 -join ',')\",\n        \"dualExpectation=$DualInstanceExpectation\",\n        \"stressCycles=$ReopenStressCycles\",\n        \"diagnostics=$($proof.Diagnostics)\",\n        \"summary=$summaryPath\"\n",
    'summary-log-extra'
)

# Contract coverage for the physical regression harness itself.
tests += r'''

test('physical proof reproduces the resize then reopen white-surface regression sequence', () => {
  assert.match(proofScript, /MoveResize1\s*=\s*\$null/);
  assert.match(proofScript, /mova e redimensione a janela interna/);
  assert.match(proofScript, /Read-ManualObservation -Stage 'move-resize1'/);
  assert.match(proofScript, /WhiteOrBlankSurfaceObserved/);
  assert.match(proofScript, /open2-after-resize-reopen/);
  assert.match(proofScript, /superfície branca\/vazia/);
});

test('physical proof makes dual-instance behavior explicit and fail closed', () => {
  assert.match(proofScript, /ValidateSet\('Skip', 'Supported', 'FailClosed'\)/);
  assert.match(proofScript, /DualInstanceExpectation/);
  assert.match(proofScript, /A segunda instância esperada não criou um novo HWND contido/);
  assert.match(proofScript, /O modo FailClosed criou\/adotou um novo HWND/);
  assert.match(proofScript, /FirstInstanceProcessIds/);
});

test('physical proof can verify unique per-launch Chromium profile tokens', () => {
  assert.match(proofScript, /RequireDistinctChromiumProfiles/);
  assert.match(proofScript, /--user-data-dir=/);
  assert.match(proofScript, /\[a-f0-9\]\{32\}/i);
  assert.match(proofScript, /Assert-And-RegisterChromiumProfiles/);
  assert.match(proofScript, /O perfil Chromium foi reutilizado entre launches/);
});

test('physical proof captures sanitized Host diagnostics and bounded reopen stress', () => {
  assert.match(proofScript, /ReopenStressCycles/);
  assert.match(proofScript, /ValidateRange\(0, 5\)/);
  assert.match(proofScript, /Save-DiagnosticDelta/);
  assert.match(proofScript, /browser-\$\(\[DateTime\]::UtcNow\.ToString\('yyyyMMdd'\)\)\.log/);
  assert.match(proofScript, /StressCycles \+=/);
});
'''

proof_path.write_text(proof, encoding='utf-8')
test_path.write_text(tests, encoding='utf-8')
