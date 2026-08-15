$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$xamlPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.xaml'
$featuresPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.Features.cs'
$surfaceCoordinatorPath = Join-Path $PSScriptRoot '..\desktop\CloudOS.Host\Browser\BrowserWindow.SurfaceCoordinator.cs'
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

# Omnibox contract is intentionally frozen after physical approval.
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
Assert-Contains $xaml 'x:Name="ExtensionsButton"' 'acesso direto a Extensões ausente.'
Assert-Contains $xaml 'x:Name="HubPanel"' 'painel de ferramentas ausente.'
Assert-Contains $xaml 'x:Name="BrowserMenuPopup"' 'popup moderno ausente.'
Assert-Contains $xaml 'x:Name="MenuDownloadsButton"' 'Downloads ausente no menu.'
Assert-Contains $xaml 'x:Name="MenuExtensionsButton"' 'Extensões ausente no menu.'
Assert-Contains $xaml 'x:Name="MenuSettingsButton"' 'Configurações ausente no menu.'
Assert-Contains $xaml 'x:Name="MenuClearDataButton"' 'último item obrigatório do menu ausente.'
Assert-Contains $xaml 'x:Key="MenuGroupCard"' 'menu não possui agrupamento visual.'
Assert-Contains $xaml 'x:Key="MenuGroupLabel"' 'menu não possui hierarquia por grupos.'

$inputStyle = [regex]::Match($xaml, '(?s)<Style x:Key="NativeInput".*?</Style>')
if (-not $inputStyle.Success -or $inputStyle.Value -notmatch '<ControlTemplate TargetType="TextBox">' -or $inputStyle.Value -notmatch 'PART_ContentHost') {
    throw 'BROWSER_CONTRACT_FAILED: contrato do NativeInput aprovado foi alterado.'
}
$menuMatch = [regex]::Match($xaml, '(?s)<Popup x:Name="BrowserMenuPopup".*</Popup>')
if (-not $menuMatch.Success) { throw 'BROWSER_CONTRACT_FAILED: BrowserMenuPopup não encontrado.' }
if ($menuMatch.Value -match '<Separator') { throw 'BROWSER_CONTRACT_FAILED: menu principal voltou a usar Separator legado.' }
if ($xaml -match '<ContextMenu') { throw 'BROWSER_CONTRACT_FAILED: BrowserWindow.xaml voltou a usar ContextMenu legado.' }

Assert-Contains $features 'ModernDownloads_Click' 'Downloads direto não está ligado a funcionalidade.'
Assert-Contains $features 'ShowDownloadsHub' 'hub real de Downloads ausente.'
Assert-Contains $features 'RefreshDownloadsView' 'lista/progresso de Downloads ausente.'
Assert-Contains $features 'DownloadsEmptyState' 'estado vazio claro de Downloads ausente.'
Assert-Contains $features 'ModernExtensions_Click' 'Extensões direto não está ligado a funcionalidade.'
Assert-Contains $features 'GetBrowserExtensionsAsync\(' 'Extensões não lista o perfil WebView2 real.'
Assert-Contains $features 'InstallAsync\(profile, dialog\.FolderName\)' 'carregamento não usa gerente local validado.'
Assert-Contains $features 'EnableAsync\(' 'Extensões não permite ativar/desativar.'
Assert-Contains $features 'RemoveAsync\(extension\)' 'Extensões não liga remoção ao gerente.'
Assert-Contains $features 'Chrome Web Store' 'UI não delimita compatibilidade de extensões.'

Assert-Contains $surfaceCoordinator 'PlacementMode\.Custom' 'popup não usa posicionamento customizado dentro da BrowserWindow.'
Assert-Contains $surfaceCoordinator 'CustomPopupPlacementCallback' 'popup não possui callback de reposicionamento.'
Assert-Contains $surfaceCoordinator 'fitsToRight' 'popup não reposiciona para a esquerda quando necessário.'
Assert-Contains $surfaceCoordinator 'MaxHeight\s*=\s*available' 'altura do popup não é limitada ao espaço disponível.'
Assert-Contains $surfaceCoordinator 'VerticalScrollBarVisibility\s*=\s*ScrollBarVisibility\.Auto' 'menu não habilita rolagem interna.'
Assert-Contains $surfaceCoordinator 'KeyboardNavigation\.SetTabNavigation' 'menu não contém navegação cíclica por teclado.'
Assert-Contains $surfaceCoordinator 'BringIntoView\(' 'itens rolados não são trazidos à área visível.'
Assert-Contains $surfaceCoordinator 'Grid\.SetColumn\(child, ReferenceEquals\(child, HubPanel\) \? 1 : 0\)' 'hub não foi convertido para coluna lateral real.'
Assert-Contains $surfaceCoordinator 'WebViewHost\.Visibility\s*=\s*Visibility\.Visible' 'hub ainda pode deixar o host de conteúdo oculto.'
Assert-Contains $surfaceCoordinator '_activeTab\.View\.Visibility\s*=\s*Visibility\.Visible' 'hub não restaura WebView2 normal ao lado do painel.'
Assert-Contains $surfaceCoordinator 'Componente do perfil WebView2 · não gerenciado pelo CloudOS' 'ownership não é diferenciada visualmente.'
Assert-Contains $surfaceCoordinator 'parent\.Children\.Remove\(remove\)' 'UI não remove ação destrutiva de extensão não gerenciada.'

Assert-Contains $extensions 'BrowserExtensionPackageValidator\.ValidatePackage' 'gerente não delega validação do pacote.'
Assert-Contains $extensions 'AddBrowserExtensionAsync\(' 'gerente não instala extensão WebView2 real.'
Assert-Contains $extensions 'managed-extensions\.v1\.json' 'estado de pacotes gerenciados ausente.'
Assert-Contains $extensions 'IsManagedExtension\(' 'gerente não expõe classificação de ownership.'
Assert-Contains $extensions 'EXTENSION_NOT_CLOUDOS_MANAGED' 'remoção de extensão não gerenciada não falha fechada.'
Assert-Contains $extensions 'BrowserManagedExtensionOwnership\.IsSafeManagedPackagePath' 'estado/remoção não exige package-* controlado.'
Assert-Contains $ownership 'Guid\.TryParseExact\(suffix, "N"' 'package-* não exige GUID canônico.'
Assert-Contains $ownership 'Directory\.GetParent\(full\)' 'ownership não exige filho direto da raiz gerenciada.'
Assert-Contains $ownership 'IsSafeStagingPath' 'staging seguro deixou de ser distinguido de package removível.'

Assert-Contains $extensionValidator 'manifest\.json' 'validação de manifest ausente.'
Assert-Contains $extensionValidator 'JsonDocument\.Parse' 'manifest não é analisado como JSON.'
Assert-Contains $extensionValidator 'FileAttributes\.ReparsePoint' 'reparse point/symlink não é bloqueado.'
Assert-Contains $extensionValidator 'EXTENSION_PATH_ESCAPE' 'escape de raiz não é tratado.'
Assert-Contains $extensionValidator 'MaxPackageFiles' 'limite de quantidade de arquivos ausente.'
Assert-Contains $extensionValidator 'MaxPackageBytes' 'limite de tamanho de pacote ausente.'
Assert-Contains $extensionValidator 'SanitizeLabel' 'metadados de extensão não são sanitizados.'
Assert-Contains $extensionValidator 'manifestVersion is not \(2 or 3\)' 'manifest_version não é validado explicitamente.'

# Hosted CI compiles these paths and runs non-interactive contracts; SendInput remains physical-only.
Assert-Contains $probe 'ShortInput\s*=\s*"youtube\.com"' 'probe não testa youtube.com.'
Assert-Contains $probe 'SendInput\(' 'probe físico deixou de usar SendInput.'
Assert-Contains $probe 'SetLastError\s*=\s*true' 'SendInput perdeu SetLastError=true.'
Assert-Contains $probe 'Marshal\.GetLastPInvokeError\(\)' 'falha de SendInput não registra Win32 sanitizado.'
Assert-Contains $probe 'InputSizeX64\s*=\s*40' 'contrato x64 de INPUT não exige 40 bytes.'
Assert-Contains $probe 'InputSizeX86\s*=\s*28' 'contrato x86 de INPUT não exige 28 bytes.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public MouseInput mouse' 'INPUT_UNION não contém MOUSEINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public KeyboardInput keyboard' 'INPUT_UNION não contém KEYBDINPUT.'
Assert-Contains $probe '\[FieldOffset\(0\)\]\s*public HardwareInput hardware' 'INPUT_UNION não contém HARDWAREINPUT.'
Assert-Contains $probe '--validate-input-layout-only' 'probe não oferece teste ABI seguro para CI.'
Assert-Contains $probe '--validate-diagnostics-contract-only' 'probe não testa serialização de falha.'
Assert-Contains $probe 'ExpectedScale is null.*100d' 'probe físico não está restrito à escala 100%.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Capture' 'probe não captura contexto físico.'
Assert-Contains $probe 'PhysicalInputDiagnostics\.Evaluate' 'probe não bloqueia contexto físico incompatível.'
Assert-Contains $probe 'OmniboxVisualDiagnostics\.Measure' 'probe não preserva diagnóstico aprovado da omnibox.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''A''\)' 'probe não testa Ctrl+A.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''C''\)' 'probe não testa Ctrl+C.'
Assert-Contains $probe 'Chord\(VK_CONTROL, ''V''\)' 'probe não testa Ctrl+V.'
Assert-Contains $probe 'PressKey\(VK_HOME\)' 'probe não testa Home.'
Assert-Contains $probe 'PressKey\(VK_END\)' 'probe não testa End.'
Assert-Contains $probe 'PressKey\(VK_RETURN\)' 'probe não testa Enter.'
Assert-Contains $probe 'PressKey\(VK_UP\)' 'probe não percorre Configurações fisicamente pelo menu.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.EnsureMenuInsideWindow' 'menu-complete não verifica bounds físicos contra a BrowserWindow.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.PrepareWebViewSentinelAsync' 'probe não prepara conteúdo físico determinístico no WebView2.'
Assert-Contains $probe 'SurfaceVisualDiagnostics\.EnsureHubAndWebView' 'probe não mede composição física hub + WebView2.'
Assert-Contains $probe 'AddUnmanagedProbeExtensionAsync' 'probe não cria fixture WebView2 não gerenciada real.'
Assert-Contains $probe '!ownershipManager\.IsManagedExtension' 'probe não confirma que a fixture externa é não gerenciada.'
Assert-Contains $probe '"Remover"' 'probe não verifica ação Remover.'
Assert-Contains $probe '13-menu-window\.png' 'captura da BrowserWindow com popup ausente.'
Assert-Contains $probe '13-menu-complete\.png' 'close-up completo do popup ausente.'
Assert-Contains $probe '14-downloads\.png' 'captura de Downloads ausente.'
Assert-Contains $probe '15-extensions\.png' 'captura de Extensões ausente.'
Assert-Contains $probe '16-settings\.png' 'captura de Configurações ausente.'

Assert-Contains $surfaceDiagnostics 'EnsureInside\(popupBounds, windowBounds' 'diagnóstico não falha quando popup sai da janela.'
Assert-Contains $surfaceDiagnostics 'CopyFromScreen\(' 'diagnóstico não lê a superfície física real.'
Assert-Contains $surfaceDiagnostics 'SentinelColor' 'diagnóstico não possui referência não-branca determinística.'
Assert-Contains $surfaceDiagnostics 'sampled\.R >= 245' 'superfície branca não é detectada.'
Assert-Contains $surfaceDiagnostics 'webView\.Visibility != Visibility\.Visible' 'WebView2 oculto não é detectado.'
Assert-Contains $surfaceDiagnostics 'webBounds\.Right > hubBounds\.Left' 'sobreposição hub/WebView2 não é detectada.'
Assert-Contains $surfaceDiagnostics 'EnsureElementVisibleInScrollViewer' 'acesso por teclado a item rolado não é validado.'

Assert-Contains $omniboxDiagnostics 'PART_ContentHost' 'diagnóstico visual não usa viewport aprovado da omnibox.'
Assert-Contains $omniboxDiagnostics 'ClipToleranceDip\s*=\s*0\.5' 'tolerância de clipping da omnibox mudou.'
Assert-Contains $omniboxDiagnostics 'FormattedText\(' 'diagnóstico de texto formatado foi removido.'
Assert-Contains $diagnostics 'Environment\.UserInteractive' 'diagnóstico não registra modo interativo.'
Assert-Contains $diagnostics 'OpenInputDesktop' 'diagnóstico não inspeciona input desktop.'
Assert-Contains $diagnostics 'GetForegroundWindow' 'diagnóstico não verifica foreground.'
Assert-Contains $diagnostics 'GetGUIThreadInfo' 'diagnóstico não verifica fila GUI.'
Assert-Contains $diagnostics 'TokenIntegrityLevel\s*=\s*25' 'diagnóstico não consulta integrity level.'

Assert-Contains $reporting 'validation\.json' 'relatório não grava validation.json.'
Assert-Contains $reporting 'PhysicalInputContext' 'relatório não preserva contexto físico.'
Assert-Contains $reporting 'OmniboxVisuals' 'relatório não preserva métricas da omnibox.'
Assert-Contains $reporting 'SurfaceVisuals' 'relatório não preserva métricas das superfícies.'
Assert-Contains $reporting 'SampledWebViewPixel' 'relatório não registra pixel físico WebView2 amostrado.'
Assert-Contains $reporting 'Artifacts' 'relatório não lista artefatos.'

$combinedProbe = $probe + "`n" + $diagnostics + "`n" + $omniboxDiagnostics + "`n" + $surfaceDiagnostics
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

Write-Host 'PASS native Browser menu/hubs/extension ownership + hardened physical probe contract'
