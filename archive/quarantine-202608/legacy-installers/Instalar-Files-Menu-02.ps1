$ErrorActionPreference='Stop';$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not(Test-Path (Join-Path $Root 'frontend\src\main.tsx'))){throw 'Execute na raiz do CloudOS-Unified.'}
$Stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$Backup=Join-Path $Root "backup-files-menu02-$Stamp";New-Item -ItemType Directory -Force $Backup|Out-Null
$dirs=@('frontend\src\apps\CloudOSFiles','frontend\src\components\ContextMenu')
foreach($rel in $dirs){$src=Join-Path $Root $rel;if(Test-Path $src){$dst=Join-Path $Backup $rel;New-Item -ItemType Directory -Force (Split-Path $dst)|Out-Null;Copy-Item $src $dst -Recurse -Force}}
foreach($rel in $dirs){$dst=Join-Path $Root $rel;New-Item -ItemType Directory -Force $dst|Out-Null;Copy-Item (Join-Path $Root "payload\$rel\*") $dst -Force}
Push-Location $Root
try{& npm.cmd run lint;if($LASTEXITCODE){throw 'Lint falhou'};& npm.cmd run build;if($LASTEXITCODE){throw 'Build falhou'};& npm.cmd test;if($LASTEXITCODE){throw 'Testes falharam'};Write-Host "Files + Menu 02 instalado. Backup: $Backup" -ForegroundColor Green}catch{Write-Host 'Falha. Restaurando backup...' -ForegroundColor Red;foreach($rel in $dirs){$dst=Join-Path $Root $rel;$src=Join-Path $Backup $rel;if(Test-Path $src){Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue;Copy-Item $src $dst -Recurse -Force}};throw}finally{Pop-Location}
