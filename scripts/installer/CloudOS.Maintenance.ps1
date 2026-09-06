[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('install', 'repair', 'uninstall', 'update', 'rollback', 'check-dependencies', 'verify-install')]
    [string]$Action,

    [string]$PackageDir,
    [string]$InstallDir,
    [Alias('NewPackageSource')]
    [string]$UpdatePackageDir,
    [switch]$PerUser = $true,
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartShortcut = $true,
    [switch]$EnableStartup,
    [switch]$PurgeUserData,
    [switch]$Force,
    [int]$HealthCheckTimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Diretorios padrao
if (-not $InstallDir) {
    if ($PerUser) {
        $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\CloudOS'
    } else {
        $InstallDir = Join-Path $env:ProgramFiles 'CloudOS'
    }
}

$logDir = Join-Path $env:LOCALAPPDATA 'CloudOS\InstallerLogs'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "$Action-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"

function Log-Message([string]$msg, [string]$color = 'White') {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Test-CloudOSDependencies {
    Log-Message "Executando verificacao de dependencias do sistema..." "Cyan"

    $osVersion = [Environment]::OSVersion.Version
    $is64Bit = [Environment]::Is64BitOperatingSystem
    $isWin10OrGreater = ($osVersion.Major -gt 10) -or ($osVersion.Major -eq 10 -and $osVersion.Build -ge 19041)

    $vcInstalled = (Test-Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64') -or
                   (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64')

    $wv2Installed = (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') -or
                    (Test-Path 'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') -or
                    (Test-Path 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application')

    $wslExe = Join-Path $env:WINDIR 'System32\wsl.exe'
    $wslInstalled = Test-Path -LiteralPath $wslExe
    $wslDistros = @()
    if ($wslInstalled) {
        $lxssKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
        if (Test-Path $lxssKey) {
            Get-ChildItem -Path $lxssKey | ForEach-Object {
                $distroName = (Get-ItemProperty -Path $_.PSPath -Name DistributionName -ErrorAction SilentlyContinue).DistributionName
                if ($distroName) { $wslDistros += $distroName }
            }
        }
    }

    $canProceed = $is64Bit -and $isWin10OrGreater

    $report = [ordered]@{
        CanProceed          = $canProceed
        Is64Bit             = $is64Bit
        OSVersion           = $osVersion.ToString()
        WindowsSupported    = $isWin10OrGreater
        VcRuntimeInstalled  = $vcInstalled
        WebView2Installed   = $wv2Installed
        WslInstalled        = $wslInstalled
        WslDistros          = $wslDistros
        WslIsOptional       = $true
        Details             = if ($canProceed) { 'Sistema operacional compativel.' } else { 'Requer Windows 10/11 x64 (Build 19041 ou superior).' }
    }

    Log-Message "  Windows: $($report.OSVersion) (Compativel: $($report.WindowsSupported))" $(if ($report.WindowsSupported) { 'Green' } else { 'Red' })
    Log-Message "  Arquitetura x64: $($report.Is64Bit)" $(if ($report.Is64Bit) { 'Green' } else { 'Red' })
    Log-Message "  Visual C++ Runtime: $($report.VcRuntimeInstalled)" $(if ($report.VcRuntimeInstalled) { 'Green' } else { 'Yellow' })
    Log-Message "  WebView2 Runtime: $($report.WebView2Installed)" $(if ($report.WebView2Installed) { 'Green' } else { 'Yellow' })
    Log-Message "  WSL (Opcional): $($report.WslInstalled) (Distros: $($wslDistros -join ', '))" $(if ($report.WslInstalled) { 'Green' } else { 'DarkGray' })

    return $report
}

function Stop-CloudOSProcesses {
    param([int]$TimeoutSeconds = 5)
    Log-Message "Encerrando processos CloudOS de forma limpa (nunca tocando em explorer ou outros apps)..." "Yellow"
    $targetNames = @(
        'cloudos_flutter_shell',
        'CloudOS',
        'CloudOS.Supervisor',
        'CloudOS.SystemBroker',
        'CloudOS.BrokerProbe'
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $procs = Get-Process -Name $targetNames -ErrorAction SilentlyContinue
        if (-not $procs) { break }
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                Log-Message "  Processo encerrado: $($p.ProcessName) (PID $($p.Id))" "DarkGray"
            } catch { }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
}

function Verify-FileManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDir,
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifesto nao encontrado: $ManifestPath"
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $results = [System.Collections.Generic.List[object]]::new()
    $missingCount = 0
    $corruptCount = 0
    $validCount = 0

    foreach ($entry in $manifest.files) {
        $filePath = Join-Path $TargetDir $entry.path
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            $missingCount++
            $results.Add([pscustomobject]@{
                Path   = $entry.path
                Status = 'MISSING'
                ExpectedHash = $entry.sha256
                ActualHash = $null
            })
            continue
        }

        $item = Get-Item -LiteralPath $filePath
        if ($item.Length -ne [Int64]$entry.size) {
            $corruptCount++
            $results.Add([pscustomobject]@{
                Path   = $entry.path
                Status = 'SIZE_MISMATCH'
                ExpectedHash = $entry.sha256
                ActualHash = $null
            })
            continue
        }

        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$entry.sha256).ToLowerInvariant()) {
            $corruptCount++
            $results.Add([pscustomobject]@{
                Path   = $entry.path
                Status = 'HASH_MISMATCH'
                ExpectedHash = $entry.sha256
                ActualHash = $actualHash
            })
            continue
        }

        $validCount++
        $results.Add([pscustomobject]@{
            Path   = $entry.path
            Status = 'VALID'
            ExpectedHash = $entry.sha256
            ActualHash = $actualHash
        })
    }

    return [pscustomobject]@{
        IsValid      = ($missingCount -eq 0 -and $corruptCount -eq 0)
        TotalFiles   = $manifest.files.Count
        ValidCount   = $validCount
        MissingCount = $missingCount
        CorruptCount = $corruptCount
        Entries      = $results
        Manifest     = $manifest
    }
}

function Invoke-Install {
    param(
        [string]$PackageSource,
        [string]$TargetLocation,
        [bool]$StartShortcut,
        [bool]$DeskShortcut,
        [bool]$ConfigureStartup = $false
    )
    Log-Message "Iniciando Instalacao Limpa do CloudOS..." "Cyan"
    Log-Message "  Pacote de Origem: $PackageSource"
    Log-Message "  Pasta de Destino: $TargetLocation"

    $deps = Test-CloudOSDependencies
    if (-not $deps.CanProceed) {
        throw "Instalacao abortada: requisitos minimos de sistema nao atendidos ($($deps.Details))"
    }

    if (-not (Test-Path -LiteralPath $PackageSource)) {
        throw "Pacote de instalacao nao encontrado: $PackageSource"
    }

    $sourceManifest = Join-Path $PackageSource 'manifests\cloudos-package-manifest.json'
    if (-not (Test-Path -LiteralPath $sourceManifest)) {
        $sourceManifest = Join-Path $PackageSource 'cloudos-package-manifest.json'
    }
    if (-not (Test-Path -LiteralPath $sourceManifest)) {
        throw "Manifesto canônico cloudos-package-manifest.json ausente no pacote de origem."
    }

    Stop-CloudOSProcesses

    # Criar diretorios
    if (-not (Test-Path -LiteralPath $TargetLocation)) {
        New-Item -ItemType Directory -Path $TargetLocation -Force | Out-Null
    }

    # Copiar recursivamente
    Copy-Item -Path (Join-Path $PackageSource '*') -Destination $TargetLocation -Recurse -Force
    Log-Message "Arquivos copiados com sucesso." "Green"

    # Copiar o proprio script de manutencao para o diretorio do app
    $maintDir = Join-Path $TargetLocation 'maintenance'
    if (-not (Test-Path -LiteralPath $maintDir)) {
        New-Item -ItemType Directory -Path $maintDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $maintDir 'CloudOS.Maintenance.ps1') -Force

    # Validar integridade da instalacao
    $installedManifest = Join-Path $TargetLocation 'manifests\cloudos-package-manifest.json'
    if (-not (Test-Path -LiteralPath $installedManifest)) {
        $installedManifest = Join-Path $TargetLocation 'cloudos-package-manifest.json'
    }
    $verifyResult = Verify-FileManifest -TargetDir $TargetLocation -ManifestPath $installedManifest
    if (-not $verifyResult.IsValid) {
        throw "Falha de integridade pos-instalacao: $($verifyResult.MissingCount) arquivos ausentes, $($verifyResult.CorruptCount) corrompidos."
    }
    Log-Message "Integridade dos arquivos verificada (100% OK: $($verifyResult.ValidCount) de $($verifyResult.TotalFiles) arquivos)." "Green"

    # Criar atalhos
    $mainExe = Join-Path $TargetLocation 'CloudOS.exe'
    $wsh = New-Object -ComObject WScript.Shell

    $startScript = Join-Path $TargetLocation 'start-cloudos-v21-integrated.ps1'

    if ($StartShortcut) {
        $startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        $startLnk = Join-Path $startMenuDir 'CloudOS.lnk'
        $shortcut = $wsh.CreateShortcut($startLnk)
        $shortcut.TargetPath = 'powershell.exe'
        $shortcut.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
        $shortcut.WorkingDirectory = $TargetLocation
        $shortcut.IconLocation = "$mainExe,0"
        $shortcut.Description = 'CloudOS Desktop'
        $shortcut.Save()
        Log-Message "Atalho criado no Menu Iniciar: $startLnk" "Green"
    }

    if ($DeskShortcut) {
        $desktopDir = [Environment]::GetFolderPath('Desktop')
        $deskLnk = Join-Path $desktopDir 'CloudOS.lnk'
        $shortcut = $wsh.CreateShortcut($deskLnk)
        $shortcut.TargetPath = 'powershell.exe'
        $shortcut.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
        $shortcut.WorkingDirectory = $TargetLocation
        $shortcut.IconLocation = "$mainExe,0"
        $shortcut.Description = 'CloudOS Desktop'
        $shortcut.Save()
        Log-Message "Atalho criado na Area de Trabalho: $deskLnk" "Green"
    }

    # Registro de Inicializacao Automatica (HKCU\Run - Per-User Seguro)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($ConfigureStartup) {
        $startupCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Startup"
        Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $startupCmd
        Log-Message "Inicializacao automatica registrada em HKCU\Run: $startupCmd" "Green"
    }

    # Registro de Desinstalacao no Windows (Add/Remove Programs)
    $versionData = if (Test-Path -LiteralPath (Join-Path $TargetLocation 'version.json')) {
        Get-Content -LiteralPath (Join-Path $TargetLocation 'version.json') -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{ productVersion = '21.0.0'; build = 29 }
    }

    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CloudOS'
    if (-not (Test-Path $uninstallKey)) {
        New-Item -Path $uninstallKey -Force | Out-Null
    }
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'CloudOS'
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value ([string]$versionData.productVersion)
    Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'CloudOS'
    Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $TargetLocation
    Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value "$mainExe,0"
    $uninstScript = Join-Path $maintDir 'CloudOS.Maintenance.ps1'
    Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value "powershell.exe -ExecutionPolicy Bypass -File `"$uninstScript`" -Action uninstall"
    Set-ItemProperty -Path $uninstallKey -Name 'NoModify' -Value 1
    Set-ItemProperty -Path $uninstallKey -Name 'NoRepair' -Value 0

    Log-Message "CloudOS instalado com sucesso no sistema!" "Green"
}

function Invoke-Repair {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLocation,
        [string]$PackageSource
    )
    Log-Message "Iniciando Reparo do CloudOS em $TargetLocation..." "Cyan"

    $manifestPath = Join-Path $TargetLocation 'manifests\cloudos-package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $manifestPath = Join-Path $TargetLocation 'cloudos-package-manifest.json'
    }

    if (-not (Test-Path -LiteralPath $manifestPath) -and $PackageSource) {
        $sourceManifest = Join-Path $PackageSource 'manifests\cloudos-package-manifest.json'
        if (Test-Path -LiteralPath $sourceManifest) {
            $manifestPath = $sourceManifest
        }
    }

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Manifesto de integridade nao encontrado para realizar o reparo."
    }

    $verifyResult = Verify-FileManifest -TargetDir $TargetLocation -ManifestPath $manifestPath
    Log-Message "Diagnostico de integridade: $($verifyResult.ValidCount) validos, $($verifyResult.MissingCount) ausentes, $($verifyResult.CorruptCount) adulterados/corrompidos."

    # Reparar entrada de startup se ela ja existir (preservando a escolha do usuario sem forcar ativacao)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $existingStartup = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    $registryRepaired = $false
    if ($existingStartup) {
        $startScript = Join-Path $TargetLocation 'start-cloudos-v21-integrated.ps1'
        $expectedCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Startup"
        if ($existingStartup -ne $expectedCmd) {
            Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $expectedCmd
            Log-Message "Entrada de startup em HKCU\Run reparada para apontar para o script valido." "Green"
            $registryRepaired = $true
        }
    }

    # Reparar entrada de shell se ela ja existir
    $policyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $configuredPolicyShell = (Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'Shell' -ErrorAction SilentlyContinue
    if ($configuredPolicyShell) {
        $expectedShell = "`"" + (Join-Path $TargetLocation 'CloudOS.ShellBootstrap.exe') + "`""
        if ($configuredPolicyShell -ne $expectedShell) {
            Set-ItemProperty -Path $policyPath -Name 'Shell' -Value $expectedShell
            Log-Message "Entrada de Shell em HKCU\Policies\System reparada para apontar para o bootstrap valido." "Green"
            $registryRepaired = $true
        }
    }

    if ($verifyResult.IsValid) {
        Log-Message "Nenhum arquivo corrompido ou ausente detectado. O produto esta 100% integro." "Green"
        return [pscustomobject]@{ Repaired = $registryRepaired; RepairedFiles = @(); Message = if ($registryRepaired) { "Registro de startup reparado com sucesso." } else { "Produto ja esta 100% integro." } }
    }

    if (-not $PackageSource -or -not (Test-Path -LiteralPath $PackageSource)) {
        throw "Origem do pacote ($PackageSource) e necessaria para restaurar os arquivos danificados."
    }

    Stop-CloudOSProcesses

    $repairedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $verifyResult.Entries) {
        if ($entry.Status -ne 'VALID') {
            $srcFile = Join-Path $PackageSource $entry.Path
            $dstFile = Join-Path $TargetLocation $entry.Path
            $parentDir = Split-Path -Parent $dstFile
            if (-not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force
            Log-Message "  Arquivo restaurado: $($entry.Path)" "Green"
            $repairedFiles.Add($entry.Path)
        }
    }

    # Re-verificar apos reparo
    $postCheck = Verify-FileManifest -TargetDir $TargetLocation -ManifestPath $manifestPath
    if (-not $postCheck.IsValid) {
        throw "Falha durante o reparo: ainda restam arquivos invalidos apos restauracao."
    }

    Log-Message "Reparo concluido com exito: $($repairedFiles.Count) arquivo(s) restaurado(s)." "Green"
    return [pscustomobject]@{
        Repaired      = $true
        RepairedFiles = $repairedFiles
        TotalValid    = $postCheck.ValidCount
    }
}

function Invoke-Uninstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLocation,
        [bool]$PurgeData
    )
    Log-Message "Iniciando Desinstalacao do CloudOS de $TargetLocation..." "Yellow"

    Stop-CloudOSProcesses

    # 0. RESTAURAR EXPLORER SHELL OBRIGATORIAMENTE (ETAPA 11)
    # Remove qualquer CustomShell policy ou Winlogon Shell per-user antes de remover arquivos
    $policyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    if (Test-Path -LiteralPath $policyPath) {
        Remove-ItemProperty -Path $policyPath -Name 'Shell' -Force -ErrorAction SilentlyContinue
        Log-Message "CustomShell policy removida de HKCU\Policies\System." "DarkGray"
    }
    $winlogonUser = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (Test-Path -LiteralPath $winlogonUser) {
        Remove-ItemProperty -Path $winlogonUser -Name 'Shell' -Force -ErrorAction SilentlyContinue
        Log-Message "Shell personalizado removido de HKCU\Winlogon." "DarkGray"
    }
    Log-Message "Shell oficial do Windows (explorer.exe) estritamente preservado." "Green"

    # 1. Remover atalhos
    $startLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\CloudOS.lnk'
    if (Test-Path -LiteralPath $startLnk) {
        Remove-Item -LiteralPath $startLnk -Force -ErrorAction SilentlyContinue
        Log-Message "Atalho do Menu Iniciar removido." "DarkGray"
    }

    $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CloudOS.lnk'
    if (Test-Path -LiteralPath $desktopLnk) {
        Remove-Item -LiteralPath $desktopLnk -Force -ErrorAction SilentlyContinue
        Log-Message "Atalho da Area de Trabalho removido." "DarkGray"
    }

    # 1.1 Remover inicializacao automatica
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $hasStartup = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if ($hasStartup) {
        Remove-ItemProperty -Path $runKey -Name 'CloudOS' -Force -ErrorAction SilentlyContinue
        Log-Message "Entrada de inicializacao automatica removida de HKCU\Run." "DarkGray"
    }
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $startupLnk = Join-Path $startupFolder 'CloudOS.lnk'
    if (Test-Path -LiteralPath $startupLnk) {
        Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue
        Log-Message "Atalho de inicializacao automatica removido da pasta Startup." "DarkGray"
    }

    # 2. Remover chave de Uninstall
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CloudOS'
    if (Test-Path $uninstallKey) {
        Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Registro de desinstalacao do Windows removido." "DarkGray"
    }

    # 3. Remover arquivos do programa
    if (Test-Path -LiteralPath $TargetLocation) {
        # Evitar deletar se estiver executando de dentro da pasta
        Get-ChildItem -Path $TargetLocation -Exclude @('maintenance', 'CloudOS.Maintenance.ps1') | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $TargetLocation 'maintenance') -Recurse -Force -ErrorAction SilentlyContinue
        # Tentar remover raiz
        Remove-Item -LiteralPath $TargetLocation -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Arquivos do produto removidos de $TargetLocation." "Green"
    }

    # 4. Dados do usuario
    $userDataDir = Join-Path $env:LOCALAPPDATA 'CloudOS\Data'
    $userConfigDir = Join-Path $env:LOCALAPPDATA 'CloudOS\Config'
    if ($PurgeData) {
        Remove-Item -LiteralPath $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Configuracoes e dados de usuario removidos conforme solicitado." "Yellow"
    } else {
        Log-Message "Configuracoes e dados de usuario preservados em %LOCALAPPDATA%\CloudOS." "Cyan"
    }

    Log-Message "Desinstalacao do CloudOS finalizada com sucesso." "Green"
}

function Invoke-Update {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLocation,
        [Parameter(Mandatory = $true)]
        [string]$NewPackageSource,
        [int]$HealthTimeout
    )
    Log-Message "Iniciando Pipeline de Atualizacao Atomica do CloudOS..." "Cyan"
    Log-Message "  Instalacao Atual: $TargetLocation"
    Log-Message "  Novo Pacote: $NewPackageSource"

    if (-not (Test-Path -LiteralPath $NewPackageSource)) {
        throw "Pacote de atualizacao nao encontrado: $NewPackageSource"
    }

    # 1. Staging e Validacao Fail-Closed
    $updateManifest = Join-Path $NewPackageSource 'manifests\cloudos-package-manifest.json'
    if (-not (Test-Path -LiteralPath $updateManifest)) {
        $updateManifest = Join-Path $NewPackageSource 'cloudos-package-manifest.json'
    }
    if (-not (Test-Path -LiteralPath $updateManifest)) {
        throw "UPDATE_REJECTED: Manifesto canônico cloudos-package-manifest.json ausente no novo pacote."
    }

    # Validar integridade do pacote novo ANTES de encostar na instalacao existente
    $packageCheck = Verify-FileManifest -TargetDir $NewPackageSource -ManifestPath $updateManifest
    if (-not $packageCheck.IsValid) {
        throw "UPDATE_REJECTED: Pacote de atualizacao corrompido ou incompleto ($($packageCheck.MissingCount) ausentes, $($packageCheck.CorruptCount) corrompidos)."
    }

    # Validar versao e protocolo
    $currentVersionFile = Join-Path $TargetLocation 'version.json'
    $currentVersion = if (Test-Path -LiteralPath $currentVersionFile) {
        Get-Content -LiteralPath $currentVersionFile -Raw | ConvertFrom-Json
    } else { $null }

    $newVersion = $packageCheck.Manifest
    if ($currentVersion -and [int]$newVersion.protocolVersion -ne [int]$currentVersion.protocolVersion) {
        throw "UPDATE_REJECTED: Incompatibilidade de protocolo: atual=$($currentVersion.protocolVersion), novo=$($newVersion.protocolVersion)."
    }

    Log-Message "Validacao do pacote de atualizacao APROVADA: Versao $($newVersion.version) (Build $($newVersion.build))." "Green"

    # 2. Criar pastas de Staging e Backup
    $stagingDir = Join-Path $TargetLocation '.staging'
    $previousDir = Join-Path $TargetLocation '.previous'

    if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
    if (Test-Path -LiteralPath $previousDir) { Remove-Item -LiteralPath $previousDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    # Copiar novo conteudo para staging
    Copy-Item -Path (Join-Path $NewPackageSource '*') -Destination $stagingDir -Recurse -Force

    # 3. Encerramento exclusivo dos processos CloudOS
    Stop-CloudOSProcesses

    # 4. Troca Atomica / Backup para Previous
    New-Item -ItemType Directory -Path $previousDir -Force | Out-Null
    $currentItems = Get-ChildItem -Path $TargetLocation -Exclude @('.staging', '.previous')
    foreach ($item in $currentItems) {
        Move-Item -LiteralPath $item.FullName -Destination $previousDir -Force
    }

    # Mover itens de staging para a raiz da instalacao
    $stagingItems = Get-ChildItem -Path $stagingDir
    foreach ($item in $stagingItems) {
        Move-Item -LiteralPath $item.FullName -Destination $TargetLocation -Force
    }
    Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

    Log-Message "Arquivos substituidos com sucesso. Versao anterior preservada em .previous/." "Green"

    # 5. Health Check da Nova Versao
    Log-Message "Executando Health-Check da nova versao..." "Cyan"
    $probeExe = Join-Path $TargetLocation 'CloudOS.BrokerProbe.exe'
    $brokerExe = Join-Path $TargetLocation 'CloudOS.SystemBroker.exe'

    $healthPassed = $false
    if (Test-Path -LiteralPath $brokerExe) {
        # Iniciar Broker temporariamente para testar handshake
        $brokerProc = Start-Process -FilePath $brokerExe -ArgumentList 'run' -PassThru -NoNewWindow
        Start-Sleep -Milliseconds 800
        if (Test-Path -LiteralPath $probeExe) {
            $deadline = [DateTime]::UtcNow.AddSeconds($HealthTimeout)
            do {
                try {
                    $probeOutput = & $probeExe ping
                    if ($probeOutput -match '"pong":true') {
                        $healthPassed = $true
                        break
                    }
                } catch { }
                Start-Sleep -Milliseconds 500
            } while ([DateTime]::UtcNow -lt $deadline)
        }
        if ($brokerProc -and -not $brokerProc.HasExited) {
            Stop-Process -Id $brokerProc.Id -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $healthPassed) {
        Log-Message "HEALTH_CHECK_FAILED: A nova versao falhou no teste de saude inicial. Iniciando Rollback automatico..." "Red"
        Invoke-Rollback -TargetLocation $TargetLocation
        throw "HEALTH_CHECK_FAILED: Atualizacao revertida automaticamente para a versao anterior estavel."
    }

    # Preservar e atualizar caminho do HKCU\Run se estiver ativado
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $existingStartup = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty 'CloudOS' -ErrorAction SilentlyContinue
    if ($existingStartup) {
        $startScript = Join-Path $TargetLocation 'start-cloudos-v21-integrated.ps1'
        $expectedCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Startup"
        Set-ItemProperty -Path $runKey -Name 'CloudOS' -Value $expectedCmd
        Log-Message "Entrada de inicializacao preservada e atualizada em HKCU\Run." "Green"
    }

    Log-Message "Atualizacao concluida com sucesso e verificada! Versao $($newVersion.version) ativa." "Green"
    return [pscustomobject]@{
        Updated = $true
        Version = $newVersion.version
        Build   = $newVersion.build
    }
}

function Invoke-Rollback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLocation
    )
    Log-Message "Executando reversao (Rollback) para a versao anterior..." "Yellow"
    $previousDir = Join-Path $TargetLocation '.previous'
    if (-not (Test-Path -LiteralPath $previousDir)) {
        throw "ROLLBACK_FAILED: Diretorio de backup .previous nao encontrado em $TargetLocation."
    }

    Stop-CloudOSProcesses

    # Limpar arquivos defeituosos da raiz
    Get-ChildItem -Path $TargetLocation -Exclude @('.previous', '.staging') | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Restaurar arquivos de previous
    $previousItems = Get-ChildItem -Path $previousDir
    foreach ($item in $previousItems) {
        Move-Item -LiteralPath $item.FullName -Destination $TargetLocation -Force
    }
    Remove-Item -LiteralPath $previousDir -Recurse -Force -ErrorAction SilentlyContinue

    Log-Message "Rollback concluido com sucesso. Versao anterior restaurada e operacional." "Green"
    return [pscustomobject]@{
        RolledBack = $true
        Status     = "RESTORED_PREVIOUS"
    }
}

# --- Dispatcher de Acoes ---
switch ($Action) {
    'check-dependencies' {
        Test-CloudOSDependencies
    }
    'install' {
        if (-not $PackageDir) { throw "Parametro -PackageDir e obrigatorio para install." }
        Invoke-Install -PackageSource $PackageDir -TargetLocation $InstallDir -StartShortcut $CreateStartShortcut -DeskShortcut $CreateDesktopShortcut -ConfigureStartup $EnableStartup
    }
    'repair' {
        Invoke-Repair -TargetLocation $InstallDir -PackageSource $PackageDir
    }
    'uninstall' {
        Invoke-Uninstall -TargetLocation $InstallDir -PurgeData $PurgeUserData
    }
    'update' {
        if (-not $UpdatePackageDir) {
            if ($PackageDir) { $UpdatePackageDir = $PackageDir }
            else { throw "Parametro -UpdatePackageDir e obrigatorio para update." }
        }
        Invoke-Update -TargetLocation $InstallDir -NewPackageSource $UpdatePackageDir -HealthTimeout $HealthCheckTimeoutSeconds
    }
    'rollback' {
        Invoke-Rollback -TargetLocation $InstallDir
    }
    'verify-install' {
        $manifestPath = Join-Path $InstallDir 'manifests\cloudos-package-manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            $manifestPath = Join-Path $InstallDir 'cloudos-package-manifest.json'
        }
        Verify-FileManifest -TargetDir $InstallDir -ManifestPath $manifestPath
    }
}
