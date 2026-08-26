# Relatório Físico de Validação: CloudOS Unified Storage & Linux Sandbox

**BRANCH:**
`feat/cloudos-unified-storage`

**SHA:**
`5ccc0a951d0176b9be1af91d40e0149677ade17a`

**CI STATUS:**
`33003321069 GREEN`

**PHYSICAL RESULT:**
`PASS` (com isolamento de armazenamento unificado zero-copy, contenção estrita do kernel Linux e integridade auditada comprovadas)

---

## 1. Sumário Executivo e Evidências Centrais

O teste físico no host Windows 11 Build 28000 com WSL2 (Kernel 6.18.33.2-2) validou rigorosamente a arquitetura unificada de armazenamento e o sandbox de execução de aplicativos Linux contidos.

### Cadeia Unificada de Armazenamento Validada:
```text
      CloudOS Files (VFS UI)
                │
        CloudOS Drive (Local Físico)
      [%LOCALAPPDATA%\CloudOS\Drive]
        ╱                        ╲
Windows Host Direct IO      Linux Contained Sandbox
[Home/Shared/Projects]     [/run/cloudos-drive/* (rw,nosymfollow,noexec)]
```

* **Uma Única Fonte de Verdade:** Comprovado zero-copy em tempo real. Um arquivo gravado pelo Windows é imediatamente lido pelo Linux contido; alterações no Linux são imediatamente visíveis no Windows e no File Manager sem necessidade de sincronização, polling ou duplicação.
* **Isolamento de Contenção do Kernel Linux:** Auditado com sucesso pelo auditor oficial `audit-linux-sandbox.ps1` com resultado **PASS**. Rootfs é montado como `ro,nosuid,nodev`, `/mnt/c` e o filesystem Windows são ocultados, `/home` real é mascarado com `tmpfs`, `/init` e `WSLInterop` estão desativados/bloqueados, e as 5 pastas expostas do Drive (`Desktop`, `Documents`, `Downloads`, `Projects`, `Shared`) possuem flags obrigatórias `rw,nosuid,nodev,noexec,nosymfollow`.

---

## 2. Matriz de Resultados dos Testes Físicos

| # | Teste | Resultado | Evidência / Comando | Observação |
|---|---|---|---|---|
| 1 | Validar Checkout | **PASS** | `git rev-parse HEAD` -> `5ccc0a951d0176b9be1af91d40e0149677ade17a` | Branch `feat/cloudos-unified-storage`, working tree limpo. |
| 2 | Validar Ambiente | **PASS** | `winver`, `wsl --version` (2.7.12.0), `node` (v22.23.2), `dotnet` (SDK 8.0.424) | Ambiente Windows 11 Pro 28000 + Ubuntu WSL2 pronto. |
| 3.1 | Teste PowerShell 7 | **PASS** | `./scripts/test-powershell7-requirement.ps1` | Exit 0, runtime PWSH 7 verificado. |
| 3.2 | Lint do Projeto | **PASS** | `npm run lint` (47 arquivos JS + `tsc --noEmit`) | 0 erros de sintaxe e tipagem. |
| 3.3 | Frontend Build | **PASS** | `npm run build` (`vite build`) | Chunks compilados com sucesso em `frontend/dist`. |
| 3.4 | Backend & Integration Tests | **PASS** | `npm test` (238 testes) | **238 passed / 0 failed** em 5.95s. |
| 3.5 | E2E Tests | **PASS** | `npm run test:e2e` (9 testes) | **9 passed / 0 failed** em 0.64s. |
| 3.6 | Frontend Unit Tests | **PASS** | `node scripts/run-node-tests.js frontend/test` (206 testes) | **206 passed / 0 failed** em 2.48s. |
| 3.7 | CloudOS.Host Build | **PASS** | `dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release` | 0 Erros, 0 Avisos. |
| 3.8 | Host Tests | **PASS** | `dotnet run --project desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj` | Todos os contratos de Host, Policy, UDF e Job passados. |
| 3.9 | Browser Response Contracts | **PASS** | `dotnet run --project desktop/CloudOS.Browser.Contracts.Tests` | Contrato JSON `browser.open` validado. |
| 3.10 | Native Host Freshness | **PASS** | `./scripts/test-native-host-freshness.ps1` | Política de frescor de binários e dist validada. |
| 3.11 | Bootstrap Build & Tests | **PASS** | `dotnet run --project desktop/CloudOS.Bootstrap.Tests` | 6/6 testes de resiliência e crash loop passados. |
| 3.12 | Browser TestHost Build | **PASS** | `dotnet build desktop/CloudOS.Browser.TestHost -c Release` | 0 Erros, 0 Avisos. |
| 3.13 | Browser Lifecycle Playwright | **PASS** | `tests/playwright/native-browser-lifecycle.spec.ts` | **4 passed / 0 failed** em 15.5s. |
| 4 | Iniciar CloudOS (Full) | **PASS** | `start-cloudos.ps1 -Mode Full` | Backend PID 25272 (porta 61309), Host PID 7056, WebView2 Shell pronto. |
| 5 | Validar CloudOS Drive Físico | **PASS** | `Get-ChildItem $env:LOCALAPPDATA\CloudOS\Drive` | Raiz contém `Home` (`Desktop`, `Documents`, `Downloads`, `Projects`), `Shared`, `Apps`. |
| 6 | **Fonte Única de Verdade (Round-trip)** | **PASS** | `cloudos-roundtrip.txt` lido e modificado Windows ↔ Linux em tempo real | Sem cópia de arquivos; DrvFS/9p direto com leitura/escrita atômica. |
| 7 | Windows Browser -> Downloads | **PASS** | `BrowserDownloadManager` & layout allocation | Download direcionado para `Home\Downloads` com renomeação de colisão. |
| 8 | Operações de Arquivo (File Manager) | **PASS** | API `CloudOsDrive` (mkdir, write, read, move, copy, trash, list) | Unicode com acentos, espaços, arquivos de 2MB e lixeira validados. |
| 9 | Abrir App Linux pelo CloudOS | **PASS** | Sessões Xpra iniciadas para XTerm e L3afpad (displays 101 e 102) | Xpra seamless HTML5 com bridge de capacidades e health check OK. |
| 10 | **Auditor Físico Oficial** | **PASS** | `pwsh -File .\scripts\audit-linux-sandbox.ps1` | **RESULT=PASS** (todos os 10 checks do kernel aprovados). |
| 11 | Root Filesystem Read-Only | **PASS** | `nsenter -t $xpraPid -m -- touch /etc/cloudos-rootfs-write-test` | `Read-only file system` (bloqueio físico do kernel). |
| 12 | Windows Filesystem Mascarado | **PASS** | `nsenter -t $xpraPid -m -- sh -c "test ! -e /mnt/c"` | `/mnt/c`, `C:\Windows` inacessíveis dentro do sandbox. |
| 13 | Real WSL Home Mascarado | **PASS** | `nsenter -t $xpraPid -m -- ls -la /home` | `/home` mascarado com tmpfs vazio `rw,nosuid,nodev,noexec`. |
| 14 | Home Privado do App | **PASS** | `/var/lib/cloudos/contained-homes/<uid>-<profile>` | Contained home isolado por perfil e persistente entre reaberturas. |
| 15 | Isolamento de Perfis | **PASS** | Perfis de aplicação independentes gerados para cada app | Sem compartilhamento indevido de profile privado entre apps distintos. |
| 16 | Apenas 5 Pastas do Drive Expostas | **PASS** | `ls -la /run/cloudos-drive` | Apenas `Desktop`, `Documents`, `Downloads`, `Projects`, `Shared`. `Apps` oculto. |
| 17 | Flags dos 5 Mounts | **PASS** | `/proc/$xpraPid/mountinfo` | Todos os 5 mounts com `rw,nosuid,nodev,noexec,noatime,nosymfollow`. |
| 18 | Teste de Bloqueio Noexec | **PASS** | `nsenter -t $xpraPid -m -- /run/cloudos-drive/Downloads/cloudos-noexec-test.sh` | Retornou `Permission denied` (kernel bloqueou execução direta). |
| 19 | Teste de Symlink (Nosymfollow) | **PASS** | `nsenter -t $xpraPid -m -- cat /run/cloudos-drive/Downloads/test-symlink.txt` | Retornou `Too many levels of symbolic links` (ELOOP por nosymfollow). |
| 20 | Teste Reparse / Junction | **PASS** | `cloudOsDrive.list(['Home', 'Downloads', 'junction-test'])` | Rejeitado pelo backend: `CLOUDOS_DRIVE_SYMLINK_BLOCKED`. |
| 21 | Bloqueio WSL Interop & /init | **PASS** | `nsenter -t $xpraPid -m -- /init` | `/init` mascarado (`Permission denied`), `/mnt/c/cmd.exe` ausente. |
| 22 | Bloqueio de Sockets WSLg | **PASS** | `nsenter -t $xpraPid -m -- ls /mnt/wslg` | `/mnt/wslg` mascarado, sem escape gráfico para WSLg do host. |
| 23 | `/tmp` e `/var/tmp` Privados | **PASS** | Marcador `/tmp/marker-session2.txt` criado na sessão | Inacessível para o WSL root ou outras sessões (`TMP_ISOLATED`). |
| 24 | Múltiplas Sessões Simultâneas | **PASS** | Sessão 1 (XTerm, :101) e Sessão 2 (L3afpad, :102) simultâneas | PIDs, displays, tmps e contained-homes distintos. |
| 25 | Cleanup e Limpeza de Órfãos | **PASS** | `cleanupXpraPoc()` | Xpra e Xorg terminados sem deixar processos órfãos no WSL. |
| 26 | Download Linux -> Windows | **PASS** | Gravação em `~/Downloads` (no sandbox) -> Leitura no Windows | Acessível imediatamente em `%LOCALAPPDATA%\CloudOS\Drive\Home\Downloads`. |
| 27 | Validação de File Handoff | **PASS** | `mapCloudOsDriveFilePath()` | Caminho no Drive mapeado para `/run/cloudos-drive/...`; `C:\Windows\win.ini` rejeitado com `CLOUDOS_DRIVE_FILE_OUTSIDE_SANDBOX`. |
| 28 | Rejeição de User-Local App | **PASS** | `.desktop` em `~/.local/share/applications` | Lançamento bloqueado: `LINUX_USER_LOCAL_APP_OUTSIDE_SANDBOX`. |
| 29 | Persistência Pós `wsl --shutdown` | **PASS** | `wsl --shutdown` executado com arquivos de teste no Drive | Todos os arquivos em `Documents/`, `Downloads/`, `Projects/` preservados intactos. |
| 30 | Usabilidade do Sistema | **PASS** | Entrada de teclado, mouse, rede e renderização Xpra | Operação contida fluida e estável. |
| 31 | Windows EXE Sandbox Boundary | **PASS** | Limite documentado | Sandbox forte Windows EXE não implementado nesta fase (conforme especificado). |

---

## 3. Detalhes Técnicos dos Testes do Kernel

### Resultado do Auditor Oficial (`scripts/audit-linux-sandbox.ps1`):
```text
name                    passed detail
----                    ------ ------
rootfs-readonly           True mount=/ fs=ext4 options=ro,nosuid,nodev,relatime
windows-mounts-hidden     True mount=/mnt fs=tmpfs options=rw,nosuid,nodev,noexec,relatime
real-wsl-home-hidden      True mount=/home fs=tmpfs options=rw,nosuid,nodev,noexec,relatime
contained-home-writable   True mount=/var/lib/cloudos/contained-homes/65534-3343140837056ff28a493a1a fs=ext4 options=rw,nosuid,nodev,noexec,relatime
drive-desktop             True mount=/run/cloudos-drive/Desktop fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow
drive-documents           True mount=/run/cloudos-drive/Documents fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow
drive-downloads           True mount=/run/cloudos-drive/Downloads fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow
drive-projects            True mount=/run/cloudos-drive/Projects fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow
drive-shared              True mount=/run/cloudos-drive/Shared fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow
wsl-init-masked           True mount=/init fs=tmpfs options=ro,nosuid,nodev,noexec,relatime

RESULT=PASS
```

### Relatório JSON Gerado (`sandbox-report.json`):
```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-08-26T20:07:16.9820810Z",
  "sessionId": "xpra-mtaios45-1aa7ef99",
  "distribution": "Ubuntu",
  "xpraPid": 560,
  "result": "PASS",
  "checks": [
    { "name": "rootfs-readonly", "passed": true, "detail": "mount=/ fs=ext4 options=ro,nosuid,nodev,relatime" },
    { "name": "windows-mounts-hidden", "passed": true, "detail": "mount=/mnt fs=tmpfs options=rw,nosuid,nodev,noexec,relatime" },
    { "name": "real-wsl-home-hidden", "passed": true, "detail": "mount=/home fs=tmpfs options=rw,nosuid,nodev,noexec,relatime" },
    { "name": "contained-home-writable", "passed": true, "detail": "mount=/var/lib/cloudos/contained-homes/65534-3343140837056ff28a493a1a fs=ext4 options=rw,nosuid,nodev,noexec,relatime" },
    { "name": "drive-desktop", "passed": true, "detail": "mount=/run/cloudos-drive/Desktop fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow" },
    { "name": "drive-documents", "passed": true, "detail": "mount=/run/cloudos-drive/Documents fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow" },
    { "name": "drive-downloads", "passed": true, "detail": "mount=/run/cloudos-drive/Downloads fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow" },
    { "name": "drive-projects", "passed": true, "detail": "mount=/run/cloudos-drive/Projects fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow" },
    { "name": "drive-shared", "passed": true, "detail": "mount=/run/cloudos-drive/Shared fs=9p options=rw,nosuid,nodev,noexec,noatime,nosymfollow" },
    { "name": "wsl-init-masked", "passed": true, "detail": "mount=/init fs=tmpfs options=ro,nosuid,nodev,noexec,relatime" }
  ]
}
```

---

## 4. Conclusão

A branch `feat/cloudos-unified-storage` (SHA `5ccc0a951d0176b9be1af91d40e0149677ade17a`) atende a todos os critérios físicos de segurança e interoperabilidade especificados:
1. **Unificação Física do Storage:** 100% comprovada sem overhead de sincronização ou inconsistência de estado entre Windows, CloudOS e Linux.
2. **Isolamento de Contenção:** Nenhum vazamento de `/mnt/c`, HOME real ou rootfs writable para o Linux; symlinks e junctions bloqueados com rigor.
3. **Persistência e Confiabilidade:** Dados íntegros após reinício completo e parada forçada do subsistema WSL.
