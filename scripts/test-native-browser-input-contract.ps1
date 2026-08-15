$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$probePath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\Program.cs'
$probeProject = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\CloudOS.Browser.PhysicalProbe.csproj'
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

# Hosted CI does not have a reliable interactive input station, so SendInput itself remains
# mandatory for the Windows physical probe. The non-interactive layout-only mode below still
# executes the marshaller and prevents regressions such as INPUT shrinking back to 32 bytes on x64.
Assert-ProbeContains 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-ProbeContains 'LongInput\s*=\s*"https://www\.youtube\.com/results\?search_query=' 'probe não testa URL longa.'
Assert-ProbeContains 'SendInput\(' 'probe físico deixou de usar SendInput.'
Assert-ProbeContains 'SetLastError\s*=\s*true' 'SendInput perdeu SetLastError=true.'
Assert-ProbeContains 'Marshal\.GetLastWin32Error\(\)' 'falha de SendInput não registra código Win32 sanitizado.'
Assert-ProbeContains 'InputSizeX64\s*=\s*40' 'contrato x64 de INPUT não exige 40 bytes.'
Assert-ProbeContains 'InputSizeX86\s*=\s*28' 'contrato x86 de INPUT não exige 28 bytes.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public MouseInput mouse' 'INPUT_UNION não contém MOUSEINPUT.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public KeyboardInput keyboard' 'INPUT_UNION não contém KEYBDINPUT.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public HardwareInput hardware' 'INPUT_UNION não contém HARDWAREINPUT.'
Assert-ProbeContains 'Marshal\.SizeOf<Input>\(\)' 'probe não mede sizeof(INPUT) gerenciado.'
Assert-ProbeContains '--validate-input-layout-only' 'probe não oferece teste de layout nativo seguro para CI.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''A''\)' 'probe não testa Ctrl+A.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''C''\)' 'probe não testa Ctrl+C.'
Assert-ProbeContains 'Chord\(VK_CONTROL, ''V''\)' 'probe não testa Ctrl+V.'
Assert-ProbeContains 'PressKey\(VK_HOME\)' 'probe não testa Home físico completo.'
Assert-ProbeContains 'PressKey\(VK_END\)' 'probe não testa End físico completo.'
Assert-ProbeContains 'PressKey\(VK_RETURN\)' 'probe não testa Enter/navegação física.'
Assert-ProbeContains 'AssertVerticalBounds' 'probe não valida clipping vertical.'
Assert-ProbeContains '--expected-scale' 'probe não exige escala física quando solicitada.'
Assert-ProbeContains '--screen' 'probe não oferece screenshot físico de tela.'
Assert-ProbeContains '01-youtube-typed\.png' 'sequência de evidência de digitação ausente.'
Assert-ProbeContains '11-light-compact\.png' 'sequência dark/light/compacta incompleta.'
Assert-ProbeContains '12-menu-open\.png' 'evidência oficial do menu ausente.'
Assert-ProbeContains '13-downloads-hub\.png' 'evidência oficial de Downloads ausente.'
Assert-ProbeContains '14-settings-hub\.png' 'evidência oficial de Configurações ausente.'

if ($probe -match 'address\.Text\s*=(?!=)') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: entrada da omnibox não pode ser substituída por atribuição direta de Text.'
}

& dotnet run --project $probeProject -c Release -- --validate-input-layout-only
if ($LASTEXITCODE -ne 0) {
    throw "BROWSER_PHYSICAL_PROBE_LAYOUT_FAILED: exit=$LASTEXITCODE"
}

Write-Host 'PASS native Browser input/menu/surface + physical probe contract'
