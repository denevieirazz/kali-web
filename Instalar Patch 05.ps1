$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$Src=Join-Path $Root 'frontend\src'
if(-not(Test-Path (Join-Path $Src 'apps\Settings\Settings.tsx'))){throw "Execute este instalador na raiz do CloudOS-Unified."}
$backup=Join-Path $Root ("backup-patch05-"+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path (Join-Path $backup 'Settings'),(Join-Path $backup 'ContextMenu')|Out-Null
Copy-Item (Join-Path $Src 'apps\Settings\*') (Join-Path $backup 'Settings') -Force
Copy-Item (Join-Path $Src 'components\ContextMenu\*') (Join-Path $backup 'ContextMenu') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\apps\Settings\Settings.tsx') (Join-Path $Src 'apps\Settings\Settings.tsx') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\apps\Settings\Settings.css') (Join-Path $Src 'apps\Settings\Settings.css') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\components\ContextMenu\ContextMenu.tsx') (Join-Path $Src 'components\ContextMenu\ContextMenu.tsx') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\components\ContextMenu\ContextMenu.css') (Join-Path $Src 'components\ContextMenu\ContextMenu.css') -Force
$browser=Join-Path $Src 'apps\Browser\Browser.tsx'
if(Test-Path $browser){$b=Get-Content $browser -Raw;$b=$b.Replace("  'duckduckgo.com',`r`n",'').Replace("  'bing.com',`r`n",'').Replace("const DEFAULT_HOME_URL = 'https://html.duckduckgo.com/html/';","const DEFAULT_HOME_URL = 'https://www.wikipedia.org';");Set-Content $browser $b -Encoding UTF8}
Write-Host "Patch 05 instalado. Backup: $backup" -ForegroundColor Green
Write-Host 'Execute: npm.cmd run lint; npm.cmd run build; npm.cmd test'
