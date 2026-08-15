$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$probePath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\Program.cs'
$xaml = Get-Content -Raw -LiteralPath $xamlPath
$probe = Get-Content -Raw -LiteralPath $probePath

function Assert-Contains([string]$pattern, [string]$message) {
    if ($xaml -notmatch $pattern) { throw "BROWSER_INPUT_CONTRACT_FAILED: $message" }
}

function Assert-ProbeContains([string]$pattern, [string]$message) {
    if ($probe -notmatch $pattern) { throw "BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: $message" }
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

# O runner hospedado do GitHub não oferece uma estação de desktop interativa confiável
# para user32!SendInput. Este bloco garante que o probe físico não seja enfraquecido para
# apenas atribuir TextBox.Text e que continue cobrindo os casos exigidos no Windows real.
Assert-ProbeContains 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-ProbeContains 'LongInput\s*=\s*"https://www\.youtube\.com/results\?search_query=' 'probe não testa URL longa.'
Assert-ProbeContains 'SendInput\(' 'probe físico deixou de usar SendInput.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''A''\)' 'probe não testa Ctrl+A.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''C''\)' 'probe não testa Ctrl+C.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''V''\)' 'probe não testa Ctrl+V.'
Assert-ProbeContains 'Key\(VK_HOME\)' 'probe não testa Home.'
Assert-ProbeContains 'Key\(VK_END\)' 'probe não testa End.'
Assert-ProbeContains 'AssertVerticalBounds' 'probe não valida clipping vertical.'
Assert-ProbeContains '--expected-scale' 'probe não exige escala física quando solicitada.'
Assert-ProbeContains '--screen' 'probe não oferece screenshot físico de tela.'
Assert-ProbeContains '01-youtube-typed\.png' 'sequência de evidência de digitação ausente.'
Assert-ProbeContains '11-light-compact\.png' 'sequência dark/light/compacta incompleta.'

if ($probe -match 'address\.Text\s*=\s*ShortInput') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: teste curto não pode ser substituído por atribuição direta de Text.'
}

Write-Host 'PASS native Browser input/menu/surface + physical probe contract'
