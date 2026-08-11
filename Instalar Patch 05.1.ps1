$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$Index=Join-Path $Root 'frontend\index.html'
$Public=Join-Path $Root 'frontend\public'
if(-not(Test-Path -LiteralPath $Index)){throw "Execute na raiz do CloudOS-Unified."}
New-Item -ItemType Directory -Force -Path $Public|Out-Null
Copy-Item (Join-Path $PSScriptRoot 'payload\cloudos-patch-05-1.js') (Join-Path $Public 'cloudos-patch-05-1.js') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\cloudos-patch-05-1.css') (Join-Path $Public 'cloudos-patch-05-1.css') -Force
$html=Get-Content -LiteralPath $Index -Raw
if($html -notmatch 'cloudos-patch-05-1.css'){$html=$html.Replace('</head>',"  <link rel=`"stylesheet`" href=`"/cloudos-patch-05-1.css`">`r`n</head>")}
if($html -notmatch 'cloudos-patch-05-1.js'){$html=$html.Replace('</body>',"  <script src=`"/cloudos-patch-05-1.js`"></script>`r`n</body>")}
Set-Content -LiteralPath $Index -Value $html -Encoding UTF8
Write-Host 'Patch 05.1 instalado.' -ForegroundColor Green
Write-Host 'Execute npm.cmd run build e reinicie o CloudOS.'
