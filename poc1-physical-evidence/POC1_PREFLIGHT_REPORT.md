# POC1_PREFLIGHT_REPORT.md

**Generated:** 2026-08-22T17:13:03.779Z
**Run:** `mt4mzlco-4c89ad5bb3`
**Phase:** `complete`
**Branch:** `poc/cloudos-linux-runtime-xpra`
**HEAD:** `a21b8144bb0469f5f8eae9d9dc512c4bc556208f`
**Distribution:** `kali-linux`
**Decision:** **GO**
**xclock executed:** **NO**

## Boundaries

| Layer | Status | Code | Component | Cause | Evidence |
|---|---|---|---|---|---|
| WSL | **PASS** | `WSL_FUNCTIONAL` | WSL service | WSL respondeu à enumeração de distribuições. | [{"name":"kali-linux","state":"Running","version":2,"isDefault":true}] |
| DISTRO | **PASS** | `WSL_DISTRO_RESPONSIVE` | kali-linux | A distro iniciou/respondeu ao comando mínimo. | stateBefore=Running; marker=CLOUDOS_PREFLIGHT_DISTRO_OK |
| XPRA | **WARN** | `XPRA_DISPLAY_RANGE_PARTIALLY_OCCUPIED` | :100..:149 | Existem displays ocupados; o allocator compartilhado só usará par correspondente confirmado livre. | {"occupied":[100,101,102,103,104,105,106],"xpraList":""} |
| TRANSPORTE | **PASS** | `XPRA_WEBSOCKET_DIRECT_PASS` | Xpra WebSocket direct | Handshake WebSocket direto com Xpra abriu. | websocket=open |
| PROXY | **PASS** | `CLOUDOS_XPRA_PROXY_WEBSOCKET_PASS` | CloudOS capability WebSocket proxy | Handshake WebSocket atravessou o dispatcher/proxy CloudOS e alcançou Xpra. | url=ws://127.0.0.1:55931/__cloudos/linux-runtime/poc1/preflight-mt4mzlco-4c89ad5bb3/ffb24ef85e1c018668ec9c85c3bea760c1225d00788e7d1a/ |
| IFRAME | **PASS** | `IFRAME_XPRA_CONNECTION_PASS` | CloudOS hidden preflight iframe | Evidência correlacionada out-of-band confirmou frame anexado, navegação HTTP e WebSocket ativo sem violar sandbox. | signals=FRAME_ATTACH,NAVIGATION,SESSION,HTTP,WS,CSP_SANDBOX; httpRequests=64; wsConnections=2; loadMs=263ms |

## Checks

| Item | Layer | GO/NOGO | Status | Code | Cause | Evidence |
|---|---|---|---|---|---|---|
| forensics-directories | FORENSICS | **GO** | **PASS** | `EVIDENCE_DIRECTORIES_WRITABLE` | Diretórios de evidência existem e aceitaram escrita. | C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\screenshots \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\logs \| C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\telemetry |
| window-baseline | FORENSICS | **GO** | **PASS** | `WINDOW_BASELINE_CAPTURED` | Processos com MainWindowHandle foram registrados antes do dry run. | count=0; file=C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\WINDOW_BASELINE.json |
| wsl-present | WSL | **GO** | **PASS** | `WSL_PRESENT` | Executável WSL foi localizado. | C:\WINDOWS\System32\wsl.exe |
| wsl-functional | WSL | **GO** | **PASS** | `WSL_FUNCTIONAL` | WSL respondeu à enumeração de distribuições. | [{"name":"kali-linux","state":"Running","version":2,"isDefault":true}] |
| distro-configured | DISTRO | **GO** | **PASS** | `WSL_DISTRO_CONFIGURED` | Distribuição instalada foi resolvida para a prova física. | {"name":"kali-linux","state":"Running","version":2,"isDefault":true} |
| distro-responsive | DISTRO | **GO** | **PASS** | `WSL_DISTRO_RESPONSIVE` | A distro iniciou/respondeu ao comando mínimo. | stateBefore=Running; marker=CLOUDOS_PREFLIGHT_DISTRO_OK |
| xpra-binary | XPRA | **GO** | **PASS** | `XPRA_PRESENT` | Executável Xpra e versão foram obtidos. | /usr/local/bin/xpra<br>xpra v6.5.3-r0 |
| xpra-html5 | XPRA | **GO** | **PASS** | `XPRA_HTML5_PRESENT` | Cliente HTML5 do Xpra foi confirmado por pacote ou asset instalado. | ASSET=/usr/share/xpra/www/index.html |
| xpra-x11 | XPRA | **GO** | **PASS** | `XPRA_X11_PRESENT` | Backend X11 do Xpra foi confirmado. | XPRA_X11_MODULE_OK |
| xclock-present | XPRA | **GO** | **PASS** | `XCLOCK_PRESENT_NOT_EXECUTED` | xclock foi localizado sem ser executado. | /usr/bin/xclock |
| xpra-cli | XPRA | **GO** | **PASS** | `XPRA_CLI_COMPATIBLE` | A ajuda do Xpra expõe as opções essenciais usadas pela POC1. | flags=--start-child,--exit-with-children,--session-name,--bind-tcp,--html,--start-new-commands,--bind |
| display-range | XPRA | **GO** | **WARN** | `XPRA_DISPLAY_RANGE_PARTIALLY_OCCUPIED` | Existem displays ocupados; o allocator compartilhado só usará par correspondente confirmado livre. | {"occupied":[100,101,102,103,104,105,106],"xpraList":""} |
| port-range | TRANSPORTE | **GO** | **PASS** | `XPRA_PORT_RANGE_CLEAR` | Toda a faixa está livre. | {"freeCount":50,"occupied":[]} |
| orphans | XPRA | **GO** | **PASS** | `POC_ORPHANS_CLEAR` | Nenhuma sessão ativa ou entrada anterior foi encontrada no ledger. | file=C:\Users\dougl\AppData\Local\Temp\cloudos-linux-runtime-poc1-sessions.json; entries=0 |
| dry-run-pair | TRANSPORTE | **GO** | **PASS** | `PREFLIGHT_DISPLAY_PORT_PAIR_READY` | O mesmo allocator canônico do runtime selecionou o par efêmero para o dry run. | display=:107; port=14507 |
| pair-race | TRANSPORTE | **GO** | **PASS** | `PREFLIGHT_PAIR_RECHECK_PASS` | Display e porta continuavam livres imediatamente antes do spawn. | display=:107; port=14507 |
| dry-run-server | XPRA | **GO** | **PASS** | `XPRA_DRY_RUN_SERVER_READY` | Servidor Xpra efêmero respondeu a xpra info sem iniciar xclock. | display=:107; port=14507; auth=env; startChild=false |
| loopback-tcp | TRANSPORTE | **GO** | **PASS** | `WSL_WINDOWS_LOOPBACK_PASS` | Windows alcançou a porta publicada pelo Xpra dentro do WSL. | tcp=connected |
| direct-http | TRANSPORTE | **GO** | **PASS** | `XPRA_HTML5_HTTP_PASS` | Cliente HTML5 respondeu diretamente na porta Xpra. | {"ok":true,"status":200,"contentType":"text/html","xpraHtml":true,"durationMs":23,"error":null} |
| direct-websocket | TRANSPORTE | **GO** | **PASS** | `XPRA_WEBSOCKET_DIRECT_PASS` | Handshake WebSocket direto com Xpra abriu. | websocket=open |
| proxy-http | PROXY | **GO** | **PASS** | `CLOUDOS_XPRA_PROXY_HTTP_PASS` | O backend CloudOS encaminhou HTML5 pelo capability path. | url=http://127.0.0.1:55931/__cloudos/linux-runtime/poc1/preflight-mt4mzlco-4c89ad5bb3/ffb24ef85e1c018668ec9c85c3bea760c1225d00788e7d1a/; status=200 |
| proxy-websocket | PROXY | **GO** | **PASS** | `CLOUDOS_XPRA_PROXY_WEBSOCKET_PASS` | Handshake WebSocket atravessou o dispatcher/proxy CloudOS e alcançou Xpra. | url=ws://127.0.0.1:55931/__cloudos/linux-runtime/poc1/preflight-mt4mzlco-4c89ad5bb3/ffb24ef85e1c018668ec9c85c3bea760c1225d00788e7d1a/ |
| iframe-boundary | IFRAME | **GO** | **PASS** | `IFRAME_XPRA_CONNECTION_PASS` | Evidência correlacionada out-of-band confirmou frame anexado, navegação HTTP e WebSocket ativo sem violar sandbox. | signals=FRAME_ATTACH,NAVIGATION,SESSION,HTTP,WS,CSP_SANDBOX; httpRequests=64; wsConnections=2; loadMs=263ms |
| post-display | POST_CONDITION | **GO** | **PASS** | `POST_DISPLAY_DEAD` | xpra info deixou de responder após Stop. | display=:107 |
| post-port | POST_CONDITION | **GO** | **PASS** | `POST_PORT_CLOSED` | A porta TCP deixou de aceitar conexão. | port=14507 |
| post-websocket | POST_CONDITION | **GO** | **PASS** | `POST_WEBSOCKET_CLOSED` | Handshake WebSocket não abre após Stop, como esperado. | websocket=closed; probe=connect ECONNREFUSED 127.0.0.1:14507 |
| post-ledger | POST_CONDITION | **GO** | **PASS** | `POST_LEDGER_CLEAN` | Nenhuma referência do dry run ficou no ledger. | file=C:\Users\dougl\AppData\Local\Temp\cloudos-linux-runtime-poc1-sessions.json; matching=0 |

## Metrics

```json
{
  "wslSnapshotMs": 47,
  "distroResponsiveMs": 98,
  "xpraProbeMs": 128,
  "displayScanMs": 95,
  "portScanMs": 24,
  "orphanScanMs": 0,
  "staticPreflightMs": 868,
  "dryRunSpawnMs": 5,
  "xpraServerReadyMs": 3349,
  "loopbackTcpMs": 0,
  "directHttpMs": 23,
  "directWebSocketMs": 5,
  "proxyHttpMs": 7,
  "proxyWebSocketMs": 6,
  "totalMs": 8989,
  "iframeLoadMs": 263,
  "iframeHttpRequests": 64,
  "iframeWebSocketConnections": 2,
  "stopMs": 852,
  "postConditionMs": 2011
}
```

## Forensics

- Window baseline: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\WINDOW_BASELINE.json`
- Run log: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\logs\preflight-mt4mzlco-4c89ad5bb3.log`
- Telemetry: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\telemetry\preflight-mt4mzlco-4c89ad5bb3.json`
- Screenshots directory: `C:\Users\dougl\Documents\Codex\2026-08-12\c-users-dougl-gemini-antigravity-scratch\worktrees\CloudOS-workflow-batch-3\poc1-physical-evidence\screenshots`

## Final gate

**PRONTO PARA CLICAR ABRIR XCLOCK: SIM**

Este relatório não prova containment. Ele prova apenas readiness físico antes de executar xclock.
