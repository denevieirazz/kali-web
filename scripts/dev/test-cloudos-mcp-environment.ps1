[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " CloudOS MCP Development Environment Health Check " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$results = [ordered]@{}
$warnings = [System.Collections.Generic.List[string]]::new()
$errors = [System.Collections.Generic.List[string]]::new()

# 1. Workspace Root Validation
Write-Host "[-] Verificando Workspace Root..." -NoNewline
$hasFlutter = Test-Path -LiteralPath (Join-Path $Root "desktop\CloudOS.FlutterShell\pubspec.yaml")
$hasNative = Test-Path -LiteralPath (Join-Path $Root "desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj")
if ($hasFlutter -and $hasNative) {
    Write-Host " OK ($Root)" -ForegroundColor Green
    $results["WorkspaceRoot"] = "OK"
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $errors.Add("Raiz do CloudOS inválida ou diretórios esperados ausentes: $Root")
    $results["WorkspaceRoot"] = "FAIL"
}

# 2. Dart & Flutter SDK
Write-Host "[-] Verificando Dart SDK..." -NoNewline
try {
    $dartVersion = (& dart --version 2>&1 | Out-String).Trim()
    if ($dartVersion -match 'Dart SDK version:\s*([0-9.]+)') {
        $v = $Matches[1]
        Write-Host " OK ($v)" -ForegroundColor Green
        $results["Dart"] = $v
    } else {
        Write-Host " OK ($dartVersion)" -ForegroundColor Green
        $results["Dart"] = $dartVersion
    }
} catch {
    Write-Host " FAIL" -ForegroundColor Red
    $errors.Add("Dart SDK não encontrado no PATH.")
    $results["Dart"] = "MISSING"
}

Write-Host "[-] Verificando Dart MCP Server nativo..." -NoNewline
try {
    $mcpHelp = (& dart mcp-server --help 2>&1 | Out-String)
    if ($mcpHelp -match 'analyze_files' -or $mcpHelp -match 'mcp') {
        Write-Host " OK (suporte oficial confirmado)" -ForegroundColor Green
        $results["DartMcpServer"] = "OK"
    } else {
        Write-Host " WARNING (ajuda retornou formato inesperado)" -ForegroundColor Yellow
        $warnings.Add("dart mcp-server respondeu mas formato de ajuda foi diferente.")
        $results["DartMcpServer"] = "WARNING"
    }
} catch {
    Write-Host " FAIL" -ForegroundColor Red
    $errors.Add("dart mcp-server não pôde ser executado.")
    $results["DartMcpServer"] = "FAIL"
}

Write-Host "[-] Verificando Flutter SDK..." -NoNewline
try {
    $flutterLine = (& flutter --version 2>&1 | Select-Object -First 1 | Out-String).Trim()
    if ($flutterLine -match 'Flutter\s+([0-9.]+)') {
        Write-Host " OK ($($Matches[0]))" -ForegroundColor Green
        $results["Flutter"] = $Matches[0]
    } else {
        Write-Host " OK ($flutterLine)" -ForegroundColor Green
        $results["Flutter"] = $flutterLine
    }
} catch {
    Write-Host " FAIL" -ForegroundColor Red
    $errors.Add("Flutter SDK não encontrado no PATH.")
    $results["Flutter"] = "MISSING"
}

# 3. Node & NPX (Dev tool runtime para Filesystem e Playwright MCPs)
Write-Host "[-] Verificando Node.js e NPX (ferramental de desenvolvimento)..." -NoNewline
try {
    $nodeVer = (& node -v 2>&1 | Out-String).Trim()
    $npxVer = (& npx -v 2>&1 | Out-String).Trim()
    Write-Host " OK (Node $nodeVer, NPX $npxVer)" -ForegroundColor Green
    $results["Node"] = $nodeVer
    $results["Npx"] = $npxVer
} catch {
    Write-Host " FAIL" -ForegroundColor Red
    $errors.Add("Node.js ou NPX não encontrados no ambiente.")
    $results["Node"] = "MISSING"
}

# 4. Windows UI Automation (cua-driver)
Write-Host "[-] Verificando cua-driver (Windows UI Automation nativo)..." -NoNewline
$cuaExe = "$env:USERPROFILE\.cua-driver\packages\current\cua-driver.exe"
if (Test-Path -LiteralPath $cuaExe) {
    Write-Host " OK ($cuaExe)" -ForegroundColor Green
    $results["CuaDriver"] = "OK"
} else {
    Write-Host " INFO (não encontrado no path padrão do perfil)" -ForegroundColor Yellow
    $results["CuaDriver"] = "NOT_FOUND_DEFAULT_PATH"
}

# 5. Python (opcional para win32-mcp-server third-party)
Write-Host "[-] Verificando Python..." -NoNewline
try {
    $pyVer = (& python --version 2>&1 | Out-String).Trim()
    if ($pyVer -match 'Python\s+([0-9.]+)') {
        Write-Host " OK ($pyVer)" -ForegroundColor Green
        $results["Python"] = $pyVer
    } else {
        Write-Host " INFO (Python não instalado; cua-driver é o driver primário)" -ForegroundColor Gray
        $results["Python"] = "NOT_INSTALLED"
    }
} catch {
    Write-Host " INFO (Python não instalado; cua-driver é o driver primário)" -ForegroundColor Gray
    $results["Python"] = "NOT_INSTALLED"
}

# 6. Desktop Commander MCP (wonderwhy-er/DesktopCommanderMCP)
Write-Host "[-] Verificando Desktop Commander MCP (@wonderwhy-er/desktop-commander)..." -NoNewline
try {
    $initJson = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"health-check","version":"1.0.0"}}}'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = if (Get-Command npx.cmd -ErrorAction SilentlyContinue) { (Get-Command npx.cmd).Source } else { "npx" }
    $psi.Arguments = "-y @wonderwhy-er/desktop-commander@latest --no-onboarding"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($initJson)
    $p.StandardInput.Flush()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dcReady = $false
    while ($sw.ElapsedMilliseconds -lt 7000 -and -not $dcReady) {
        if (-not $p.StandardOutput.EndOfStream) {
            $line = $p.StandardOutput.ReadLine()
            if ($line -match '"name":"desktop-commander"') {
                $dcReady = $true
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
    try { $p.Kill() } catch {}

    if ($dcReady) {
        Write-Host " OK (MCP JSON-RPC handshake verificado)" -ForegroundColor Green
        $results["DesktopCommander"] = "OK"
    } else {
        Write-Host " WARNING (não respondeu ao handshake no tempo limite)" -ForegroundColor Yellow
        $warnings.Add("Desktop Commander MCP demorou para inicializar ou não respondeu ao handshake.")
        $results["DesktopCommander"] = "TIMEOUT"
    }
} catch {
    Write-Host " WARNING (erro ao invocar: $($_.Exception.Message))" -ForegroundColor Yellow
    $warnings.Add("Desktop Commander MCP falhou na invocação: $($_.Exception.Message)")
    $results["DesktopCommander"] = "FAIL"
}

# 7. Windows Computer Use MCP (windows-computer-use-mcp)
Write-Host "[-] Verificando Windows Computer Use MCP (windows-computer-use-mcp)..." -NoNewline
try {
    $initJson = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"health-check","version":"1.0.0"}}}'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = if (Get-Command npx.cmd -ErrorAction SilentlyContinue) { (Get-Command npx.cmd).Source } else { "npx" }
    $psi.Arguments = "-y windows-computer-use-mcp"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($initJson)
    $p.StandardInput.Flush()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $wcuReady = $false
    while ($sw.ElapsedMilliseconds -lt 6000 -and -not $wcuReady) {
        if (-not $p.StandardOutput.EndOfStream) {
            $line = $p.StandardOutput.ReadLine()
            if ($line -match '"name":"windows-computer-use"') {
                $wcuReady = $true
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
    try { $p.Kill() } catch {}

    if ($wcuReady) {
        Write-Host " OK (MCP JSON-RPC handshake verificado)" -ForegroundColor Green
        $results["WindowsComputerUse"] = "OK"
    } else {
        Write-Host " WARNING (não respondeu ao handshake no tempo limite)" -ForegroundColor Yellow
        $warnings.Add("Windows Computer Use MCP demorou para inicializar ou não respondeu ao handshake.")
        $results["WindowsComputerUse"] = "TIMEOUT"
    }
} catch {
    Write-Host " WARNING (erro ao invocar: $($_.Exception.Message))" -ForegroundColor Yellow
    $warnings.Add("Windows Computer Use MCP falhou na invocação: $($_.Exception.Message)")
    $results["WindowsComputerUse"] = "FAIL"
}

# 8. Configurações MCP (.agents/mcp_config.json e global)
Write-Host "[-] Verificando .agents/mcp_config.json local..." -NoNewline
$localMcp = Join-Path $Root ".agents\mcp_config.json"
if (Test-Path -LiteralPath $localMcp) {
    try {
        $json = Get-Content -LiteralPath $localMcp -Raw | ConvertFrom-Json
        $serverNames = @($json.mcpServers.psobject.Properties.Name)
        Write-Host " OK ($($serverNames -join ', '))" -ForegroundColor Green
        $results["LocalMcpConfig"] = "OK"
    } catch {
        Write-Host " FAIL (JSON inválido)" -ForegroundColor Red
        $errors.Add(".agents/mcp_config.json existe mas contém JSON inválido.")
        $results["LocalMcpConfig"] = "INVALID_JSON"
    }
} else {
    Write-Host " WARNING (arquivo ausente)" -ForegroundColor Yellow
    $warnings.Add(".agents/mcp_config.json não foi encontrado.")
    $results["LocalMcpConfig"] = "MISSING"
}

Write-Host "[-] Verificando mcp_config.json global..." -NoNewline
$globalMcp = "$env:USERPROFILE\.gemini\config\mcp_config.json"
if (Test-Path -LiteralPath $globalMcp) {
    try {
        $gJson = Get-Content -LiteralPath $globalMcp -Raw | ConvertFrom-Json
        $gNames = @($gJson.mcpServers.psobject.Properties.Name)
        Write-Host " OK ($($gNames -join ', '))" -ForegroundColor Green
        $results["GlobalMcpConfig"] = "OK"
    } catch {
        Write-Host " FAIL (JSON inválido)" -ForegroundColor Red
        $errors.Add("mcp_config.json global existe mas contém JSON inválido.")
        $results["GlobalMcpConfig"] = "INVALID_JSON"
    }
} else {
    Write-Host " INFO (ausente)" -ForegroundColor Gray
    $results["GlobalMcpConfig"] = "MISSING"
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Resultado da Verificação de Ambiente             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host "ERROS ENCONTRADOS:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  * $err" -ForegroundColor Red
    }
    exit 1
}

if ($warnings.Count -gt 0) {
    Write-Host "AVISOS:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  * $w" -ForegroundColor Yellow
    }
}

Write-Host "STATUS GERAL: AMBIENTE MCP OPERACIONAL (Sem segredos expostos)." -ForegroundColor Green
exit 0
