$gitDir = "C:\Users\dougl\AppData\Local\Programs\MinGit"
if (-not (Test-Path $gitDir)) {
    New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
}

$zipPath = Join-Path $env:TEMP "mingit.zip"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Baixando MinGit..."
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/MinGit-2.45.2-64-bit.zip" -OutFile $zipPath

Write-Host "Extraindo MinGit..."
Expand-Archive -Path $zipPath -DestinationPath $gitDir -Force
Remove-Item $zipPath -Force

$gitExe = Join-Path $gitDir "cmd\git.exe"
Write-Host "MinGit pronto em $gitExe"
& $gitExe --version
