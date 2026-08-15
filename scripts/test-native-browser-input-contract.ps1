$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$probePath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\Program.cs'
$diagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\PhysicalInputDiagnostics.cs'
$reportingPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\ProbeReporting.cs'
$probeProject = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\CloudOS.Browser.PhysicalProbe.csproj'
$xaml = Get-Content -Raw -LiteralPath $xamlPath
$probe = Get-Content -Raw -LiteralPath $probePath
$diagnostics = Get-Content -Raw -LiteralPath $diagnosticsPath
$reporting = Get-Content -Raw -LiteralPath $reportingPath

function Assert-Contains([string]$pattern, [string]$message) {
    if ($xaml -notmatch $pattern) { throw "BROWSER_INPUT_CONTRACT_FAILED: $message" }
}

function Assert-ProbeContains([string]$pattern, [string]$message) {
    if ($probe -notmatch $pattern) { throw "BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: $message" }
}

function Assert-DiagnosticsContains([string]$pattern, [string]$message) {
    if ($diagnostics -notmatch $pattern) { throw "BROWSER_PHYSICAL_DIAGNOSTICS_CONTRACT_FAILED: $message" }
}

function Assert-ReportingContains([string]$pattern, [string]$message) {
    if ($reporting -notmatch $pattern) { throw "BROWSER_PHYSICAL_REPORT_CONTRACT_FAILED: $message" }
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

# Hosted CI intentionally does not execute user32!SendInput. It can compile the probe,
# execute ABI checks and exercise failure-report serialization, but only the physical Windows
# run may satisfy the interactive desktop/input evidence requirement.
Assert-ProbeContains 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-ProbeContains 'LongInput\s*=\s*"https://www\.youtube\.com/results\?search_query=' 'probe não testa URL longa.'
Assert-ProbeContains 'SendInput\(' 'probe físico deixou de usar SendInput.'
Assert-ProbeContains 'SetLastError\s*=\s*true' 'SendInput perdeu SetLastError=true.'
Assert-ProbeContains 'Marshal\.GetLastPInvokeError\(\)' 'falha de SendInput não registra o último erro P/Invoke sanitizado.'
Assert-ProbeContains 'InputSizeX64\s*=\s*40' 'contrato x64 de INPUT não exige 40 bytes.'
Assert-ProbeContains 'InputSizeX86\s*=\s*28' 'contrato x86 de INPUT não exige 28 bytes.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public MouseInput mouse' 'INPUT_UNION não contém MOUSEINPUT.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public KeyboardInput keyboard' 'INPUT_UNION não contém KEYBDINPUT.'
Assert-ProbeContains '\[FieldOffset\(0\)\]\s*public HardwareInput hardware' 'INPUT_UNION não contém HARDWAREINPUT.'
Assert-ProbeContains 'Marshal\.SizeOf<Input>\(\)' 'probe não mede sizeof(INPUT) gerenciado.'
Assert-ProbeContains '--validate-input-layout-only' 'probe não oferece teste de layout nativo seguro para CI.'
Assert-ProbeContains '--validate-diagnostics-contract-only' 'probe não oferece autoteste não-físico da serialização de falha.'
Assert-ProbeContains 'PhysicalInputDiagnostics\.Capture' 'probe não captura contexto físico antes do SendInput.'
Assert-ProbeContains 'PhysicalInputDiagnostics\.Evaluate' 'probe não bloqueia contexto físico incompatível antes do SendInput.'
Assert-ProbeContains '00-failure-context\.png' 'probe não tenta capturar contexto visual em falha.'
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

Assert-DiagnosticsContains 'Environment\.UserInteractive' 'diagnóstico não registra modo interativo.'
Assert-DiagnosticsContains 'SessionId' 'diagnóstico não registra sessão Windows.'
Assert-DiagnosticsContains 'GetProcessWindowStation' 'diagnóstico não inspeciona window station.'
Assert-DiagnosticsContains 'OpenInputDesktop' 'diagnóstico não abre o input desktop para comparação.'
Assert-DiagnosticsContains 'UOI_IO\s*=\s*6' 'diagnóstico não verifica qual desktop recebe input.'
Assert-DiagnosticsContains 'GetForegroundWindow' 'diagnóstico não verifica foreground real.'
Assert-DiagnosticsContains 'GetWindowThreadProcessId' 'diagnóstico não correlaciona foreground com PID/TID.'
Assert-DiagnosticsContains 'GetGUIThreadInfo' 'diagnóstico não verifica active/focus da GUI queue.'
Assert-DiagnosticsContains 'TokenIntegrityLevel\s*=\s*25' 'diagnóstico não consulta integrity level.'
Assert-DiagnosticsContains 'TokenElevation\s*=\s*20' 'diagnóstico não consulta elevação.'
Assert-DiagnosticsContains 'TokenUIAccess\s*=\s*26' 'diagnóstico não registra UIAccess.'
Assert-DiagnosticsContains 'ForegroundIntegrityHigher' 'diagnóstico não distingue foreground com integridade maior.'
Assert-DiagnosticsContains 'foreground-input-queue-differs' 'diagnóstico não distingue fila de input diferente.'
Assert-DiagnosticsContains 'native-keyboard-focus-mismatch' 'diagnóstico não distingue foco nativo incorreto.'

Assert-ReportingContains 'validation\.json' 'relatório não grava validation.json.'
Assert-ReportingContains 'PhysicalInputContext' 'relatório não preserva contexto físico seguro.'
Assert-ReportingContains 'Artifacts' 'relatório não lista artefatos produzidos.'
Assert-ReportingContains 'ProbeErrorReport' 'relatório não preserva erro sanitizado.'

$combinedProbe = $probe + "`n" + $diagnostics
if ($combinedProbe -match 'address\.Text\s*=(?!=)') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: entrada da omnibox não pode ser substituída por atribuição direta de Text.'
}
if ($combinedProbe -match 'SendKeys|AutomationPeer') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: probe não pode substituir SendInput por SendKeys/AutomationPeer.'
}
if ($diagnostics -match 'AttachThreadInput') {
    throw 'BROWSER_PHYSICAL_DIAGNOSTICS_CONTRACT_FAILED: diagnóstico não pode mascarar a fila de input anexando threads.'
}

& dotnet run --project $probeProject -c Release -- --validate-input-layout-only
if ($LASTEXITCODE -ne 0) {
    throw "BROWSER_PHYSICAL_PROBE_LAYOUT_FAILED: exit=$LASTEXITCODE"
}

$diagnosticsOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("cloudos-browser-probe-diagnostics-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    & dotnet run --project $probeProject -c Release -- --output $diagnosticsOutput --validate-diagnostics-contract-only
    if ($LASTEXITCODE -ne 0) {
        throw "BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: exit=$LASTEXITCODE"
    }

    $diagnosticsReport = Join-Path $diagnosticsOutput 'validation.json'
    if (-not (Test-Path -LiteralPath $diagnosticsReport)) {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: validation.json ausente.'
    }

    $json = Get-Content -Raw -LiteralPath $diagnosticsReport | ConvertFrom-Json
    if ($json.passed -ne $false -or $json.physicalValidation -ne $false) {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: relatório CI não-físico declarou sucesso/validação física.'
    }
    if ($json.stage -ne 'diagnostics-contract-self-test' -or $json.error.code -ne 'SELF_TEST_FAILURE_REPORT') {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: etapa/código de falha não foram serializados.'
    }
}
finally {
    Remove-Item -LiteralPath $diagnosticsOutput -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS native Browser input/diagnostics/menu/surface + physical probe contract'
