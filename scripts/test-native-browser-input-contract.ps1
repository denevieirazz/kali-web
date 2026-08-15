$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$xaml = Get-Content -Raw -LiteralPath $xamlPath

function Assert-Contains([string]$pattern, [string]$message) {
    if ($xaml -notmatch $pattern) { throw "BROWSER_INPUT_CONTRACT_FAILED: $message" }
}

Assert-Contains 'x:Name="AddressBox"' 'AddressBox ausente.'
Assert-Contains 'Style="\{StaticResource NativeInput\}"' 'AddressBox não usa o estilo de input nativo.'
Assert-Contains 'x:Name="AddressPlaceholder"' 'placeholder explícito ausente.'
Assert-Contains 'Property="CaretBrush" Value="\{DynamicResource BrowserTextPrimaryBrush\}"' 'caret não está explicitamente tematizado.'
Assert-Contains 'Property="SelectionBrush" Value="\{DynamicResource BrowserSelectionBrush\}"' 'seleção não está explicitamente tematizada.'
Assert-Contains 'Property="VerticalContentAlignment" Value="Center"' 'alinhamento vertical central ausente.'
Assert-Contains 'x:Name="BrowserMenuPopup"' 'popup moderno ausente.'
Assert-Contains 'x:Name="DownloadsButton"' 'botão de downloads ausente.'
Assert-Contains 'x:Name="HubPanel"' 'superfície de Downloads/Extensões/Configurações ausente.'

$styleMatch = [regex]::Match($xaml, '(?s)<Style x:Key="NativeInput".*?</Style>')
if (-not $styleMatch.Success) { throw 'BROWSER_INPUT_CONTRACT_FAILED: estilo NativeInput não encontrado.' }
if ($styleMatch.Value -match 'Property="Template"') {
    throw 'BROWSER_INPUT_CONTRACT_FAILED: NativeInput não pode substituir o template nativo do TextBox.'
}
if ($xaml -match '<ContextMenu') {
    throw 'BROWSER_INPUT_CONTRACT_FAILED: BrowserWindow.xaml voltou a usar ContextMenu legado.'
}

Write-Host 'PASS native Browser input/menu/surface XAML contract'
