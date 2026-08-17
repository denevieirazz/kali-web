Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'artifact-audit-lib.ps1')

$allowed=@(
    'CloudOS.Bootstrap.exe',
    'agent/backend/src/server.js',
    'web/assets/index-abc123.js',
    'runtime/node.exe',
    'meta/SBOM/npm.cyclonedx.json'
)
$allowedViolations=@(Get-CloudOSArtifactPolicyViolations -Names $allowed -Label 'allowed')
if($allowedViolations.Count -ne 0){throw "ARTIFACT_POLICY_FALSE_POSITIVE:$($allowedViolations -join '|')"}

$cases=[ordered]@{
    nodeModules='app/node_modules/x/index.js'
    env='app/.env.production'
    repositoryTree='.github/workflows/release.yml'
    sourceTree='frontend/src/App.jsx'
    goSource='runtime/main.go'
    privateKeyFile='meta/private-key.pem'
    log='logs/cloudos.log'
    traversal='../outside.txt'
}
foreach($entry in $cases.GetEnumerator()){
    $violations=@(Get-CloudOSArtifactPolicyViolations -Names @([string]$entry.Value) -Label ([string]$entry.Key))
    if($violations.Count -eq 0){throw "ARTIFACT_POLICY_NEGATIVE_NOT_CAUGHT:$($entry.Key):$($entry.Value)"}
}

$secretCases=[ordered]@{
    privateKey='-----BEGIN PRIVATE KEY-----'
    githubClassic=('ghp_' + ('A'*36))
    githubFineGrained=('github_pat_' + ('B'*50))
    awsAccessKey=('AKIA' + ('C'*16))
    slackToken=('xoxb-' + ('D'*30))
}
foreach($entry in $secretCases.GetEnumerator()){
    $match=Find-CloudOSHighConfidenceSecret ([string]$entry.Value)
    if(-not $match){throw "ARTIFACT_SECRET_NEGATIVE_NOT_CAUGHT:$($entry.Key)"}
}
if(Find-CloudOSHighConfidenceSecret 'const tokenName = "github token configured elsewhere";'){throw 'ARTIFACT_SECRET_FALSE_POSITIVE'}

$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-artifact-policy-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $temp 'agent/backend/src') -Force|Out-Null
Set-Content -LiteralPath (Join-Path $temp 'agent/backend/src/server.js') -Value 'console.log("ok")' -Encoding utf8
try{
    $count=Assert-CloudOSArtifactDirectory -Root $temp -Label 'clean-fixture'
    if($count -ne 1){throw "ARTIFACT_POLICY_CLEAN_COUNT_INVALID:$count"}
    New-Item -ItemType Directory -Path (Join-Path $temp 'node_modules/pkg') -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $temp 'node_modules/pkg/index.js') -Value 'module.exports={}' -Encoding utf8
    $caught=$false
    try{Assert-CloudOSArtifactDirectory -Root $temp -Label 'dirty-fixture'|Out-Null}catch{$caught=$_.Exception.Message -like 'ARTIFACT_POLICY_VIOLATION:*'}
    if(-not $caught){throw 'ARTIFACT_POLICY_DIRECTORY_NEGATIVE_NOT_CAUGHT'}
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}

Write-Host 'PRODUCTIZATION_ARTIFACT_POLICY_OK negativeCases=true backendSrcAllowed=true'
