$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$featuresPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.Features.cs'
$surfaceCoordinatorPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.SurfaceCoordinator.cs'
$sideHubPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.SideHubComposition.cs'
$geometryPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserSurfaceGeometry.cs'
$extensionsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserExtensionManager.cs'
$ownershipPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserManagedExtensionOwnership.cs'
$extensionValidatorPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserExtensionPackageValidator.cs'
$probePath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\Program.cs'
$omniboxDiagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\OmniboxVisualDiagnostics.cs'
$surfaceDiagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\SurfaceVisualDiagnostics.cs'
$diagnosticsPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\PhysicalInputDiagnostics.cs'
$reportingPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\ProbeReporting.cs'
$probeProject = Join-Path $PSScriptRoot '..\desktop\CloudOS.Browser.PhysicalProbe\CloudOS.Browser.PhysicalProbe.csproj'

$xaml = Get-Content -Raw -LiteralPath $xamlPath
$features = Get-Content -Raw -LiteralPath $featuresPath
$surfaceCoordinator = Get-Content -Raw -LiteralPath $surfaceCoordinatorPath
$sideHub = Get-Content -Raw -LiteralPath $sideHubPath
$geometry = Get-Content -Raw -LiteralPath $geometryPath
$extensions = Get-Content -Raw -LiteralPath $extensionsPath
$ownership = Get-Content -Raw -LiteralPath $ownershipPath
$extensionValidator = Get-Content -Raw -LiteralPath $extensionValidatorPath
$probe = Get-Content -Raw -LiteralPath $probePath
$omniboxDiagnostics = Get-Content -Raw -LiteralPath $omniboxDiagnosticsPath
$surfaceDiagnostics = Get-Content -Raw -LiteralPath $surfaceDiagnosticsPath
$diagnostics = Get-Content -Raw -LiteralPath $diagnosticsPath
$reporting = Get-Content -Raw -LiteralPath $reportingPath

function Assert-Contains([string]$content, [string]$pattern, [string]$message) {
    if ($content -notmatch $pattern) { throw "BROWSER_CONTRACT_FAILED: $message" }
}

# Omnibox contract is frozen after physical approval.
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

$inputStyle = [regex]::Match($xaml, '(?s)<Style x:Key="NativeInput".*?</Style>')
if (-not $inputStyle.Success -or $inputStyle.Value -notmatch '<ControlTemplate TargetType="TextBox">' -or $inputStyle.Value -notmatch 'PART_ContentHost') {
    throw 'BROWSER_CONTRACT_FAILED: contrato do NativeInput aprovado foi alterado.'
}

# Existing menu geometry and keyboard correction must remain intact.
Assert-Contains $surfaceCoordinator 'PlacementMode\.Custom' 'popup não usa posicionamento customizado.'
Assert-Contains $surfaceCoordinator 'CustomPopupPlacementCallback' 'popup não possui callback customizado.'
Assert-Contains $surfaceCoordinator 'fitsToRight' 'popup não recua para a esquerda.'
Assert-Contains $surfaceCoordinator 'MaxHeight\s*=\s*available' 'popup não limita altura.'
Assert-Contains $surfaceCoordinator 'VerticalScrollBarVisibility\s*=\s*ScrollBarVisibility\.Auto' 'menu não usa scroll interno.'
Assert-Contains $surfaceCoordinator 'KeyboardNavigation\.SetTabNavigation' 'menu perdeu navegação de teclado.'
Assert-Contains $surfaceCoordinator 'BringIntoView\(' 'menu não traz item focado ao viewport.'
Assert-Contains $surfaceCoordinator 'Grid\.SetColumn\(child, ReferenceEquals\(child, HubPanel\) \? 1 : 0\)' 'hub deixou de usar coluna física separada.'

# Side hubs must bypass the legacy ShowHub collapse path for every real entry point, including Popup buttons.
Assert-Contains $sideHub 'EventManager\.RegisterClassHandler\(' 'correção não intercepta Click antes do handler legado.'
Assert-Contains $sideHub 'e\.Handled\s*=\s*true' 'handler legado não é bloqueado para hubs corrigidos.'
Assert-Contains $sideHub 'DownloadsButton' 'Downloads direto não usa fluxo preservador.'
Assert-Contains $sideHub 'MenuDownloadsButton' 'Downloads do menu não usa fluxo preservador.'
Assert-Contains $sideHub 'ExtensionsButton' 'Extensões direto não usa fluxo preservador.'
Assert-Contains $sideHub 'MenuExtensionsButton' 'Extensões do menu não usa fluxo preservador.'
Assert-Contains $sideHub 'MenuSettingsButton' 'Configurações do Popup não usa fluxo preservador.'
Assert-Contains $sideHub 'Application\.Current\.Windows' 'botões hospedados em Popup não resolvem a BrowserWindow proprietária.'
Assert-Contains $sideHub 'OpenSideHubPreservingActiveSurface' 'fluxo lateral preservador ausente.'
Assert-Contains $sideHub 'WebViewHost\.Visibility\s*=\s*Visibility\.Visible' 'host WebView2 não é mantido visível.'
Assert-Contains $sideHub '_activeTab\.View\.Visibility\s*=\s*Visibility\.Visible' 'aba normal não permanece visível.'
Assert-Contains $sideHub 'InvalidateMeasure\(' 'resize do viewport não é invalidado após abrir hub.'
Assert-Contains $sideHub 'InvalidateArrange\(' 'arranjo do viewport não é invalidado após abrir hub.'

# Extension ownership remains fail-closed.
Assert-Contains $features 'GetBrowserExtensionsAsync\(' 'Extensões não lista perfil real.'
Assert-Contains $extensions 'EXTENSION_NOT_CLOUDOS_MANAGED' 'remoção não gerenciada não falha fechada.'
Assert-Contains $extensions 'BrowserManagedExtensionOwnership\.IsSafeManagedPackagePath' 'remoção não exige package-* seguro.'
Assert-Contains $ownership 'Guid\.TryParseExact\(suffix, "N"' 'package-* não exige GUID canônico.'
Assert-Contains $ownership 'Directory\.GetParent\(full\)' 'ownership não exige filho direto.'
Assert-Contains $extensionValidator 'FileAttributes\.ReparsePoint' 'symlink/reparse point não é bloqueado.'
Assert-Contains $extensionValidator 'EXTENSION_PATH_ESCAPE' 'escape de raiz não é tratado.'
Assert-Contains $extensionValidator 'MaxPackageFiles' 'limite de arquivos ausente.'
Assert-Contains $extensionValidator 'MaxPackageBytes' 'limite de bytes ausente.'

# Pure, runtime-tested geometry used by the physical gate.
Assert-Contains $geometry 'ScaleDipRect' 'conversão DIP/pixel não foi extraída para contrato testável.'
Assert-Contains $geometry 'SelectInteriorRegion' 'seleção de região interna segura ausente.'
Assert-Contains $geometry 'BuildSampleGrid' 'matriz regional de amostragem ausente.'
Assert-Contains $geometry 'EvaluateColors' 'avaliação proporcional de cor ausente.'
Assert-Contains $geometry 'DefaultMinimumMatchRatio\s*=\s*0\.80' 'limiar mínimo de sentinela não é 80%.'
Assert-Contains $geometry 'DefaultMaximumWhiteRatio\s*=\s*0\.10' 'limiar de branco não está limitado.'
Assert-Contains $geometry 'HorizontalOverlapPixels' 'detecção de overlap ausente.'

# Physical input contract remains real SendInput and 100%-only.
Assert-Contains $probe 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-Contains $probe 'SendInput\(' 'probe deixou de usar SendInput.'
Assert-Contains $probe 'SetLastError\s*=\s*true' 'SendInput perdeu SetLastError=true.'
Assert-Contains $probe 'Marshal\.GetLastPInvokeError\(\)' 'falha de SendInput não registra Win32.'
Assert-Contains $probe 'InputSizeX64\s*=\s*40' 'INPUT x64 deixou de exigir 40 bytes.'
Assert-Contains $probe 'InputSizeX86\s*=\s*28' 'INPUT x86 deixou de exigir 28 bytes.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public MouseInput mouse' 'union perdeu MOUSEINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public KeyboardInput keyboard' 'union perdeu KEYBDINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public HardwareInput hardware' 'union perdeu HARDWAREINPUT.'
Assert-Contains $probe 'ExpectedScale is null.*100d' 'probe não está restrito a 100%.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Capture' 'preflight físico ausente.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Evaluate' 'bloqueio de contexto físico ausente.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''A''\)' 'Ctrl+A físico ausente.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''C''\)' 'Ctrl+C físico ausente.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''V''\)' 'Ctrl+V físico ausente.'
Assert-Contains $probe 'PressKey\(VK_HOME\)' 'Home físico ausente.'
Assert-Contains $probe 'PressKey\(VK_END\)' 'End físico ausente.'
Assert-Contains $probe 'PressKey\(VK_RETURN\)' 'Enter físico ausente.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.EnsureMenuInsideWindow' 'menu não verifica bounds físicos.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.PrepareWebViewSentinelAsync' 'sentinela física ausente.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.EnsureHubAndWebView' 'gate regional hub/WebView2 ausente.'
Assert-Contains $probe 'AddUnmanagedProbeExtensionAsync' 'fixture não gerenciada real ausente.'
Assert-Contains $probe '!ownershipManager\.IsManagedExtension' 'fixture não confirma ownership externo.'
Assert-Contains $probe '13-menu-window\.png' 'captura janela/menu ausente.'
Assert-Contains $probe '13-menu-complete\.png' 'captura completa menu ausente.'
Assert-Contains $probe '14-downloads\.png' 'captura Downloads ausente.'
Assert-Contains $probe '15-extensions\.png' 'captura Extensões ausente.'
Assert-Contains $probe '16-settings\.png' 'captura Configurações ausente.'

# Sentinel is a real deterministic navigation, re-confirmed after hub composition.
Assert-Contains $surfaceDiagnostics 'NavigateToString\(' 'sentinela ainda é somente injeção de script na página corrente.'
Assert-Contains $surfaceDiagnostics 'NavigationCompleted' 'sentinela não aguarda NavigationCompleted.'
Assert-Contains $surfaceDiagnostics 'ConfirmSentinelDocumentAsync' 'documento esperado não é confirmado.'
Assert-Contains $surfaceDiagnostics 'document\.readyState === ''complete''' 'documento não exige readyState complete.'
Assert-Contains $surfaceDiagnostics 'DwmFlush\(' 'gate não aguarda ciclo real de composição DWM.'
Assert-Contains $surfaceDiagnostics 'VisualTreeHelper\.GetDpi' 'DPI real da janela não é lido.'
Assert-Contains $surfaceDiagnostics 'PointToScreen' 'bounds físicos não usam PointToScreen.'
Assert-Contains $surfaceDiagnostics 'ScaleDipRect' 'DIP não é comparado com pixels físicos.'
Assert-Contains $surfaceDiagnostics 'SelectInteriorRegion' 'amostragem não evita bordas/overlays.'
Assert-Contains $surfaceDiagnostics 'BuildSampleGrid' 'gate ainda depende de pixel único.'
Assert-Contains $surfaceDiagnostics 'EvaluateColors' 'gate não usa proporção regional.'
Assert-Contains $surfaceDiagnostics 'CopyFromScreen\(' 'gate não lê pixels reais da tela.'
Assert-Contains $surfaceDiagnostics 'HorizontalOverlapPixels' 'overlap hub/WebView não é medido.'
Assert-Contains $surfaceDiagnostics 'TryCaptureStageArtifact\(window, surfaceName\)' 'artefato da etapa não é capturado pelo gate antes da falha.'
Assert-Contains $surfaceDiagnostics 'ProbeRunReport\.Current\?\.RegisterSurface\(surfaceName, report, finalMeasurement: true\)' 'diagnóstico final não é persistido antes da exceção.'
Assert-Contains $surfaceDiagnostics 'hub\.LayoutUpdated' 'não existe observação antecipada antes das asserções do Program.'

foreach ($classification in @(
    'webview-not-rendered',
    'sentinel-navigation-not-completed',
    'sample-outside-webview',
    'dpi-coordinate-mismatch',
    'hub-webview-overlap',
    'white-host-background-visible',
    'unexpected-rendered-color',
    'capture-unavailable')) {
    Assert-Contains $surfaceDiagnostics ([regex]::Escape($classification)) "classificação física ausente: $classification"
    Assert-Contains $reporting ([regex]::Escape($classification)) "relatório não preserva classificação: $classification"
}

# Reporting contract required even on failure.
foreach ($field in @(
    'WindowBounds','HubBounds','WebViewBoundsDip','WebViewBoundsPixels','DpiScale',
    'NavigationCompleted','DocumentConfirmed','SamplingRegion','SamplePoints','ExpectedColor',
    'ObservedColors','MatchRatio','WhitePixelRatio','OverlapPixels','SeparationPixels','WebViewVisible')) {
    Assert-Contains $reporting $field "campo surfaceVisuals ausente: $field"
}
Assert-Contains $reporting 'RegisterSurface' 'relatório não permite persistência antecipada da superfície.'
Assert-Contains $reporting 'PendingSurfaceClassification' 'classificação específica pode ser perdida pelo wrapper legado.'
Assert-Contains $reporting 'validation\.json' 'relatório não grava validation.json.'
Assert-Contains $reporting 'SampledWebViewPixel' 'compatibilidade do relatório físico anterior foi removida.'

Assert-Contains $omniboxDiagnostics 'PART_ContentHost' 'diagnóstico da omnibox deixou o viewport aprovado.'
Assert-Contains $omniboxDiagnostics 'ClipToleranceDip\s*=\s*0\.5' 'tolerância da omnibox mudou.'
Assert-Contains $diagnostics 'Environment\.UserInteractive' 'diagnóstico físico não registra interatividade.'
Assert-Contains $diagnostics 'OpenInputDesktop' 'diagnóstico físico não verifica desktop.'
Assert-Contains $diagnostics 'GetForegroundWindow' 'diagnóstico físico não verifica foreground.'
Assert-Contains $diagnostics 'GetGUIThreadInfo' 'diagnóstico físico não verifica fila GUI.'

$combinedProbe = $probe + "`n" + $diagnostics + "`n" + $omniboxDiagnostics + "`n" + $surfaceDiagnostics
if ($combinedProbe -match 'address\.Text\s*=(?!=)') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: entrada da omnibox não pode ser simulada por atribuição direta de Text.'
}
if ($combinedProbe -match 'SendKeys|AutomationPeer') {
    throw 'BROWSER_PHYSICAL_PROBE_CONTRACT_FAILED: probe não pode substituir SendInput por SendKeys/AutomationPeer.'
}
if ($diagnostics -match 'AttachThreadInput') {
    throw 'BROWSER_PHYSICAL_DIAGNOSTICS_CONTRACT_FAILED: diagnóstico não pode mascarar fila de input.'
}

& dotnet run --project $probeProject -c Release -- --validate-input-layout-only
if ($LASTEXITCODE -ne 0) { throw "BROWSER_PHYSICAL_PROBE_LAYOUT_FAILED: exit=$LASTEXITCODE" }

$diagnosticsOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("cloudos-browser-probe-diagnostics-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    & dotnet run --project $probeProject -c Release -- --output $diagnosticsOutput --validate-diagnostics-contract-only
    if ($LASTEXITCODE -ne 0) { throw "BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: exit=$LASTEXITCODE" }
    $diagnosticsReport = Join-Path $diagnosticsOutput 'validation.json'
    if (-not (Test-Path -LiteralPath $diagnosticsReport)) { throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: validation.json ausente.' }
    $json = Get-Content -Raw -LiteralPath $diagnosticsReport | ConvertFrom-Json
    if ($json.passed -ne $false -or $json.physicalValidation -ne $false) {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: relatório CI não-físico declarou validação física.'
    }
    if ($json.stage -ne 'diagnostics-contract-self-test' -or $json.error.code -ne 'SELF_TEST_FAILURE_REPORT') {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: etapa/código de falha não foram serializados.'
    }
    if ($null -eq $json.omniboxVisuals -or $null -eq $json.surfaceVisuals) {
        throw 'BROWSER_PHYSICAL_DIAGNOSTICS_SELF_TEST_FAILED: métricas visuais obrigatórias ausentes.'
    }
}
finally {
    Remove-Item -LiteralPath $diagnosticsOutput -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS native Browser physical surface gate: preserved WebView, regional sampling, DPI and fail-first reporting'
