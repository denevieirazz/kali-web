param([string]$ResultPath)
. (Join-Path $PSScriptRoot 'common.ps1')
$config=Get-CloudOSProductConfig
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
$result=Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
$stage=[IO.Path]::GetFullPath([string]$result.staging)
foreach($relative in @('CloudOS.Bootstrap.exe','app\host\CloudOS.Host.exe','agent\backend\src\server.js','web\index.html','runtime\node.exe','runtime\cloudos-core','meta\product.json','meta\manifest.json','meta\components.json','meta\checksums.sha256','README-UNSIGNED.txt')){
    if(-not(Test-Path -LiteralPath (Join-Path $stage $relative))){throw "PACKAGE_REQUIRED_FILE_MISSING:$relative"}
}
Assert-CloudOSStagingClean $stage
$manifest=Get-Content -LiteralPath (Join-Path $stage 'meta\manifest.json') -Raw | ConvertFrom-Json
foreach($file in @($manifest.files)){
    $path=Join-Path $stage (([string]$file.path).Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $path)){throw "PACKAGE_MANIFEST_FILE_MISSING:$($file.path)"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne ([string]$file.sha256).ToLowerInvariant()){throw "PACKAGE_MANIFEST_HASH_MISMATCH:$($file.path)"}
}
$nodeVersion=(& (Join-Path $stage 'runtime\node.exe') --version 2>&1 | Out-String).Trim()
if($nodeVersion -ne "v$($config.nodeVersion)"){throw "PACKAGED_NODE_VERSION_MISMATCH:$nodeVersion"}
if(-not(Test-Path -LiteralPath $result.setup)){throw 'PACKAGE_SETUP_MISSING'}
if(-not(Test-Path -LiteralPath $result.fullPackage)){throw 'PACKAGE_FULL_NUPKG_MISSING'}
if(-not(Test-Path -LiteralPath $result.portableZip)){throw 'PACKAGE_PORTABLE_ZIP_MISSING'}
$signature=Get-AuthenticodeSignature -LiteralPath $result.setup
if($signature.Status -eq 'Valid'){throw 'UNEXPECTED_SIGNED_SETUP_IN_UNSIGNED_BATCH'}
Add-Type -AssemblyName System.IO.Compression
$zip=[IO.Compression.ZipFile]::OpenRead([string]$result.portableZip)
try{
    $entries=@($zip.Entries.FullName)
    foreach($required in @('Iniciar CloudOS.cmd','app/CloudOS.Bootstrap.exe','app/app/host/CloudOS.Host.exe','runtime/node.exe','data-portable/','logs/')){
        if($entries -notcontains $required){throw "PORTABLE_ENTRY_MISSING:$required"}
    }
    if($entries | Where-Object {$_ -match '(^|/)node_modules/|(^|/)test-results/|\.env($|\.)|\.log$'}){throw 'PORTABLE_FORBIDDEN_CONTENT'}
}finally{$zip.Dispose()}
Write-Host "PRODUCTIZATION_PACKAGE_LAYOUT_OK setup=$($result.setup) portable=$($result.portableZip)"
