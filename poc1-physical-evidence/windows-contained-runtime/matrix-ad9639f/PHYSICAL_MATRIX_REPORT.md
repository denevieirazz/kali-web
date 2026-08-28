# CloudOS PR #16 — Physical Windows Runtime Matrix

PRODUCT_TESTED_SHA=ad9639f1ce8d808d2d532404fd9ca6673244052e

PR_BRANCH=ix/cloudos-runtime-launch-rebind

EVIDENCE_BRANCH=vidence/pr16-physical-ad9639f

PHYSICAL_RUNTIME_GATE=FAIL

Automated CI for this exact product SHA is green. Physical execution on Windows host evaluated direct Win32 containment, Start Menu brokered containment, and Chromium browser containment.

| CASE | APP/EXECUTABLE | RUNTIME CLASS | RUNS | PASS | FAIL | FAIL-CLOSED EXPECTED | EXTERNAL WINDOW LEAK | ALT-TAB LEAK | ORPHAN PROCESS | JOB/launchProcessId RESULT | CAPTURE RESULT | CLOSE/REOPEN RESULT | EVIDENCE PATH | VERDICT |
|---|---|---|---:|---:|---:|---:|---|---|---|---|---|---|---|---|
| win32-simple | Telegram.exe | Win32 standalone | 1 | 0 | 1 | 0 | YES | YES | NO | InJob=false / OwnedByHost=false | Escape | N/A | matrix-ad9639f/telegram-physical-evidence.json | FAIL |
| splash-bootstrap | Mapa de Caracteres | Brokered UWP/Shell | 1 | 0 | 0 | 1 | NO | NO | NO | Blocked by containment policy | N/A | N/A | matrix-ad9639f/ | PASS_EXPECTED_FAIL_CLOSED |
| child-gui | Limpeza de Disco | Brokered Shell | 1 | 0 | 0 | 1 | NO | NO | NO | Blocked by containment policy | N/A | N/A | matrix-ad9639f/ | PASS_EXPECTED_FAIL_CLOSED |
| electron-chromium | brave.exe | Chromium/Browser | 1 | 1 | 0 | 0 | NO | NO | NO | Contained in CloudOS window | Rendered | Passed | matrix-ad9639f/ | PASS |
| shortcut-args | N/A | shortcut with safe argv | 0 | 0 | 0 | 0 | NO | NO | NO | N/A | N/A | N/A | N/A | NOT_APPLICABLE |
| dual-instance | N/A | simultaneous launches | 0 | 0 | 0 | 0 | NO | NO | NO | N/A | N/A | N/A | N/A | NOT_APPLICABLE |
| close-reopen | N/A | lifecycle | 0 | 0 | 0 | 0 | NO | NO | NO | N/A | N/A | N/A | N/A | NOT_APPLICABLE |
| multiwindow-limit | N/A | multiwindow/modal ambiguity | 0 | 0 | 0 | 0 | NO | NO | NO | N/A | N/A | N/A | N/A | NOT_APPLICABLE |
| stress | N/A | repeated lifecycle | 0 | 0 | 0 | 0 | NO | NO | NO | N/A | N/A | N/A | N/A | NOT_APPLICABLE |

## Summary of Findings

1. **Chromium / Brave**: Abriu contido com sucesso dentro do CloudOS (PASS).
2. **Start Menu Brokered Apps (Mapa de Caracteres, Limpeza de Disco, Clima)**: Bloqueados com aviso explicativo de contenção ("Aplicativo protegido pela contenção"), impedindo execução desgovernada (PASS_EXPECTED_FAIL_CLOSED).
3. **Win32 Standalone (Telegram)**: Escapou da contenção (InJob: false, OwnedByHost: false), abrindo como janela externa no desktop e no Alt+Tab do Windows (FAIL).
4. **Instalação de Pacotes**: Observação de usuário registrada; gerenciamento de novos pacotes externos não suportado nesta fase.

