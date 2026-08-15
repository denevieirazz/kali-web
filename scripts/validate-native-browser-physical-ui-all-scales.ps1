$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'require-powershell7-windows.ps1')

Write-Host 'Validacao fisica CloudOS Browser - roteiro 100/125/150%' -ForegroundColor Cyan
Write-Host 'A escala do Windows nao sera alterada automaticamente.' -ForegroundColor Yellow
Write-Host 'Depois de mudar manualmente em Configuracoes > Sistema > Tela, execute:'
Write-Host ''
Write-Host 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-native-browser-physical-ui.ps1 -ExpectedScale 100 -Theme dark'
Write-Host 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-native-browser-physical-ui.ps1 -ExpectedScale 125 -Theme dark'
Write-Host 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-native-browser-physical-ui.ps1 -ExpectedScale 150 -Theme dark'
Write-Host ''
Write-Host 'Cada execucao captura a sequencia de digitacao/navegacao, dark/light e janela normal/compacta.'
