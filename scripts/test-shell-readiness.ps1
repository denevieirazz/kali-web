[CmdletBinding()]
param(
  [switch]$Json,
  [switch]$FailOnBlocked,
  [ValidatePattern('^[A-Fa-f0-9]{40,128}$')]
  [string]$ExpectedSignerThumbprint
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
  param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Group,
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][ValidateSet('pass', 'attention', 'fail', 'unknown', 'manual')][string]$Status,
    [Parameter(Mandatory)][string]$Detail,
    [ValidateSet('hard', 'soft', 'none')][string]$Gate = 'hard'
  )

  $Checks.Add([pscustomobject]@{
    id = $Id
    group = $Group
    label = $Label
    status = $Status
    gate = $Gate
    detail = $Detail
  })
}

function Get-OptionalRegistryValue {
  param([string]$Path, [string]$Name)
  try {
    return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
  } catch {
    return $null
  }
}

function Get-RegistryValueProbe {
  param([string]$Path, [string]$Name)
  try {
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
      return [pscustomobject]@{ readable = $true; found = $false; value = $null }
    }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $property = $item.PSObject.Properties[$Name]
    return [pscustomobject]@{
      readable = $true
      found = $null -ne $property
      value = $(if ($null -ne $property) { $property.Value } else { $null })
    }
  } catch {
    return [pscustomobject]@{ readable = $false; found = $false; value = $null }
  }
}

function Invoke-ReadOnlyCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [ValidateRange(1000, 30000)][int]$TimeoutMilliseconds = 8000
  )
  $process = $null
  try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    # Todos os argumentos usados por este diagnóstico são constantes, sem espaço
    # ou metacaractere. Não aceite entrada arbitrária nesta função.
    $startInfo.Arguments = $Arguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
      return [pscustomobject]@{ exitCode = -1; output = ''; timedOut = $false }
    }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
      try { $process.Kill() } catch {}
      return [pscustomobject]@{ exitCode = -1; output = ''; timedOut = $true }
    }
    $output = (($stdout.GetAwaiter().GetResult(), $stderr.GetAwaiter().GetResult()) -join [Environment]::NewLine).Trim()
    return [pscustomobject]@{ exitCode = $process.ExitCode; output = $output; timedOut = $false }
  } catch {
    return [pscustomobject]@{ exitCode = -1; output = ''; timedOut = $false }
  } finally {
    if ($null -ne $process) { $process.Dispose() }
  }
}

function Test-IsProtectedInstallLocation {
  param([string]$CandidatePath, [string]$ProtectedRoot)
  try {
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $root = [IO.Path]::GetFullPath($ProtectedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }

    $unsafeSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
    $writeRights = [Security.AccessControl.FileSystemRights]::Write -bor
      [Security.AccessControl.FileSystemRights]::Modify -bor
      [Security.AccessControl.FileSystemRights]::FullControl -bor
      [Security.AccessControl.FileSystemRights]::CreateFiles -bor
      [Security.AccessControl.FileSystemRights]::CreateDirectories

    $cursor = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
    while ($cursor) {
      $cursorPath = [IO.Path]::GetFullPath($cursor.FullName).TrimEnd([IO.Path]::DirectorySeparatorChar)
      if ($cursorPath -ine $root -and -not $cursorPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
      }
      if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }

      $acl = Get-Acl -LiteralPath $cursorPath -ErrorAction Stop
      $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
      $trustedInstallerSid = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
      if ($ownerSid -notin @('S-1-5-18', 'S-1-5-32-544', $trustedInstallerSid)) { return $false }
      foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
        try {
          $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        } catch {
          return $false
        }
        if ($unsafeSids -contains $sid -and ($rule.FileSystemRights -band $writeRights) -ne 0) { return $false }
      }

      if ($cursorPath -ieq $root) { break }
      $cursor = $cursor.Parent
    }
    return $true
  } catch {
    return $false
  }
}

$windowsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$editionId = Get-OptionalRegistryValue -Path $windowsKey -Name 'EditionID'
$productName = Get-OptionalRegistryValue -Path $windowsKey -Name 'ProductName'
$displayVersion = Get-OptionalRegistryValue -Path $windowsKey -Name 'DisplayVersion'
$build = Get-OptionalRegistryValue -Path $windowsKey -Name 'CurrentBuildNumber'

if ($editionId) {
  Add-Check -Id 'windows.edition' -Group 'Windows' -Label 'Edição do Windows identificada' -Status 'pass' -Gate 'none' -Detail "$productName · $displayVersion · build $build"
  $supportedEditions = @(
    'Enterprise', 'EnterpriseN', 'EnterpriseS', 'EnterpriseSN',
    'Education', 'EducationN', 'IoTEnterprise', 'IoTEnterpriseS'
  )
  if ($supportedEditions -contains $editionId) {
    Add-Check -Id 'windows.shellLauncherSku' -Group 'Windows' -Label 'Edição compatível com Shell Launcher' -Status 'pass' -Detail "EditionID $editionId é compatível com o caminho de produção."
  } else {
    Add-Check -Id 'windows.shellLauncherSku' -Group 'Windows' -Label 'Edição compatível com Shell Launcher' -Status 'fail' -Detail "EditionID $editionId não oferece Shell Launcher; mantenha o modo aplicativo ou use uma edição Enterprise/Education compatível."
  }
} else {
  Add-Check -Id 'windows.edition' -Group 'Windows' -Label 'Edição do Windows identificada' -Status 'unknown' -Detail 'Não foi possível ler a edição do Windows.'
  Add-Check -Id 'windows.shellLauncherSku' -Group 'Windows' -Label 'Edição compatível com Shell Launcher' -Status 'unknown' -Detail 'A compatibilidade não pode ser inferida sem EditionID.'
}

$explorerPath = Join-Path $env:WINDIR 'explorer.exe'
if (Test-Path -LiteralPath $explorerPath) {
  try {
    $explorerSignature = Get-AuthenticodeSignature -LiteralPath $explorerPath
    $microsoftSigned = $explorerSignature.Status -eq 'Valid' -and
      $explorerSignature.SignerCertificate.Subject -match '(?i)(Microsoft Windows|Microsoft Corporation)'
    Add-Check -Id 'recovery.explorer' -Group 'Recuperação' -Label 'Explorer disponível como fallback' -Status ($(if ($microsoftSigned) { 'pass' } else { 'fail' })) -Detail ($(if ($microsoftSigned) { 'explorer.exe está presente e possui assinatura Microsoft válida.' } else { 'explorer.exe existe, mas sua assinatura Microsoft não foi confirmada.' }))
  } catch {
    Add-Check -Id 'recovery.explorer' -Group 'Recuperação' -Label 'Explorer disponível como fallback' -Status 'unknown' -Detail 'explorer.exe está presente, mas a assinatura não pôde ser validada.'
  }
} else {
  Add-Check -Id 'recovery.explorer' -Group 'Recuperação' -Label 'Explorer disponível como fallback' -Status 'fail' -Detail 'explorer.exe não foi encontrado; o modo shell deve permanecer bloqueado.'
}

$winlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$machineShellProbe = Get-RegistryValueProbe -Path $winlogonKey -Name 'Shell'
$machineShell = $machineShellProbe.value
if (-not $machineShellProbe.readable) {
  Add-Check -Id 'shell.current' -Group 'Segurança' -Label 'Shell atual do Windows preservado' -Status 'unknown' -Detail 'O Registro global do shell não pôde ser lido; a ausência de acesso nunca é tratada como aprovação.'
} elseif ([string]::IsNullOrWhiteSpace($machineShell)) {
  Add-Check -Id 'shell.current' -Group 'Segurança' -Label 'Shell atual do Windows preservado' -Status 'unknown' -Detail 'O valor global do shell não pôde ser lido.'
} elseif ($machineShell.Trim([char[]]@([char]34, [char]32)) -ieq 'explorer.exe') {
  Add-Check -Id 'shell.current' -Group 'Segurança' -Label 'Shell atual do Windows preservado' -Status 'pass' -Detail 'Explorer continua sendo o shell global; o CloudOS ainda não foi ativado como shell.'
} else {
  Add-Check -Id 'shell.current' -Group 'Segurança' -Label 'Shell atual do Windows preservado' -Status 'attention' -Detail 'O shell global já foi personalizado fora desta preparação. Revise-o antes de qualquer piloto.'
}

$policyShellProbe = Get-RegistryValueProbe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'Shell'
$userShellProbe = Get-RegistryValueProbe -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'Shell'
if (-not $policyShellProbe.readable -or -not $userShellProbe.readable) {
  Add-Check -Id 'shell.userOverride' -Group 'Segurança' -Label 'Nenhum override de shell por usuário' -Status 'unknown' -Detail 'Uma das localizações de shell por usuário não pôde ser lida; o gate permanece bloqueado.'
} elseif ($policyShellProbe.found -or $userShellProbe.found) {
  Add-Check -Id 'shell.userOverride' -Group 'Segurança' -Label 'Nenhum override de shell por usuário' -Status 'attention' -Detail 'Foi detectada uma configuração de shell por usuário já existente. O script apenas leu o estado e não o modificou.'
} else {
  Add-Check -Id 'shell.userOverride' -Group 'Segurança' -Label 'Nenhum override de shell por usuário' -Status 'pass' -Detail 'Nenhuma política ou substituição de shell foi encontrada para o usuário atual.'
}

if ($supportedEditions -contains $editionId) {
  try {
    $shellLauncherSettings = @(Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName 'WESL_UserSetting' -OperationTimeoutSec 5 -ErrorAction Stop)
    if ($shellLauncherSettings.Count -eq 0) {
      Add-Check -Id 'shell.shellLauncherState' -Group 'Segurança' -Label 'Shell Launcher ainda não configurado' -Status 'pass' -Detail 'Nenhuma associação Shell Launcher foi encontrada nesta máquina.'
    } else {
      Add-Check -Id 'shell.shellLauncherState' -Group 'Segurança' -Label 'Shell Launcher ainda não configurado' -Status 'attention' -Detail 'Já existem associações Shell Launcher. O diagnóstico não as alterou; revise cada SID fora desta preparação.'
    }
  } catch {
    Add-Check -Id 'shell.shellLauncherState' -Group 'Segurança' -Label 'Shell Launcher ainda não configurado' -Status 'unknown' -Detail 'A edição é compatível, mas o estado do provedor Shell Launcher não pôde ser consultado.'
  }
} else {
  Add-Check -Id 'shell.shellLauncherState' -Group 'Segurança' -Label 'Shell Launcher ainda não configurado' -Status 'pass' -Detail 'A edição atual não oferece Shell Launcher; o bloqueio de edição permanece ativo.'
}

$hostExe = Join-Path $ProjectRoot 'desktop\publish\CloudOS.Host.exe'
$bootstrapExe = Join-Path $ProjectRoot 'desktop\publish\CloudOS.Bootstrap.exe'
$programFilesRoot = [Environment]::GetFolderPath('ProgramFiles')
$publishedRoot = Split-Path -Parent $hostExe
$nodeExe = Join-Path $publishedRoot 'runtime\node.exe'
$backendEntry = Join-Path $publishedRoot 'agent\backend\src\server.js'
$frontendIndex = Join-Path $publishedRoot 'web\index.html'

foreach ($artifact in @(
  @{ id = 'package.host'; label = 'Host CloudOS publicado'; path = $hostExe },
  @{ id = 'package.bootstrap'; label = 'Supervisor de recuperação publicado'; path = $bootstrapExe },
  @{ id = 'package.node'; label = 'Runtime Node empacotado'; path = $nodeExe },
  @{ id = 'package.backend'; label = 'Agente backend empacotado'; path = $backendEntry },
  @{ id = 'package.frontend'; label = 'Interface de produção compilada'; path = $frontendIndex }
)) {
  $exists = Test-Path -LiteralPath $artifact.path
  Add-Check -Id $artifact.id -Group 'Pacote' -Label $artifact.label -Status ($(if ($exists) { 'pass' } else { 'fail' })) -Detail ($(if ($exists) { 'Artefato encontrado no pacote local.' } else { 'Artefato ausente; compile/publique antes de um piloto.' }))
}

if ((Test-Path -LiteralPath $hostExe) -and (Test-Path -LiteralPath $bootstrapExe)) {
  try {
    $signatures = @($hostExe, $bootstrapExe) | ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_ }
    $allValid = @($signatures | Where-Object Status -ne 'Valid').Count -eq 0
    $allPinned = $ExpectedSignerThumbprint -and @($signatures | Where-Object {
      -not $_.SignerCertificate -or -not $_.SignerCertificate.Thumbprint.Equals($ExpectedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 0
    if ($allValid -and $allPinned) {
      Add-Check -Id 'security.signature' -Group 'Segurança' -Label 'Binários assinados pelo publicador esperado' -Status 'pass' -Detail 'Host e bootstrap possuem assinatura Authenticode válida do certificado fixado.'
    } elseif ($allValid) {
      Add-Check -Id 'security.signature' -Group 'Segurança' -Label 'Binários assinados pelo publicador esperado' -Status 'fail' -Detail 'As assinaturas são válidas, mas o certificado do publicador CloudOS não foi fixado ou não corresponde.'
    } else {
      $states = ($signatures | ForEach-Object Status) -join ', '
      Add-Check -Id 'security.signature' -Group 'Segurança' -Label 'Binários assinados pelo publicador esperado' -Status 'fail' -Detail "Assinaturas Authenticode: $states. Assinaturas válidas são obrigatórias antes do modo shell."
    }
  } catch {
    Add-Check -Id 'security.signature' -Group 'Segurança' -Label 'Binários assinados pelo publicador esperado' -Status 'unknown' -Detail 'Não foi possível validar as assinaturas Authenticode.'
  }
} else {
  Add-Check -Id 'security.signature' -Group 'Segurança' -Label 'Binários assinados pelo publicador esperado' -Status 'fail' -Detail 'Host ou bootstrap publicado não existe para validação.'
}

# O catálogo fica fora da árvore que ele próprio cobre; assim a validação não
# ganha um arquivo extra depois que o catálogo é criado.
$packageCatalog = Join-Path (Split-Path -Parent $publishedRoot) 'CloudOS.Package.cat'
if (Test-Path -LiteralPath $packageCatalog) {
  try {
    $catalogSignature = Get-AuthenticodeSignature -LiteralPath $packageCatalog
    $catalogPinned = $ExpectedSignerThumbprint -and $catalogSignature.SignerCertificate -and
      $catalogSignature.SignerCertificate.Thumbprint.Equals($ExpectedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)
    $catalogResult = Test-FileCatalog -Path $publishedRoot -CatalogFilePath $packageCatalog -Detailed
    $catalogValid = $catalogResult.Status -eq 'Valid'
    Add-Check -Id 'security.packageCatalog' -Group 'Segurança' -Label 'Catálogo assinado cobre o pacote' -Status ($(if ($catalogValid -and $catalogSignature.Status -eq 'Valid' -and $catalogPinned) { 'pass' } else { 'fail' })) -Detail ($(if ($catalogValid -and $catalogSignature.Status -eq 'Valid' -and $catalogPinned) { 'O catálogo de hashes do pacote é válido e assinado pelo publicador esperado.' } else { 'O catálogo, sua assinatura ou o certificado fixado não foi validado.' }))
  } catch {
    Add-Check -Id 'security.packageCatalog' -Group 'Segurança' -Label 'Catálogo assinado cobre o pacote' -Status 'unknown' -Detail 'Não foi possível validar o catálogo de integridade do pacote.'
  }
} else {
  Add-Check -Id 'security.packageCatalog' -Group 'Segurança' -Label 'Catálogo assinado cobre o pacote' -Status 'fail' -Detail 'O pacote de desenvolvimento ainda não possui um catálogo assinado de hashes.'
}

$isProtectedInstall = (Test-Path -LiteralPath $hostExe) -and (Test-IsProtectedInstallLocation -CandidatePath $publishedRoot -ProtectedRoot $programFilesRoot)
Add-Check -Id 'package.protectedLocation' -Group 'Pacote' -Label 'Instalação protegida em Program Files' -Status ($(if ($isProtectedInstall) { 'pass' } else { 'fail' })) -Detail ($(if ($isProtectedInstall) { 'A localização está dentro de Program Files, sem reparse point ou permissão de escrita ampla detectada.' } else { 'O pacote atual é de desenvolvimento ou a localização não possui proteção suficiente. O instalador futuro deve usar %ProgramFiles%\CloudOS.' }))

$webViewVersion = $null
# O identificador do produto pode variar entre canais/instaladores; enumera somente
# as chaves oficiais do Edge Update e identifica o runtime pelo nome do produto.
foreach ($root in @('HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients', 'HKCU:\Software\Microsoft\EdgeUpdate\Clients')) {
  try {
    foreach ($child in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
      $name = Get-OptionalRegistryValue -Path $child.PSPath -Name 'name'
      if ($name -like '*WebView2*') {
        $webViewVersion = Get-OptionalRegistryValue -Path $child.PSPath -Name 'pv'
        if ($webViewVersion) { break }
      }
    }
  } catch {}
  if ($webViewVersion) { break }
}
Add-Check -Id 'runtime.webview2' -Group 'Runtime' -Label 'WebView2 Runtime disponível' -Status ($(if ($webViewVersion) { 'pass' } else { 'unknown' })) -Detail ($(if ($webViewVersion) { "Versão detectada: $webViewVersion" } else { 'O registro não informou a versão. O host fará a validação definitiva ao iniciar.' }))

$reagent = Join-Path $env:WINDIR 'System32\reagentc.exe'
if (Test-Path -LiteralPath $reagent) {
  $winRe = Invoke-ReadOnlyCommand -FilePath $reagent -Arguments @('/info')
  if ($winRe.exitCode -eq 0 -and $winRe.output -match '(?i)(Enabled|Habilitado|Ativado)') {
    Add-Check -Id 'recovery.winre' -Group 'Recuperação' -Label 'Windows RE habilitado' -Status 'pass' -Detail 'O ambiente de recuperação do Windows está habilitado.'
  } elseif ($winRe.exitCode -eq 0 -and $winRe.output -match '(?i)(Disabled|Desabilitado|Desativado)') {
    Add-Check -Id 'recovery.winre' -Group 'Recuperação' -Label 'Windows RE habilitado' -Status 'fail' -Detail 'O Windows RE foi identificado como desabilitado.'
  } elseif ($winRe.exitCode -eq 0) {
    Add-Check -Id 'recovery.winre' -Group 'Recuperação' -Label 'Windows RE habilitado' -Status 'unknown' -Detail 'O comando respondeu, mas o estado não foi reconhecido com segurança neste idioma.'
  } else {
    Add-Check -Id 'recovery.winre' -Group 'Recuperação' -Label 'Windows RE habilitado' -Status 'unknown' -Detail 'Não foi possível consultar o Windows RE neste contexto.'
  }
} else {
  Add-Check -Id 'recovery.winre' -Group 'Recuperação' -Label 'Windows RE habilitado' -Status 'unknown' -Detail 'REAgentC não foi encontrado.'
}

$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (Test-Path -LiteralPath $wsl) {
  $wslStatus = Invoke-ReadOnlyCommand -FilePath $wsl -Arguments @('--status')
  Add-Check -Id 'linux.wsl' -Group 'Windows + Linux' -Label 'WSL consultável' -Status ($(if ($wslStatus.exitCode -eq 0) { 'pass' } else { 'fail' })) -Detail ($(if ($wslStatus.exitCode -eq 0) { 'O comando de status do WSL respondeu.' } elseif ($wslStatus.timedOut) { 'A consulta do WSL excedeu oito segundos e foi encerrada.' } else { 'O WSL existe, mas o status não pôde ser consultado neste contexto.' }))

  $wslVersion = Invoke-ReadOnlyCommand -FilePath $wsl -Arguments @('--version')
  $wslVersionText = $wslVersion.output -replace [char]0, ''
  $wslgReady = $wslVersion.exitCode -eq 0 -and $wslVersionText -match '(?im)^.*WSLg.*:\s*\S+'
  Add-Check -Id 'linux.wslg' -Group 'Windows + Linux' -Label 'WSLg confirmado' -Status ($(if ($wslgReady) { 'pass' } else { 'fail' })) -Detail ($(if ($wslgReady) { 'O runtime informou uma versão do WSLg.' } elseif ($wslVersion.timedOut) { 'A consulta da versão do WSLg excedeu oito segundos.' } else { 'Não foi possível confirmar uma versão real do WSLg.' }))

  $wslDistributions = Invoke-ReadOnlyCommand -FilePath $wsl -Arguments @('--list', '--verbose')
  $wslDistributionText = $wslDistributions.output -replace [char]0, ''
  $hasWsl2Distribution = $wslDistributions.exitCode -eq 0 -and $wslDistributionText -match '(?m)^\s*\*?\s*\S.*\s+2\s*$'
  Add-Check -Id 'linux.wsl2Distribution' -Group 'Windows + Linux' -Label 'Distribuição WSL 2 utilizável' -Status ($(if ($hasWsl2Distribution) { 'pass' } else { 'fail' })) -Detail ($(if ($hasWsl2Distribution) { 'Ao menos uma distribuição registrada usa WSL 2.' } elseif ($wslDistributions.timedOut) { 'A enumeração das distribuições excedeu oito segundos.' } else { 'Nenhuma distribuição WSL 2 pôde ser confirmada.' }))
} else {
  Add-Check -Id 'linux.wsl' -Group 'Windows + Linux' -Label 'WSL consultável' -Status 'fail' -Detail 'wsl.exe não foi encontrado.'
  Add-Check -Id 'linux.wslg' -Group 'Windows + Linux' -Label 'WSLg confirmado' -Status 'fail' -Detail 'WSLg depende de uma instalação operacional do WSL.'
  Add-Check -Id 'linux.wsl2Distribution' -Group 'Windows + Linux' -Label 'Distribuição WSL 2 utilizável' -Status 'fail' -Detail 'Nenhuma distribuição WSL 2 pôde ser consultada.'
}

Add-Check -Id 'recovery.adminAccount' -Group 'Recuperação' -Label 'Conta administrativa de recuperação testada' -Status 'manual' -Detail 'Exige uma conta separada que continue usando Explorer e um teste real de entrada.'
Add-Check -Id 'recovery.bitlockerKey' -Group 'Recuperação' -Label 'Chave BitLocker guardada fora do PC' -Status 'manual' -Detail 'A presença da cópia externa não pode ser inferida com segurança pelo software.'
Add-Check -Id 'recovery.restorePoint' -Group 'Recuperação' -Label 'Ponto de restauração e mídia de recuperação' -Status 'manual' -Detail 'Devem ser criados e testados imediatamente antes do piloto em máquina/VM dedicada.'
Add-Check -Id 'quality.vmQualification' -Group 'Qualificação' -Label 'Matriz de falhas aprovada em VM' -Status 'manual' -Detail 'Crash, atualização, falta de rede, suspensão, UAC, WSL e rollback precisam passar em VM descartável.'

$blocking = @($Checks | Where-Object { $_.gate -eq 'hard' -and $_.status -ne 'pass' })
$report = [pscustomobject]@{
  contract = 'cloudos.shell-preflight/v1'
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::Now.ToString('o')
  mode = 'read-only-preflight'
  activationPerformed = $false
  verdict = $(if ($blocking.Count -eq 0) { 'candidate' } else { 'not-ready' })
  blockingCount = $blocking.Count
  checks = $Checks
  notice = 'Este diagnóstico não modifica Registro, boot, Explorer, recursos do Windows, contas ou WSL.'
}

if ($Json) {
  $report | ConvertTo-Json -Depth 6
  if ($FailOnBlocked -and $blocking.Count -gt 0) { exit 2 }
  exit 0
}

Write-Host 'CloudOS — diagnóstico somente leitura para futuro modo shell'
Write-Host 'Nenhuma configuração do Windows será alterada.'
Write-Host ''
foreach ($check in $Checks) {
  $marker = switch ($check.status) {
    'pass' { '[OK]' }
    'attention' { '[ATENÇÃO]' }
    'fail' { '[BLOQUEADO]' }
    'manual' { '[MANUAL]' }
    default { '[DESCONHECIDO]' }
  }
  Write-Host "$marker $($check.label) - $($check.detail)"
}
Write-Host ''
Write-Host "Veredito: $($report.verdict); bloqueios obrigatórios: $($report.blockingCount)."
Write-Host $report.notice
if ($FailOnBlocked -and $blocking.Count -gt 0) { exit 2 }
