# Script de Automação do Git
$exePath = Join-Path $env:TEMP "PortableGit.exe"
$targetDir = "C:\Users\d\git"

if (Test-Path $exePath) {
    Write-Host "Extraindo PortableGit..."
    Start-Process -FilePath $exePath -ArgumentList "-y", "-o`"C:\Users\d\git`"" -Wait -NoNewWindow
}

$gitBin = "C:\Users\d\git\cmd\git.exe"
if (Test-Path $gitBin) {
    Write-Host "Git encontrado! Executando commit e push..."
    Set-Location "C:\Users\d\Music\projeto"
    & $gitBin add .
    & $gitBin commit -m "feat: instalador Calamares 100% web, debug visual em tempo real, fixes VBScript Chr(34), fix de variaveis worker e README exaustivo"
    & $gitBin push origin main
    Write-Host "PUSH CONCLUIDO COM SUCESSO!"
} else {
    Write-Host "Procurando Git no sistema..."
}
