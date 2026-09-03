[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$StageDirectory,
    [Parameter(Mandatory = $true)][string]$CertificateThumbprint,
    [Parameter(Mandatory = $true)][ValidatePattern('^https?://')][string]$TimestampServer,
    [string]$OutputZip
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
if ([string]::IsNullOrWhiteSpace($StageDirectory)) {
    $StageDirectory = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64'
}
$stage = (Resolve-Path -LiteralPath $StageDirectory).Path
if ([string]::IsNullOrWhiteSpace($OutputZip)) {
    $OutputZip = Join-Path (Split-Path -Parent $stage) 'CloudOS-Native-Release-x64-signed.zip'
}
$OutputZip = [IO.Path]::GetFullPath($OutputZip)

$thumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
if ($thumbprint -notmatch '^[0-9A-F]{40,64}$') {
    throw 'CertificateThumbprint must be a SHA-1/SHA-256 hexadecimal certificate thumbprint.'
}

function Get-CodeSigningCertificate {
    param([Parameter(Mandatory = $true)][string]$WantedThumbprint)

    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($storePath in @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')) {
        try {
            foreach ($certificate in @(Get-ChildItem -LiteralPath $storePath -ErrorAction Stop)) {
                if (([string]$certificate.Thumbprint).ToUpperInvariant() -eq $WantedThumbprint) {
                    $matches.Add($certificate)
                }
            }
        }
        catch {
            # Some constrained signing hosts expose only one certificate store.
        }
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one signing certificate with thumbprint $WantedThumbprint; found $($matches.Count)."
    }

    $certificate = $matches[0]
    if (-not $certificate.HasPrivateKey) {
        throw 'The selected Authenticode certificate has no accessible private key.'
    }
    $now = [DateTime]::Now
    if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now) {
        throw 'The selected Authenticode certificate is not currently valid.'
    }
    $hasCodeSigningEku = @($certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId.Value }) -contains '1.3.6.1.5.5.7.3.3'
    if (-not $hasCodeSigningEku) {
        throw 'The selected certificate does not include the Code Signing EKU.'
    }
    return $certificate
}

$privateMaterial = @(
    Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.pfx', '.p12', '.key', '.pem') }
)
if ($privateMaterial.Count -ne 0) {
    throw "Private-key material must never be shipped in the CloudOS package: $($privateMaterial.FullName -join ', ')"
}

$certificate = Get-CodeSigningCertificate -WantedThumbprint $thumbprint
$signable = @(
    Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.exe', '.dll', '.ps1', '.psm1') } |
        Sort-Object FullName
)
if ($signable.Count -eq 0) {
    throw 'No Authenticode-signable CloudOS files were found in the staged release.'
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($file in $signable) {
    $signature = Set-AuthenticodeSignature `
        -LiteralPath $file.FullName `
        -Certificate $certificate `
        -HashAlgorithm SHA256 `
        -TimestampServer $TimestampServer
    if ($signature.Status -ne 'Valid') {
        throw "Authenticode signing failed for $($file.Name): $($signature.Status) $($signature.StatusMessage)"
    }

    $verified = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($verified.Status -ne 'Valid' -or
        $null -eq $verified.SignerCertificate -or
        ([string]$verified.SignerCertificate.Thumbprint).ToUpperInvariant() -ne $thumbprint) {
        throw "Authenticode verification failed after signing: $($file.Name)"
    }

    $records.Add([pscustomobject]@{
        file = $file.FullName.Substring($stage.Length).TrimStart('\')
        status = [string]$verified.Status
        signer_subject = [string]$verified.SignerCertificate.Subject
        signer_thumbprint = [string]$verified.SignerCertificate.Thumbprint
        timestamp_subject = if ($null -ne $verified.TimeStamperCertificate) {
            [string]$verified.TimeStamperCertificate.Subject
        } else { $null }
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = [Int64](Get-Item -LiteralPath $file.FullName).Length
    })
}

# Signing changes PE bytes. Refresh the staged package manifest only after every
# signature has verified so downstream SHA256/integrity checks describe exactly
# the signed payload that will be installed.
$manifestPath = Join-Path $stage 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Signed release stage is missing cloudos-native-manifest.json.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$binaryNames = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
foreach ($name in $binaryNames) {
    $path = Join-Path $stage $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Signed release payload is missing: $name"
    }
    $manifestRecord = @($manifest.files | Where-Object { $_.name -eq $name })
    if ($manifestRecord.Count -ne 1) {
        throw "Manifest must contain exactly one record for signed payload $name."
    }
    $manifestRecord[0].size = [Int64](Get-Item -LiteralPath $path).Length
    $manifestRecord[0].sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | Add-Member -NotePropertyName package_authenticode_v22 -NotePropertyValue $true -Force
$manifest | Add-Member -NotePropertyName package_signer_thumbprint -NotePropertyValue $thumbprint -Force
$manifest | Add-Member -NotePropertyName package_signed_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$sumLines = New-Object System.Collections.Generic.List[string]
foreach ($name in $binaryNames) {
    $path = Join-Path $stage $name
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumLines.Add("$hash  $name")
}
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value $sumLines -Encoding ascii

$evidencePath = Join-Path $stage 'cloudos-authenticode-v22.json'
$evidence = [ordered]@{
    schema = 22
    component = 'CloudOS.Release.Authenticode'
    signed_utc = [DateTime]::UtcNow.ToString('o')
    signer_thumbprint = $thumbprint
    signer_subject = [string]$certificate.Subject
    timestamp_server = $TimestampServer
    all_valid = $true
    signed_file_count = $records.Count
    files = @($records)
    private_key_material_in_package = $false
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8

# Final fail-closed verification of every signable file after manifest/hash refresh.
foreach ($file in $signable) {
    $verified = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($verified.Status -ne 'Valid' -or
        $null -eq $verified.SignerCertificate -or
        ([string]$verified.SignerCertificate.Thumbprint).ToUpperInvariant() -ne $thumbprint) {
        throw "Final Authenticode verification failed: $($file.FullName)"
    }
}
foreach ($line in Get-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Invalid SHA256SUMS line: $line" }
    $expected = $matches[1]
    $name = $matches[2]
    $actual = (Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Final signed SHA256 mismatch: $name" }
}

if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputZip -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $OutputZip -PathType Leaf) -or
    (Get-Item -LiteralPath $OutputZip).Length -le 0) {
    throw 'Signed CloudOS release ZIP was not created.'
}
$zipHash = (Get-FileHash -LiteralPath $OutputZip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "[CloudOS V22] SIGNED_RELEASE=$OutputZip"
Write-Host "[CloudOS V22] SIGNED_RELEASE_SHA256=$zipHash"
Write-Host "[CloudOS V22] AUTHENTICODE_OK files=$($records.Count) signer=$thumbprint"
