@echo off
setlocal EnableExtensions

where git.exe >nul 2>nul || (
  echo ERROR: git.exe nao encontrado no PATH.
  pause
  exit /b 1
)

where pwsh.exe >nul 2>nul || (
  echo ERROR: PowerShell 7 ^(pwsh.exe^) nao encontrado no PATH.
  pause
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "EVIDENCE_WORKTREE="
for /f "usebackq delims=" %%I in (`git -C "%SCRIPT_DIR%" rev-parse --show-toplevel 2^>nul`) do set "EVIDENCE_WORKTREE=%%I"

if not defined EVIDENCE_WORKTREE (
  echo ERROR: nao foi possivel localizar a worktree Git a partir de:
  echo %SCRIPT_DIR%
  pause
  exit /b 1
)

echo Evidence worktree: %EVIDENCE_WORKTREE%
git -C "%EVIDENCE_WORKTREE%" status --short
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%CHECKPOINT_EVIDENCE.ps1" -EvidenceWorktree "%EVIDENCE_WORKTREE%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo EVIDENCE PUSH: SUCCESS
) else (
  echo EVIDENCE PUSH: ERROR ^(exit=%EXIT_CODE%^)
)
pause
exit /b %EXIT_CODE%
