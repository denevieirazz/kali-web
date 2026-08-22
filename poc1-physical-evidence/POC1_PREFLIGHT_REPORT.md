# POC1_PREFLIGHT_REPORT.md

**Generated:** 2026-08-22T03:56:38.406Z
**Run:** `mt3ujhg1-ef297576df`
**Phase:** `complete`
**Branch:** `poc/cloudos-linux-runtime-xpra`
**HEAD:** `31c3b830a103b04794fc26eabd04d95422ee0518`
**Distribution:** `kali-linux`
**Decision:** **NO GO**
**xclock executed:** **NO**

## Boundaries

| Layer | Status | Code | Component | Cause | Evidence |
|---|---|---|---|---|---|
| WSL | **PASS** | `WSL_FUNCTIONAL` | WSL service | WSL respondeu à enumeração de distribuições. | [{"name":"kali-linux","state":"Running","version":2,"isDefault":true}] |
| DISTRO | **PASS** | `WSL_DISTRO_RESPONSIVE` | kali-linux | A distro iniciou/respondeu ao comando mínimo. | stateBefore=Running; marker=CLOUDOS_PREFLIGHT_DISTRO_OK |
| XPRA | **FAIL** | `POC_LEDGER_NOT_CLEAN` | POC1 runtime ledger | O ledger contém sessões anteriores; o preflight não mata sessões automaticamente. | [{"id":"xpra-mt3ufi3w-4d6003b4","generation":1,"ownerId":"f29af1c42854e6751fe255c7:2dcf275d-70e7-41d1-81a7-ab73a4e37f3c","app":"firefox","title":"Firefox ESR","distribution":"kali-linux","port":14503,"display":103,"startedAt":"2026-08-22T03:53:28.172Z","leaseExpiresAt":"2026-08-22T03:55:28.172Z","pids":{"xpra":null,"app":null,"xorg":null},"classification":"POC_LEDGER_STALE","linuxAlive":false,"windowsPortAlive":false}] |
| TRANSPORTE | **PASS** | `PREFLIGHT_DISPLAY_PORT_PAIR_READY` | display/port allocator | O mesmo allocator canônico do runtime selecionou o par efêmero para o dry run. | display=:104; port=14504 |
| PROXY | **FAIL** | `PROXY_NOT_REACHED` | PROXY | Camada não alcançada porque XPRA falhou antes. | blockedBy=XPRA |
| IFRAME | **FAIL** | `IFRAME_NOT_REACHED` | IFRAME | Camada não alcançada porque XPRA falhou antes. | blockedBy=XPRA |

## Checks

| Item | Layer | GO/NOGO | Status | Code | Cause | Evidence |
|---|---|---|---|---|---|---|
| forensics-directories | FORENSICS | **GO** | **PASS** | `EVIDENCE_DIRECTORIES_WRITABLE` | Diretórios de evidência existem e aceitaram escrita. | C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\screenshots \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\logs \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\telemetry |
| window-baseline | FORENSICS | **GO** | **PASS** | `WINDOW_BASELINE_CAPTURED` | Processos com MainWindowHandle foram registrados antes do dry run. | count=9; file=C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\WINDOW_BASELINE.json |
| wsl-present | WSL | **GO** | **PASS** | `WSL_PRESENT` | Executável WSL foi localizado. | C:\WINDOWS\System32\wsl.exe |
| wsl-functional | WSL | **GO** | **PASS** | `WSL_FUNCTIONAL` | WSL respondeu à enumeração de distribuições. | [{"name":"kali-linux","state":"Running","version":2,"isDefault":true}] |
| distro-configured | DISTRO | **GO** | **PASS** | `WSL_DISTRO_CONFIGURED` | Distribuição instalada foi resolvida para a prova física. | {"name":"kali-linux","state":"Running","version":2,"isDefault":true} |
| distro-responsive | DISTRO | **GO** | **PASS** | `WSL_DISTRO_RESPONSIVE` | A distro iniciou/respondeu ao comando mínimo. | stateBefore=Running; marker=CLOUDOS_PREFLIGHT_DISTRO_OK |
| xpra-binary | XPRA | **GO** | **PASS** | `XPRA_PRESENT` | Executável Xpra e versão foram obtidos. | /usr/local/bin/xpra<br>xpra v6.5.3-r0 |
| xpra-html5 | XPRA | **GO** | **PASS** | `XPRA_HTML5_PRESENT` | Cliente HTML5 do Xpra foi confirmado por pacote ou asset instalado. | ASSET=/usr/share/xpra/www/index.html |
| xpra-x11 | XPRA | **GO** | **PASS** | `XPRA_X11_PRESENT` | Backend X11 do Xpra foi confirmado. | XPRA_X11_MODULE_OK |
| xclock-present | XPRA | **GO** | **PASS** | `XCLOCK_PRESENT_NOT_EXECUTED` | xclock foi localizado sem ser executado. | /usr/bin/xclock |
| xpra-cli | XPRA | **GO** | **PASS** | `XPRA_CLI_COMPATIBLE` | A ajuda do Xpra expõe as opções essenciais usadas pela POC1. | flags=--start-child,--exit-with-children,--session-name,--bind-tcp,--html,--start-new-commands,--bind |
| display-range | XPRA | **GO** | **WARN** | `XPRA_DISPLAY_RANGE_PARTIALLY_OCCUPIED` | Existem displays ocupados; o allocator compartilhado só usará par correspondente confirmado livre. | {"occupied":[100,101,102,103],"xpraList":""} |
| port-range | TRANSPORTE | **GO** | **PASS** | `XPRA_PORT_RANGE_CLEAR` | Toda a faixa está livre. | {"freeCount":50,"occupied":[]} |
| orphans | XPRA | **NO GO** | **FAIL** | `POC_LEDGER_NOT_CLEAN` | O ledger contém sessões anteriores; o preflight não mata sessões automaticamente. | [{"id":"xpra-mt3ufi3w-4d6003b4","generation":1,"ownerId":"f29af1c42854e6751fe255c7:2dcf275d-70e7-41d1-81a7-ab73a4e37f3c","app":"firefox","title":"Firefox ESR","distribution":"kali-linux","port":14503,"display":103,"startedAt":"2026-08-22T03:53:28.172Z","leaseExpiresAt":"2026-08-22T03:55:28.172Z","pids":{"xpra":null,"app":null,"xorg":null},"classification":"POC_LEDGER_STALE","linuxAlive":false,"windowsPortAlive":false}] |
| dry-run-pair | TRANSPORTE | **GO** | **PASS** | `PREFLIGHT_DISPLAY_PORT_PAIR_READY` | O mesmo allocator canônico do runtime selecionou o par efêmero para o dry run. | display=:104; port=14504 |

## Metrics

```json
{
  "wslSnapshotMs": 59,
  "distroResponsiveMs": 123,
  "xpraProbeMs": 142,
  "displayScanMs": 122,
  "portScanMs": 28,
  "orphanScanMs": 3012,
  "staticPreflightMs": 4054,
  "totalMs": 4406
}
```

## Forensics

- Window baseline: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\WINDOW_BASELINE.json`
- Run log: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\logs\preflight-mt3ujhg1-ef297576df.log`
- Telemetry: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\telemetry\preflight-mt3ujhg1-ef297576df.json`
- Screenshots directory: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\screenshots`

## Final gate

**PRONTO PARA CLICAR ABRIR XCLOCK: NÃO**

Este relatório não prova containment. Ele prova apenas readiness físico antes de executar xclock.
