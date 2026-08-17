Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-CloudOSArtifactPolicyViolations {
    param([Parameter(Mandatory)][string[]]$Names,[string]$Label='artifact')
    $violations=New-Object System.Collections.Generic.List[string]
    foreach($rawName in $Names){
        $name=([string]$rawName).Replace('\','/').TrimStart('/')
        if([string]::IsNullOrWhiteSpace($name)){continue}
        if($name -match '(^|/)\.\.(/|$)'){[void]$violations.Add("${Label}:path-traversal:$name");continue}
        if($name -match '(^|/)node_modules(/|$)'){[void]$violations.Add("${Label}:node_modules:$name")}
        if($name -match '(^|/)(\.git|\.github|test-results|tests|archive)(/|$)'){[void]$violations.Add("${Label}:repository-tree:$name")}
        if($name -match '(^|/)scripts/productization(/|$)|(^|/)frontend/src(/|$)|(^|/)core/wsl(/|$)|(^|/)desktop/CloudOS\.(Host|Bootstrap|Productization\.Tests)(/|$)'){[void]$violations.Add("${Label}:source-tree:$name")}
        if($name -match '(^|/)go\.(mod|sum)$|\.go$'){[void]$violations.Add("${Label}:go-source:$name")}
        $leaf=[IO.Path]::GetFileName($name)
        if($leaf -match '^\.env($|\.)|\.log$|\.(pfx|p12|key|pem)$|^(id_rsa|id_ed25519)$' -or $leaf -match '(?i)(secret|credential|private[_-]?key)'){
            [void]$violations.Add("${Label}:sensitive-file:$name")
        }
    }
    return @($violations)
}

function Find-CloudOSHighConfidenceSecret {
    param([AllowEmptyString()][string]$Text)
    if([string]::IsNullOrEmpty($Text)){return $null}
    $patterns=[ordered]@{
        privateKey='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
        githubClassic='\bgh[pousr]_[A-Za-z0-9]{30,}\b'
        githubFineGrained='\bgithub_pat_[A-Za-z0-9_]{40,}\b'
        awsAccessKey='\b(AKIA|ASIA)[A-Z0-9]{16}\b'
        slackToken='\bxox[baprs]-[A-Za-z0-9-]{20,}\b'
    }
    foreach($entry in $patterns.GetEnumerator()){
        if($Text -match $entry.Value){return [string]$entry.Key}
    }
    return $null
}

function Test-CloudOSTextCandidate {
    param([Parameter(Mandatory)][string]$Name,[long]$Length)
    if($Length -gt 2097152){return $false}
    return $Name -match '(?i)\.(txt|md|json|jsonl|js|mjs|cjs|css|html|xml|yml|yaml|config|ini|cmd|ps1|psm1|nuspec|props|targets|license)$'
}

function Assert-CloudOSArtifactDirectory {
    param([Parameter(Mandatory)][string]$Root,[string]$Label='directory')
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){throw "ARTIFACT_DIRECTORY_MISSING:${Label}:$Root"}
    $files=@(Get-ChildItem -LiteralPath $Root -File -Recurse)
    $names=@($files|ForEach-Object{Get-CloudOSRelativePath $Root $_.FullName})
    $violations=@(Get-CloudOSArtifactPolicyViolations -Names $names -Label $Label)
    if($violations.Count -ne 0){throw "ARTIFACT_POLICY_VIOLATION:$($violations -join '|')"}
    foreach($file in $files){
        $relative=Get-CloudOSRelativePath $Root $file.FullName
        if(-not(Test-CloudOSTextCandidate -Name $relative -Length $file.Length)){continue}
        try{$text=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop}catch{continue}
        $secret=Find-CloudOSHighConfidenceSecret $text
        if($secret){throw "ARTIFACT_SECRET_PATTERN:${Label}:${relative}:$secret"}
    }
    return $files.Count
}

function Assert-CloudOSZipArchive {
    param([Parameter(Mandatory)][string]$Path,[string]$Label='zip')
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "ARTIFACT_ARCHIVE_MISSING:${Label}:$Path"}
    Add-Type -AssemblyName System.IO.Compression
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try{
        $entries=@($zip.Entries|Where-Object{-not [string]::IsNullOrEmpty($_.Name)})
        $names=@($entries|ForEach-Object{$_.FullName})
        $violations=@(Get-CloudOSArtifactPolicyViolations -Names $names -Label $Label)
        if($violations.Count -ne 0){throw "ARTIFACT_POLICY_VIOLATION:$($violations -join '|')"}
        foreach($entry in $entries){
            if(-not(Test-CloudOSTextCandidate -Name $entry.FullName -Length $entry.Length)){continue}
            $reader=[IO.StreamReader]::new($entry.Open())
            try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $secret=Find-CloudOSHighConfidenceSecret $text
            if($secret){throw "ARTIFACT_SECRET_PATTERN:${Label}:$($entry.FullName):$secret"}
        }
        return $entries.Count
    }finally{$zip.Dispose()}
}

function Read-CloudOSChecksumManifest {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "CHECKSUM_MANIFEST_MISSING:$Path"}
    $map=[ordered]@{}
    foreach($line in Get-Content -LiteralPath $Path){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        if($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$'){throw "CHECKSUM_LINE_INVALID:$line"}
        $relative=$Matches[2].Replace('\','/')
        if($map.Contains($relative)){throw "CHECKSUM_DUPLICATE_PATH:$relative"}
        $map[$relative]=$Matches[1].ToLowerInvariant()
    }
    return $map
}

function Assert-CloudOSChecksumsExact {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ChecksumPath,[string[]]$Exclude=@())
    $excludeSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $Exclude){[void]$excludeSet.Add($item.Replace('\','/'))}
    $expected=[ordered]@{}
    foreach($file in Get-ChildItem -LiteralPath $Root -File -Recurse|Sort-Object FullName){
        $relative=Get-CloudOSRelativePath $Root $file.FullName
        if($excludeSet.Contains($relative)){continue}
        $expected[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $actual=Read-CloudOSChecksumManifest $ChecksumPath
    foreach($relative in $expected.Keys){
        if(-not $actual.Contains($relative)){throw "CHECKSUM_PATH_MISSING:$relative"}
        if($actual[$relative] -ne $expected[$relative]){throw "CHECKSUM_HASH_MISMATCH:$relative"}
    }
    foreach($relative in $actual.Keys){if(-not $expected.Contains($relative)){throw "CHECKSUM_UNEXPECTED_PATH:$relative"}}
    return $expected.Count
}
