$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Main=Join-Path $Root 'frontend\src\main.tsx'
$Desktop=Join-Path $Root 'frontend\src\components\Desktop\Desktop.tsx'
$Index=Join-Path $Root 'frontend\index.html'
if(-not(Test-Path $Main)){throw 'Extraia e execute na raiz do CloudOS-Unified.'}
$Stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $Backup=Join-Path $Root "backup-core-ui-$Stamp"; New-Item -ItemType Directory -Force $Backup|Out-Null
foreach($rel in @('frontend\src\main.tsx','frontend\src\components\Desktop\Desktop.tsx','frontend\public\cloudos-start-menu.js','frontend\index.html')){$s=Join-Path $Root $rel;if(Test-Path $s){$d=Join-Path $Backup $rel;New-Item -ItemType Directory -Force (Split-Path $d)|Out-Null;Copy-Item $s $d -Force}}
$Native=Join-Path $Root 'frontend\src\native';New-Item -ItemType Directory -Force $Native|Out-Null
Copy-Item (Join-Path $Root 'payload\frontend\src\native\shellBridge.ts') (Join-Path $Native 'shellBridge.ts') -Force
Copy-Item (Join-Path $Root 'payload\frontend\src\native\coreUiFix.css') (Join-Path $Native 'coreUiFix.css') -Force
$Public=Join-Path $Root 'frontend\public';New-Item -ItemType Directory -Force $Public|Out-Null
Copy-Item (Join-Path $Root 'payload\frontend\public\cloudos-start-menu.js') (Join-Path $Public 'cloudos-start-menu.js') -Force
$m=Get-Content $Main -Raw
if($m-notmatch "native/shellBridge"){$m="import './native/shellBridge';`r`nimport './native/coreUiFix.css';`r`n"+$m;Set-Content $Main $m -Encoding UTF8}
if(Test-Path $Desktop){$d=Get-Content $Desktop -Raw;$d=$d-replace 'onClick:\s*\(\)\s*=>\s*window\.location\.reload\(\)','onClick: () => window.cloudOS?.refreshDesktop()';$d=$d-replace 'onClick:\s*\(\)\s*=>\s*location\.reload\(\)','onClick: () => window.cloudOS?.refreshDesktop()';Set-Content $Desktop $d -Encoding UTF8}
$i=Get-Content $Index -Raw
$i=[regex]::Replace($i,'(?im)^.*cloudos-patch-05-1\.(js|css).*(\r?\n)?','')
if($i-notmatch 'cloudos-start-menu.js'){$i=$i-replace '</body>','  <script src="/cloudos-start-menu.js" defer></script>`r`n</body>'}
Set-Content $Index $i -Encoding UTF8
Push-Location $Root
try{& npm.cmd run lint;if($LASTEXITCODE){throw 'Lint falhou'};& npm.cmd run build;if($LASTEXITCODE){throw 'Build falhou'};& npm.cmd test;if($LASTEXITCODE){throw 'Testes falharam'};Write-Host "Correcao instalada. Backup: $Backup" -ForegroundColor Green}finally{Pop-Location}
