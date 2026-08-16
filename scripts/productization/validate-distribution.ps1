Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'PHYSICAL_VALIDATION_WINDOWS_ONLY'}
if($PSVersionTable.PSVersion.Major -lt 7){throw 'POWERSHELL_7_REQUIRED'}
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-CloudOSRepoRoot
Push-Location $root
try{$branch=(& git branch --show-current|Out-String).Trim();$head=Get-CloudOSGitSha}finally{Pop-Location}
if($branch -ne 'productization/cloudos-distribution-batch-2'){throw "PHYSICAL_VALIDATION_BRANCH_MISMATCH:$branch"}
$executionId="$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
$resultDir=Join-Path $root "test-results\productization-batch-2\$head\$executionId";New-Item -ItemType Directory -Force -Path $resultDir|Out-Null
$steps=New-Object System.Collections.Generic.List[object]
function Record([int]$Number,[string]$Name,[string]$Status,[string]$Detail=''){ $steps.Add([pscustomobject]@{number=$Number;name=$Name;status=$Status;detail=$Detail;at=[DateTimeOffset]::Now.ToString('O')});$steps|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $resultDir 'steps.json') -Encoding utf8;Write-Host "[$Status] $Number. $Name $Detail" }
function Confirm-Step([int]$Number,[string]$Name,[string]$Instruction){Write-Host '';Write-Host "PASSO $Number — $Name" -ForegroundColor Cyan;Write-Host $Instruction;do{$answer=(Read-Host 'Digite PASS para confirmar ou FAIL para interromper').Trim().ToUpperInvariant()}while($answer -notin @('PASS','FAIL'));if($answer -eq 'FAIL'){Record $Number $Name 'FAIL' 'Reprovado no checkpoint físico';throw "PHYSICAL_CHECKPOINT_FAILED:${Number}:${Name}"};Record $Number $Name 'PASS' 'confirmado interativamente'}
function Get-RealDbHash{ $path=Join-Path $env:LOCALAPPDATA 'CloudOS\data\cloudos.json';if(-not(Test-Path -LiteralPath $path)){return $null};return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Snapshot-Wsl([string]$Prefix){$dir=Join-Path $resultDir $Prefix;New-Item -ItemType Directory -Force -Path $dir|Out-Null;foreach($item in @(@('version','--version'),@('status','--status'),@('list','--list','--verbose'))){$name=$item[0];$args=$item[1..($item.Count-1)];try{(& wsl.exe @args 2>&1|Out-String)|Set-Content -LiteralPath (Join-Path $dir "$name.txt") -Encoding utf8}catch{$_|Out-String|Set-Content -LiteralPath (Join-Path $dir "$name.txt") -Encoding utf8}}}
function Wsl-Identity([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return @()};$lines=Get-Content -LiteralPath $Path;return @($lines|ForEach-Object{($_ -replace '^\s*\*?\s*','').Trim()}|Where-Object{$_ -and $_ -notmatch '^(NAME|NOME)\s+'}|ForEach-Object{if($_ -match '^(?<name>.+?)\s+(Running|Stopped|Executando|Parado)\s+(?<version>\d+)\s*$'){"$($Matches.name.Trim())|$($Matches.version)"}else{$_}}|Sort-Object)}
$realDbBefore=Get-RealDbHash;Snapshot-Wsl 'wsl-before'
$paths=Get-CloudOSArtifactPaths;$packageResultPath=Join-Path $paths.Artifacts 'package-result.json'
try{
    $packageReady=$false;if(Test-Path -LiteralPath $packageResultPath){try{$p=Get-Content -LiteralPath $packageResultPath -Raw|ConvertFrom-Json;$packageReady=($p.head -eq $head -and (Test-Path -LiteralPath $p.setup))}catch{}}
    if(-not $packageReady){& (Join-Path $root 'Preparar CloudOS.cmd');if($LASTEXITCODE -ne 0){throw 'PHYSICAL_PREPARE_FAILED'};& (Join-Path $root 'Compilar CloudOS.cmd');if($LASTEXITCODE -ne 0){throw 'PHYSICAL_BUILD_FAILED'};& (Join-Path $root 'Empacotar CloudOS.cmd');if($LASTEXITCODE -ne 0){throw 'PHYSICAL_PACKAGE_FAILED'}}
    & (Join-Path $PSScriptRoot 'new-update-fixture.ps1');$fixture=Get-Content -LiteralPath (Join-Path $paths.Artifacts 'update-fixture-result.json') -Raw|ConvertFrom-Json;$package=Get-Content -LiteralPath $packageResultPath -Raw|ConvertFrom-Json
    $installRoot=Join-Path $resultDir 'installed-app';$validationData=Join-Path $resultDir 'validation-data';New-Item -ItemType Directory -Force -Path $validationData|Out-Null;Set-Content -LiteralPath (Join-Path $validationData 'preservation-sentinel.txt') -Value $executionId -Encoding utf8
    $install=Start-Process -FilePath ([string]$package.setup) -ArgumentList @('--silent','--installto',$installRoot,'--log',(Join-Path $resultDir 'install.log')) -PassThru -Wait;if($install.ExitCode -ne 0){throw "PHYSICAL_INSTALL_FAILED:$($install.ExitCode)"};Record 1 'instalar pacote experimental' 'PASS' "installRoot=$installRoot"
    $launcher=Join-Path $resultDir 'Launch Validation.cmd';@" 
@echo off
setlocal
set "CLOUDOS_LOCAL_ROOT=$validationData"
set "CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE=1"
"$installRoot\current\CloudOS.Bootstrap.exe" --prerequisites
"@.TrimStart()|Set-Content -LiteralPath $launcher -Encoding ascii
    $startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs';$shortcut=Join-Path $startMenu 'CloudOS Experimental Validation.lnk';$shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($shortcut);$link.TargetPath=$env:ComSpec;$link.Arguments="/c `"$launcher`"";$link.WorkingDirectory=$resultDir;$link.Save()
    Confirm-Step 2 'iniciar pelo Menu Iniciar do Windows' 'Abra o Menu Iniciar e execute "CloudOS Experimental Validation". O atalho usa somente dados temporários desta execução.'
    Confirm-Step 3 'abrir Central de Pré-requisitos' 'Confirme que a Central aparece, explica estados em linguagem simples e não instala/alterar componentes automaticamente.'
    Confirm-Step 4 'iniciar WebOnly' 'Na Central, inicie WebOnly, confirme que o navegador abre e depois encerre a janela WebOnly.'
    Confirm-Step 5 'iniciar Full' 'Abra novamente "CloudOS Experimental Validation", escolha Full e aguarde o desktop CloudOS.'
    Confirm-Step 6 'abrir Terminal' 'No CloudOS Full, abra Terminal e confirme que a janela responde.'
    Confirm-Step 7 'abrir navegador' 'Abra o Navegador CloudOS e confirme uma navegação visual básica.'
    Confirm-Step 8 'abrir Files' 'Abra Files e confirme a interface sem conceder/acessar pastas pessoais desnecessárias.'
    Confirm-Step 9 'fechar tudo' 'Feche Terminal, Navegador, Files e o CloudOS Full. Confirme que a interface encerrou.'
    $serverInfo=[Diagnostics.ProcessStartInfo]::new();$serverInfo.FileName=(Join-Path ([string]$package.staging) 'runtime\node.exe');$serverInfo.ArgumentList.Add((Join-Path $PSScriptRoot 'update-fixture-server.mjs'));$serverInfo.ArgumentList.Add([string]$fixture.directory);$serverInfo.ArgumentList.Add('0');$serverInfo.UseShellExecute=$false;$serverInfo.CreateNoWindow=$true;$serverInfo.RedirectStandardOutput=$true;$serverInfo.RedirectStandardError=$true
    $server=[Diagnostics.Process]::new();$server.StartInfo=$serverInfo;if(-not $server.Start()){throw 'PHYSICAL_UPDATE_FIXTURE_SERVER_FAILED'};$serverLine=$server.StandardOutput.ReadLine();$serverJson=$serverLine|ConvertFrom-Json;$updateUrl="http://127.0.0.1:$($serverJson.port)"
    try{
        $updateInfo=[Diagnostics.ProcessStartInfo]::new();$updateInfo.FileName=Join-Path $installRoot 'current\CloudOS.Bootstrap.exe';$updateInfo.UseShellExecute=$false;$updateInfo.Environment['CLOUDOS_LOCAL_ROOT']=$validationData;$updateInfo.Environment['CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE']='1';foreach($arg in @('--check-update','--update-source',$updateUrl,'--channel','development')){$updateInfo.ArgumentList.Add($arg)};$updateProcess=[Diagnostics.Process]::Start($updateInfo)
        Confirm-Step 10 'atualizar usando fixture local' "Na janela Atualizações, confirme versão $($fixture.nextVersion), baixe e aplique. O feed é loopback desta execução: $updateUrl"
        Confirm-Step 11 'reiniciar' 'Após aplicar, confirme que o CloudOS reiniciou. Feche-o depois da confirmação.'
        $deadline=[DateTime]::UtcNow.AddSeconds(30);do{Start-Sleep -Milliseconds 250;$installedVersion=try{(Get-Content -LiteralPath (Join-Path $installRoot 'current\meta\product.json') -Raw|ConvertFrom-Json).version}catch{$null}}while($installedVersion -ne $fixture.nextVersion -and [DateTime]::UtcNow -lt $deadline)
        if($installedVersion -ne $fixture.nextVersion){throw "PHYSICAL_UPDATED_VERSION_NOT_ACTIVE:$installedVersion"}
        & (Join-Path $PSScriptRoot 'test-packaged-node-runtime.ps1') -Staging (Join-Path $installRoot 'current');Record 12 'confirmar health' 'PASS' "version=$installedVersion"
    }finally{if($server -and -not $server.HasExited){$server.Kill($false);$server.WaitForExit()};$server?.Dispose()}
    $backupDir=Join-Path $resultDir 'backups';$backup=& (Join-Path $PSScriptRoot 'backup-cloudos.ps1') -DataRoot $validationData -OutputDirectory $backupDir -ProductVersion ([string]$fixture.nextVersion) -Head $head;Record 13 'executar backup' 'PASS' "backup=$backup"
    $restoreRoot=Join-Path $resultDir 'restored-data';& (Join-Path $PSScriptRoot 'restore-cloudos.ps1') -BackupPath $backup -DataRoot $restoreRoot -ConfirmRestore;Record 14 'restaurar em dados temporários' 'PASS' "restoreRoot=$restoreRoot"
    $un=Start-Process -FilePath (Join-Path $installRoot 'Update.exe') -ArgumentList @('uninstall','--silent') -Wait -PassThru;if($un.ExitCode -ne 0){throw 'PHYSICAL_UNINSTALL_PRESERVE_FAILED'};if(-not(Test-Path -LiteralPath (Join-Path $validationData 'preservation-sentinel.txt'))){throw 'PHYSICAL_UNINSTALL_DID_NOT_PRESERVE_DATA'};Record 15 'desinstalar preservando dados' 'PASS'
    $re=Start-Process -FilePath ([string]$package.setup) -ArgumentList @('--silent','--installto',$installRoot) -Wait -PassThru;if($re.ExitCode -ne 0){throw 'PHYSICAL_REINSTALL_FAILED'};Record 16 'reinstalar' 'PASS';if(-not(Test-Path -LiteralPath (Join-Path $validationData 'preservation-sentinel.txt'))){throw 'PHYSICAL_REINSTALL_DATA_MISSING'};Record 17 'confirmar dados preservados' 'PASS'
    $un2=Start-Process -FilePath (Join-Path $installRoot 'Update.exe') -ArgumentList @('uninstall','--silent') -Wait -PassThru;if($un2.ExitCode -ne 0){throw 'PHYSICAL_FINAL_UNINSTALL_FAILED'};& (Join-Path $PSScriptRoot 'remove-cloudos-data.ps1') -DataRoot $validationData -RemoveData -RemoveBackups -RemoveLogs -Confirmation 'REMOVER DADOS CLOUDOS';Record 18 'desinstalar removendo dados temporários' 'PASS'
    $escaped=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and ([IO.Path]::GetFullPath($_.ExecutablePath).StartsWith([IO.Path]::GetFullPath($installRoot),[StringComparison]::OrdinalIgnoreCase))});if($escaped){throw "PHYSICAL_ORPHANS_FOUND:$(@($escaped.ProcessId)-join ',')"};Record 19 'confirmar zero órfãos' 'PASS'
    Snapshot-Wsl 'wsl-after';$beforeIdentity=Wsl-Identity (Join-Path $resultDir 'wsl-before\list.txt');$afterIdentity=Wsl-Identity (Join-Path $resultDir 'wsl-after\list.txt');if(($beforeIdentity -join "`n") -ne ($afterIdentity -join "`n")){throw 'PHYSICAL_WSL_IDENTITY_CHANGED'};$realDbAfter=Get-RealDbHash;if($realDbBefore -ne $realDbAfter){throw 'PHYSICAL_REAL_DATABASE_CHANGED'};Record 20 'confirmar WSL não modificado' 'PASS' 'distro/version identity preserved; real DB hash preserved'
    [pscustomobject]@{schemaVersion=1;head=$head;executionId=$executionId;status='passed';resultDirectory=$resultDir;physicalInteractive=$true;visualConfirmation='user-or-Gemini-confirmed-via-checkpoints';realDatabaseChanged=$false;wslIdentityChanged=$false;steps=$steps}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $resultDir 'result.json') -Encoding utf8
    Write-Host "PHYSICAL_DISTRIBUTION_VALIDATION_OK head=$head result=$resultDir" -ForegroundColor Green
}finally{try{Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\CloudOS Experimental Validation.lnk') -Force -ErrorAction SilentlyContinue}catch{};Pop-Location;Write-Host "explorer `"$resultDir`""}
