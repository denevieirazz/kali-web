$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$featuresPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.Features.cs'
$extensionsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserExtensionManager.cs'
$probePath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\Program.cs'
$omniboxDiagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\OmniboxVisualDiagnostics.cs'
$diagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\PhysicalInputDiagnostics.cs'
$reportingPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\ProbeReporting.cs'
$probeProject = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\CloudOS.Browser.PhysicalProbe.csproj'

$xaml = Get-Content -Raw -LiteralPath $xamlPath
$features = Get-Content -Raw -LiteralPath $featuresPath
$extensions = Get-Content -Raw -LiteralPath $extensionsPath
$probe = Get-Content -Raw -LiteralPath $probePath
$omniboxDiagnostics = Get-Content -Raw -LiteralPath $omniboxDiagnosticsPath
$diagnostics = Get-Content -Raw -LiteralPath $diagnosticsPath
$reporting = Get-Content -Raw -LiteralPath $reportingPath

function Assert-Contains([string]$content, [string]$pattern, [string]$message) {
    if ($content -notmatch $pattern) { throw "BROWSER_CONTRACT_FAILED: $message" }
}

Assert-Contains $xaml 'x:Name="AddressBox"' 'AddressBox ausente.'
Assert-Contains $xaml 'Style="\{StaticResource NativeInput\}"' 'AddressBox não usa NativeInput.'
Assert-Contains $xaml 'x:Name="AddressPlaceholder"' 'placeholder explícito ausente.'
Assert-Contains $xaml 'Property="CaretBrush" Value="\{DynamicResource BrowserTextPrimaryBrush\}"' 'caret não está tematizado.'
Assert-Contains $xaml 'Property="SelectionBrush" Value="\{DynamicResource BrowserSelectionBrush\}"' 'seleção não está tematizada.'
Assert-Contains $xaml 'Property="VerticalContentAlignment" Value="Center"' 'alinhamento vertical central ausente.'
Assert-Contains $xaml 'Property="Padding" Value="0,6,0,6"' 'padding vertical explícito da omnibox ausente.'
Assert-Contains $xaml 'Property="FontSize" Value="14"' 'FontSize explícito da omnibox ausente.'
Assert-Contains $xaml 'Property="TextBlock.LineHeight" Value="20"' 'LineHeight explícito da omnibox ausente.'
Assert-Contains $xaml 'x:Name="PART_ContentHost"' 'template não expõe viewport real PART_ContentHost.'
Assert-Contains $xaml 'x:Name="AddressShell"[^>]*Height="44"' 'AddressShell não exige altura segura.'
Assert-Contains $xaml 'x:Name="AddressBox"[^>]*Height="40"' 'AddressBox não exige altura segura.'
Assert-Contains $xaml 'x:Name="DownloadsButton"' 'acesso direto a Downloads ausente.'
Assert-Contains $xaml 'x:Name="DownloadsButtonLabel"[^>]*Text="Downloads"' 'Downloads não possui rótulo claro na toolbar.'
Assert-Contains $xaml 'x:Name="ExtensionsButton"' 'acesso direto a Extensões ausente.'
Assert-Contains $xaml 'x:Name="ExtensionsButtonLabel"[^>]*Text="Extensões"' 'Extensões não possui rótulo claro na toolbar.'
Assert-Contains $xaml 'x:Name="HubPanel"' 'painel de ferramentas ausente.'
Assert-Contains $xaml 'x:Name="HubGlyph"' 'hierarquia visual do painel ausente.'
Assert-Contains $xaml 'x:Name="BrowserMenuPopup"' 'popup moderno ausente.'
Assert-Contains $xaml 'x:Name="MenuDownloadsButton"' 'Downloads ausente no menu.'
Assert-Contains $xaml 'x:Name="MenuExtensionsButton"' 'Extensões ausente no menu.'
Assert-Contains $xaml 'x:Name="MenuSettingsButton"' 'Configurações ausente no menu.'
Assert-Contains $xaml 'x:Key="MenuGroupCard"' 'menu não possui agrupamento visual.'
Assert-Contains $xaml 'x:Key="MenuGroupLabel"' 'menu não possui hierarquia por grupos.'
Assert-Contains $xaml 'IsKeyboardFocused" Value="True"' 'estados de foco do menu/botões ausentes.'

$inputStyle = [regex]::Match($xaml, '(?s)<Style x:Key="NativeInput".*?</Style>')
if (-not $inputStyle.Success) { throw 'BROWSER_CONTRACT_FAILED: estilo NativeInput não encontrado.' }
if ($inputStyle.Value -notmatch '<ControlTemplate TargetType="TextBox">') {
    throw 'BROWSER_CONTRACT_FAILED: NativeInput não controla explicitamente o viewport do TextBox.'
}
if ($inputStyle.Value -notmatch 'PART_ContentHost') {
    throw 'BROWSER_CONTRACT_FAILED: NativeInput perdeu PART_ContentHost.'
}

$menuMatch = [regex]::Match($xaml, '(?s)<Popup x:Name="BrowserMenuPopup".*</Popup>')
if (-not $menuMatch.Success) { throw 'BROWSER_CONTRACT_FAILED: BrowserMenuPopup não encontrado.' }
if ($menuMatch.Value -match '<Separator') {
    throw 'BROWSER_CONTRACT_FAILED: menu principal voltou a usar separadores WPF legados.'
}
if ($xaml -match '<ContextMenu') {
    throw 'BROWSER_CONTRACT_FAILED: BrowserWindow.xaml voltou a usar ContextMenu legado.'
}

Assert-Contains $features 'ModernDownloads_Click' 'Downloads direto não está ligado a funcionalidade.'
Assert-Contains $features 'ShowDownloadsHub' 'hub real de Downloads ausente.'
Assert-Contains $features 'RefreshDownloadsView' 'lista/progresso de Downloads ausente.'
Assert-Contains $features 'DownloadsEmptyState' 'estado vazio claro de Downloads ausente.'
Assert-Contains $features 'ModernExtensions_Click' 'Extensões direto não está ligado a funcionalidade.'
Assert-Contains $features 'GetBrowserExtensionsAsync\(' 'Extensões não lista o perfil WebView2 real.'
Assert-Contains $features 'InstallAsync\(profile, dialog\.FolderName\)' 'carregamento não usa gerente local validado.'
Assert-Contains $features 'EnableAsync\(' 'Extensões não permite ativar/desativar.'
Assert-Contains $features 'RemoveAsync\(extension\)' 'Extensões não permite remoção gerenciada.'
Assert-Contains $features 'Chrome Web Store' 'UI não delimita a compatibilidade de extensões.'

Assert-Contains $extensions 'AddBrowserExtensionAsync\(' 'gerente não instala extensão WebView2 real.'
Assert-Contains $extensions 'manifest\.json' 'validação de manifest ausente.'
Assert-Contains $extensions 'JsonDocument\.Parse' 'manifest não é analisado como JSON.'
Assert-Contains $extensions 'FileAttributes\.ReparsePoint' 'reparse point/symlink não é bloqueado.'
Assert-Contains $extensions 'EXTENSION_PATH_ESCAPE' 'escape de raiz não é tratado.'
Assert-Contains $extensions 'MaxPackageFiles' 'limite de quantidade de arquivos ausente.'
Assert-Contains $extensions 'MaxPackageBytes' 'limite de tamanho de pacote ausente.'
Assert-Contains $extensions '"Extensions"' 'raiz gerenciada de extensões ausente.'
Assert-Contains $extensions 'managed-extensions\.v1\.json' 'estado de pacotes gerenciados ausente.'
Assert-Contains $extensions 'SanitizeLabel' 'metadados de extensão não são sanitizados.'

# Hosted CI intentionally does not execute user32!SendInput. It compiles the probe,
# executes ABI checks, package validators and failure-report serialization. The real
# interactive desktop remains mandatory for physical/visual acceptance.
Assert-Contains $probe 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-Contains $probe 'LongInput\s*=\s*"https://www\.youtube\.com/results\?search_query=' 'probe não testa URL longa.'
Assert-Contains $probe 'SendInput\(' 'probe físico deixou de usar SendInput.'
Assert-Contains $probe 'SetLastError\s*=\s*true' 'SendInput perdeu SetLastError=true.'
Assert-Contains $probe 'Marshal\.GetLastPInvokeError\(\)' 'falha de SendInput não registra Win32 sanitizado.'
Assert-Contains $probe 'InputSizeX64\s*=\s*40' 'contrato x64 de INPUT não exige 40 bytes.'
Assert-Contains $probe 'InputSizeX86\s*=\s*28' 'contrato x86 de INPUT não exige 28 bytes.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public MouseInput mouse' 'INPUT_UNION não contém MOUSEINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public KeyboardInput keyboard' 'INPUT_UNION não contém KEYBDINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public HardwareInput hardware' 'INPUT_UNION não contém HARDWAREINPUT.'
Assert-Contains $probe 'Marshal\.SizeOf<Input>\(\)' 'probe não mede sizeof(INPUT).'
Assert-Contains $probe '--validate-input-layout-only' 'probe não oferece teste ABI seguro para CI.'
Assert-Contains $probe '--validate-diagnostics-contract-only' 'probe não testa serialização de falha.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Capture' 'probe não captura contexto físico.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Evaluate' 'probe não bloqueia contexto físico incompatível.'
Assert-Contains $probe 'OmniboxVisualDiagnostics\.Measure' 'probe não mede viewport real da omnibox.'
Assert-Contains $probe 'CaptureElement\(' 'probe não gera close-up físico da omnibox.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''A''\)' 'probe não testa Ctrl+A.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''C''\)' 'probe não testa Ctrl+C.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''V''\)' 'probe não testa Ctrl+V.'
Assert-Contains $probe 'PressKey\(VK_HOME\)' 'probe não testa Home.'
Assert-Contains $probe 'PressKey\(VK_END\)' 'probe não testa End.'
Assert-Contains $probe 'PressKey\(VK_RETURN\)' 'probe não testa Enter.'
Assert-Contains $probe '01-omnibox-empty-closeup\.png' 'close-up da omnibox vazia ausente.'
Assert-Contains $probe '02-omnibox-typed-closeup\.png' 'close-up da omnibox digitada ausente.'
Assert-Contains $probe '03-omnibox-selected-closeup\.png' 'close-up da omnibox selecionada ausente.'
Assert-Contains $probe '13-menu-complete\.png' 'captura completa do menu ausente.'
Assert-Contains $probe '14-downloads\.png' 'captura de Downloads ausente.'
Assert-Contains $probe '15-extensions\.png' 'captura de Extensões ausente.'
Assert-Contains $probe '16-settings\.png' 'captura de Configurações ausente.'
Assert-Contains $probe 'ExtensionLoadButton' 'probe não exige controle real de carregamento de extensão.'
Assert-Contains $probe 'DownloadsEmptyState' 'probe não exige estado visível de Downloads.'

Assert-Contains $omniboxDiagnostics 'PART_ContentHost' 'diagnóstico visual não usa o viewport do template.'
Assert-Contains $omniboxDiagnostics 'TransformToVisual\(contentHost\)' 'bounds do texto não são transformados para o viewport real.'
Assert-Contains $omniboxDiagnostics 'ClipToleranceDip\s*=\s*0\.5' 'tolerância de clipping não é pequena/objetiva.'
Assert-Contains $omniboxDiagnostics 'FormattedText\(' 'diagnóstico não compara métricas de texto formatado.'
Assert-Contains $omniboxDiagnostics 'CaretBrush' 'diagnóstico não prova caret visível.'
Assert-Contains $omniboxDiagnostics 'SelectionBrush' 'diagnóstico não prova seleção visível.'
Assert-Contains $omniboxDiagnostics 'content\.Top < viewport\.Top' 'clipping superior não é detectado.'
Assert-Contains $omniboxDiagnostics 'content\.Bottom > viewport\.Bottom' 'clipping inferior não é detectado.'

Assert-Contains $diagnostics 'Environment\.UserInteractive' 'diagnóstico não registra modo interativo.'
Assert-Contains $diagnostics 'OpenInputDesktop' 'diagnóstico não inspeciona input desktop.'
Assert-Contains $diagnostics 'GetForegroundWindow' 'diagnóstico não verifica foreground.'
Assert-Contains $diagnostics 'GetGUIThreadInfo' 'diagnóstico não verifica active/focus da GUI queue.'
Assert-Contains $diagnostics 'TokenIntegrityLevel\s*=\s*25' 'diagnóstico não consulta integrity level.'

Assert-Contains $reporting 'validation\.json' 'relatório não grava validation.json.'
Assert-Contains $reporting 'PhysicalInputContext' 'relatório não preserva contexto físico.'
Assert-Contains $reporting 'OmniboxVisuals' 'relatório não preserva métricas visuais da omnibox.'
Assert-Contains $reporting 'Artifacts' 'relatório não lista artefatos.'
Assert-Contains $reporting 'ProbeErrorReport' 'relatório não preserva erro sanitizado.'

$combinedProbe = $probe + "`n" + $diagnostics + "`n" + $omniboxDiagnostics
if ($combinedProbe -match 'address\.Text\s*=(?!=)') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: entrada da omnibox não pode ser simulada por atribuição direta de Text.'
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
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: relatório CI não-físico declarou validação física.'
    }
    if ($json.stage -ne 'diagnostics-contract-self-test' -or $json.error.code -ne 'SELF_TEST_FAILURE_REPORT') {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: etapa/código de falha não foram serializados.'
    }
    if ($null -eq $json.omniboxVisuals) {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: seção omniboxVisuals ausente.'
    }
}
finally {
    Remove-Item -LiteralPath $diagnosticsOutput -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS native Browser omnibox/menu/downloads/extensions + physical probe contract'
