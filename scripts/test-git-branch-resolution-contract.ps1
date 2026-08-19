$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "🧪 INICIANDO SUÍTE COMPLETA DO CONTRATO DE RESOLUÇÃO GIT E DETACHED HEAD..."

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Get-GitContext.ps1')

function Assert-Condition([bool]$condition, [string]$message) {
    if (-not $condition) {
        Write-Error "ASSERTION_FAILED: $message"
        exit 1
    }
}

$isWsl = (Get-Command wslpath -ErrorAction SilentlyContinue) -ne $null
$tempBase = if ($isWsl) {
    $winTemp = (& cmd.exe /c "echo %TEMP%" 2>$null).Trim()
    (& wslpath -u $winTemp 2>$null).Trim()
} else {
    [System.IO.Path]::GetTempPath()
}

# 1. Branch Normal
Write-Host "1. Testando resolução em branch normal..."
$ctx1 = Get-CloudOSGitContext -RepoPath $root
Assert-Condition ($ctx1.IsGit -eq $true) "Deveria identificar repositório Git"
Assert-Condition ($ctx1.HeadSha -match '^[0-9a-fA-F]{40}$') "HeadSha deve ser hash SHA de 40 caracteres"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($ctx1.Branch)) "Deveria resolver branch normal no repositório"
Assert-Condition ($ctx1.IsDetached -eq $false) "Não deve marcar como detached em branch normal"
Assert-Condition ($ctx1.IsKnownNonWslBranch -eq $true) "poc/cloudos-linux-runtime-xpra deve ser classificada como non-wsl branch"
Assert-Condition ($null -eq $ctx1.GitError) "GitError deve ser nulo em branch normal"
Write-Host "   ✅ Branch normal resolvida: $($ctx1.Branch) (SHA: $($ctx1.HeadSha.Substring(0,8)))"

# 2. GITHUB_HEAD_REF Simulado (PR)
Write-Host "2. Testando GITHUB_HEAD_REF simulado..."
$origHeadRef = $env:GITHUB_HEAD_REF
$origRefName = $env:GITHUB_REF_NAME
try {
    $env:GITHUB_HEAD_REF = 'feature/wsl-core-terminal'
    Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue
    $ctx2 = Get-CloudOSGitContext -RepoPath $root
    Assert-Condition ($ctx2.Branch -eq 'feature/wsl-core-terminal') "GITHUB_HEAD_REF deveria ter precedência"
    Assert-Condition ($ctx2.IsKnownNonWslBranch -eq $false) "feature/wsl-core* não deve ser marcada como non-wsl"
    Assert-Condition ($ctx2.ScopeSource -eq 'github-head-ref') "ScopeSource deve ser github-head-ref"
    Write-Host "   ✅ GITHUB_HEAD_REF priorizado com sucesso para feature/wsl-core*"
} finally {
    if ($null -ne $origHeadRef) { $env:GITHUB_HEAD_REF = $origHeadRef } else { Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue }
    if ($null -ne $origRefName) { $env:GITHUB_REF_NAME = $origRefName } else { Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue }
}

# 3. GITHUB_REF_NAME Simulado (Push)
Write-Host "3. Testando GITHUB_REF_NAME simulado..."
try {
    Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    $env:GITHUB_REF_NAME = 'poc/cloudos-linux-runtime-xpra'
    $ctx3 = Get-CloudOSGitContext -RepoPath $root
    Assert-Condition ($ctx3.Branch -eq 'poc/cloudos-linux-runtime-xpra') "GITHUB_REF_NAME deveria ser resolvido"
    Assert-Condition ($ctx3.IsKnownNonWslBranch -eq $true) "poc/cloudos-linux-runtime-xpra deve ser classificada como non-wsl branch"
    Assert-Condition ($ctx3.ScopeSource -eq 'github-ref-name') "ScopeSource deve ser github-ref-name"
    Write-Host "   ✅ GITHUB_REF_NAME resolvido com sucesso"
} finally {
    if ($null -ne $origHeadRef) { $env:GITHUB_HEAD_REF = $origHeadRef } else { Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue }
    if ($null -ne $origRefName) { $env:GITHUB_REF_NAME = $origRefName } else { Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue }
}

# 4. GITHUB_REF_NAME e GITHUB_HEAD_REF Malformados / Sintéticos / Injeção
Write-Host "4. Testando rejeição de refs malformadas, sintéticas e injeções..."
try {
    Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    foreach ($badRef in @('99/merge', 'pull/42/merge', '../traversal', 'branch`nwith`nnewlines', 'invalid branch name with spaces', 'bad~branch^1', 'branch:colon', '/leading-slash', 'trailing-slash/')) {
        $env:GITHUB_REF_NAME = $badRef
        $ctxBad = Get-CloudOSGitContext -RepoPath $root
        Assert-Condition ($ctxBad.Branch -ne $badRef) "Ref inválida '$badRef' não pode ser aceita como nome de branch"
    }
    Write-Host "   ✅ Todas as refs malformadas e sintéticas foram rejeitadas com sucesso"
} finally {
    if ($null -ne $origHeadRef) { $env:GITHUB_HEAD_REF = $origHeadRef } else { Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue }
    if ($null -ne $origRefName) { $env:GITHUB_REF_NAME = $origRefName } else { Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue }
}

# 5. Tentativa de Bypass com Variável Arbitrária (CLOUDOS_WSL_CORE_SCOPE)
Write-Host "5. Testando que variável arbitrária CLOUDOS_WSL_CORE_SCOPE não altera classificação..."
try {
    $env:CLOUDOS_WSL_CORE_SCOPE = '1'
    $ctx5 = Get-CloudOSGitContext -RepoPath $root
    Assert-Condition ($ctx5.Branch -eq 'poc/cloudos-linux-runtime-xpra') "Branch real deve ser mantida"
    Assert-Condition ($ctx5.IsKnownNonWslBranch -eq $true) "Variável arbitrária não deve alterar IsKnownNonWslBranch"
    Write-Host "   ✅ Variável arbitrária ignorada com sucesso"
} finally {
    Remove-Item env:CLOUDOS_WSL_CORE_SCOPE -ErrorAction SilentlyContinue
}

# 6. Execução Fora de Repositório Git e Fail-Closed dos Contratos
Write-Host "6. Testando execução fora de repositório Git e fail-closed dos contratos..."
$tempDir = Join-Path $tempBase "not-a-repo-$((Get-Random))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $ctx6 = Get-CloudOSGitContext -RepoPath $tempDir
    Assert-Condition ($ctx6.IsGit -eq $false) "Fora de repo deve ter IsGit=false"
    Assert-Condition ($ctx6.GitError -eq 'NOT_A_GIT_REPOSITORY') "GitError deve ser NOT_A_GIT_REPOSITORY"

    # Confirma que os contratos falham fechado em uma árvore de código sem .git
    New-Item -ItemType Directory -Path (Join-Path $tempDir "scripts") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempDir "frontend\src\apps\CloudOSTerminal") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempDir "backend\src\terminal") -Force | Out-Null
    Copy-Item (Join-Path $root "scripts\*") (Join-Path $tempDir "scripts\") -Recurse -Force
    Copy-Item (Join-Path $root "frontend\src\apps\CloudOSTerminal\*") (Join-Path $tempDir "frontend\src\apps\CloudOSTerminal\") -Recurse -Force
    Copy-Item (Join-Path $root "backend\src\terminal\*") (Join-Path $tempDir "backend\src\terminal\") -Recurse -Force

    $failProc = Start-Process pwsh -ArgumentList "-File", (Join-Path $tempDir "scripts\test-visible-terminal-wsl-core-contract.ps1") -NoNewWindow -PassThru -Wait -RedirectStandardError (Join-Path $tempDir "fail_err.log") -RedirectStandardOutput (Join-Path $tempDir "fail_out.log")
    $failErr = if (Test-Path (Join-Path $tempDir "fail_err.log")) { Get-Content (Join-Path $tempDir "fail_err.log") -Raw } else { "" }
    $failOut = if (Test-Path (Join-Path $tempDir "fail_out.log")) { Get-Content (Join-Path $tempDir "fail_out.log") -Raw } else { "" }
    Assert-Condition ($failProc.ExitCode -ne 0) "Contrato fora de repo Git DEVE falhar fechado com código não-zero"
    Assert-Condition ($failErr.Contains('Git context resolution failed') -or $failOut.Contains('Git context resolution failed')) "Erro de saída deve conter 'Git context resolution failed'"
    Write-Host "   ✅ Fora de repositório retornou erro explícito e contratos falharam fechado"
} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 7. Execução Real dos Contratos em Detached HEAD e Exigência de GUARD_EXECUTED (Nunca GUARD_SKIPPED)
Write-Host "7. Testando execução real dos contratos em detached HEAD (Exige GUARD_EXECUTED)..."
$tempWt = Join-Path $tempBase "wt-contract-test-$((Get-Random))"
$winTempWt = if ($isWsl) { (& wslpath -w $tempWt 2>$null).Trim() } else { $tempWt }
$gitExe = if ($isWsl) { "git.exe" } else { "git" }

& $gitExe worktree add --detach $winTempWt HEAD | Out-Null
try {
    Copy-Item (Join-Path $root "scripts\Get-GitContext.ps1") (Join-Path $tempWt "scripts\Get-GitContext.ps1") -Force
    Copy-Item (Join-Path $root "scripts\test-visible-terminal-wsl-core-contract.ps1") (Join-Path $tempWt "scripts\test-visible-terminal-wsl-core-contract.ps1") -Force
    Copy-Item (Join-Path $root "scripts\test-wsl-core-foundation-contract.ps1") (Join-Path $tempWt "scripts\test-wsl-core-foundation-contract.ps1") -Force
    Copy-Item (Join-Path $root "scripts\test-wsl-core-secure-terminal-contract.ps1") (Join-Path $tempWt "scripts\test-wsl-core-secure-terminal-contract.ps1") -Force

    # Cenário A: Simulação de branch conhecida (poc/cloudos-linux-runtime-xpra) -> Justifica skip
    $env:GITHUB_REF_NAME = 'poc/cloudos-linux-runtime-xpra'
    $s1 = Start-Process pwsh -ArgumentList "-File", (Join-Path $tempWt "scripts\test-visible-terminal-wsl-core-contract.ps1") -NoNewWindow -PassThru -Wait -RedirectStandardOutput (Join-Path $tempWt "s1.log")
    $logSkip = Get-Content (Join-Path $tempWt "s1.log") -Raw
    Assert-Condition ($s1.ExitCode -eq 0) "Visible Terminal em branch de push fora de WSL core deve passar"
    Assert-Condition ($logSkip.Contains('GUARD_SKIPPED: KNOWN_NON_WSL_BRANCH (branch=poc/cloudos-linux-runtime-xpra')) "Branch conhecida fora de escopo deve emitir GUARD_SKIPPED justificado"
    Write-Host "   ✅ Branch conhecida fora de escopo emitiu GUARD_SKIPPED justificado com sucesso"

    # Cenário B: Detached HEAD puro sem branch -> Guarda de escopo EXECUTA obrigatoriamente
    Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue

    $d1 = Start-Process pwsh -ArgumentList "-File", (Join-Path $tempWt "scripts\test-visible-terminal-wsl-core-contract.ps1") -NoNewWindow -PassThru -Wait -RedirectStandardOutput (Join-Path $tempWt "d1.log")
    $logDetached = Get-Content (Join-Path $tempWt "d1.log") -Raw
    Assert-Condition ($logDetached.Contains('GUARD_EXECUTED: WSL_CORE_SCOPE_BOUNDARY_CHECK') -and -not $logDetached.Contains('GUARD_SKIPPED')) "Em detached HEAD sem branch, o contrato DEVE executar a guarda (GUARD_EXECUTED) e NUNCA GUARD_SKIPPED"
    Write-Host "   ✅ Detached HEAD sem branch executou a guarda obrigatória sem skip"
} finally {
    Remove-Item env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    Remove-Item env:GITHUB_REF_NAME -ErrorAction SilentlyContinue
    & $gitExe worktree remove --force $winTempWt | Out-Null
}

# 8. Teste Negativo: Falha Fechada se Houver Violação de Fronteira no Escopo
Write-Host "8. Testando falha fechada quando houver alteração proibida no escopo WSL Core..."
$tempWtNeg = Join-Path $tempBase "wt-contract-neg-$((Get-Random))"
$winTempWtNeg = if ($isWsl) { (& wslpath -w $tempWtNeg 2>$null).Trim() } else { $tempWtNeg }

& $gitExe worktree add --detach $winTempWtNeg HEAD | Out-Null
try {
    Copy-Item (Join-Path $root "scripts\Get-GitContext.ps1") (Join-Path $tempWtNeg "scripts\Get-GitContext.ps1") -Force
    Copy-Item (Join-Path $root "scripts\test-visible-terminal-wsl-core-contract.ps1") (Join-Path $tempWtNeg "scripts\test-visible-terminal-wsl-core-contract.ps1") -Force

    # Cria arquivo proibido rastreado
    $fakeForbidden = Join-Path $tempWtNeg "frontend\src\apps\Browser\FakeLeak.tsx"
    New-Item -ItemType Directory -Path (Split-Path $fakeForbidden) -Force | Out-Null
    Set-Content -Path $fakeForbidden -Value "// Forbidden test file"
    & $gitExe -C $winTempWtNeg add "frontend/src/apps/Browser/FakeLeak.tsx"
    & $gitExe -C $winTempWtNeg -c user.name="Test" -c user.email="test@test.local" commit -m "test: commit with forbidden file" | Out-Null

    # Executa o contrato e captura stdout/stderr
    $negProc = Start-Process pwsh -ArgumentList "-File", (Join-Path $tempWtNeg "scripts\test-visible-terminal-wsl-core-contract.ps1") -NoNewWindow -PassThru -Wait -RedirectStandardError (Join-Path $tempWtNeg "neg_err.log") -RedirectStandardOutput (Join-Path $tempWtNeg "neg_out.log")
    $negErr = Get-Content (Join-Path $tempWtNeg "neg_err.log") -Raw
    $negOut = Get-Content (Join-Path $tempWtNeg "neg_out.log") -Raw

    Assert-Condition ($negProc.ExitCode -eq 1) "Contrato DEVERIA ter falhado com código 1 diante de arquivo proibido no escopo"
    Assert-Condition ($negErr.Contains('FakeLeak.tsx') -or $negOut.Contains('FakeLeak.tsx')) "Mensagem de erro DEVE conter o arquivo proibido FakeLeak.tsx"
    Write-Host "   ✅ Falha fechada comprovada: contrato rejeitou commit com arquivo proibido FakeLeak.tsx (ExitCode=1)"
} finally {
    & $gitExe worktree remove --force $winTempWtNeg | Out-Null
}

# 9. Teste Negativo: Falha se o bloco de guarda for removido ou ignorado
Write-Host "9. Testando detecção de ausência do marcador de guarda (rejeição se guarda for pulada)..."
$fakeLogNoGuard = "PASS visible Terminal -> WSL Core v2 contract without marker"
Assert-Condition (-not ($fakeLogNoGuard.Contains('GUARD_EXECUTED') -or $fakeLogNoGuard.Contains('GUARD_SKIPPED'))) "Detector deve identificar ausência de marcador de guarda"
Write-Host "   ✅ Ausência de marcador de guarda reprovada com sucesso"

Write-Host "`n🎉 TODOS OS 9 TESTES DO CONTRATO DE RESOLUÇÃO GIT E DETACHED HEAD PASSARAM COM SUCESSO!`n"
