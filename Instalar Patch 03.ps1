$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$Index=Join-Path $Root 'frontend\index.html'
$Public=Join-Path $Root 'frontend\public'
if(-not(Test-Path -LiteralPath $Index)){throw "frontend/index.html nao encontrado em $Root"}
New-Item -ItemType Directory -Force -Path $Public|Out-Null
Copy-Item (Join-Path $PSScriptRoot 'payload\cloudos-customizer.js') (Join-Path $Public 'cloudos-customizer.js') -Force
Copy-Item (Join-Path $PSScriptRoot 'payload\cloudos-neon.css') (Join-Path $Public 'cloudos-neon.css') -Force
$html=Get-Content -LiteralPath $Index -Raw
if($html -notmatch 'cloudos-neon.css'){$html=$html.Replace('</head>',"  <link rel=`"stylesheet`" href=`"/cloudos-neon.css`">`r`n</head>")}
if($html -notmatch 'cloudos-customizer.js'){$html=$html.Replace('</body>',"  <script src=`"/cloudos-customizer.js`"></script>`r`n</body>")}
Set-Content -LiteralPath $Index -Value $html -Encoding UTF8
Write-Host 'Patch 03 instalado corretamente.' -ForegroundColor Green
Write-Host 'Agora execute: npm.cmd run build'
