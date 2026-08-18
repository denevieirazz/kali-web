# DRONE_TRIAGE.md

## Workflow Autonomous Hardening — triagem do Drone

Branch: `stabilization/cloudos-workflow-batch-4`

Base da triagem: `DRONE_REPORT.md` do run válido #10, commit auditado `2225b42c1e0e9df9a0e0411ec4bcf901098680f8`.

## Resumo

| Achado | Severidade original | Classificação | Decisão |
|---|---|---|---|
| DRONE-0002 `503 GET /api/wsl/distributions` | ALTO | BUG DO AMBIENTE/EXPECTATIVA DO DRONE | Não corrigir produto; retirar do gate de produto quando o fixture estiver em modo sem Native Host/WSL. |
| DRONE-0003 `console.error` do mesmo 503 | MÉDIO | BUG DO AMBIENTE/duplicata | Não corrigir produto; manter como diagnóstico contextual, sem duplicar severidade. |
| DRONE-0005 `Cannot read properties of undefined (reading 'dimensions')` | ALTO | BUG DO PRODUTO | Corrigir lifecycle visual do Terminal e proteger por regressão E2E/Drone. |
| DRONE-0006 restore `esperado=3 recebido=0` | ALTO | BUG DO TESTE | O Drone conta tabs enquanto `.terminal-workspace--loading` já está visível. Aguardar restauração efetiva antes da comparação. |

# ROOT CAUSE

## DRONE-0002 / DRONE-0003 — WSL probe 503

### Caminho

O fixture Playwright inicia o backend com `CLOUDOS_NATIVE_HOST=0` e sem lease/token de Host. O Terminal consulta `/api/wsl/distributions` durante o bootstrap para descobrir perfis. Nesse ambiente deliberadamente WebOnly, o endpoint pode responder 503.

### Causa raiz

O Drone tratava qualquer HTTP 5xx como defeito ALTO de produto sem considerar que o próprio fixture desabilitou a capacidade nativa necessária para WSL. O `console.error` é a manifestação duplicada do mesmo 503 no navegador.

### Impacto

Falso bloqueio do severity gate em CI Linux, mesmo quando o fallback PowerShell/WebOnly funciona como projetado.

### Classificação

**BUG DO AMBIENTE/EXPECTATIVA DO DRONE.** Não alterar WSL, backend, RC ou produto para satisfazer esse runner.

## DRONE-0005 — xterm `dimensions` undefined

### Caminho

`CloudOSTerminal` mantém um `TerminalSession` por aba para preservar contexto. A pane inativa recebe `.terminal-workspace__pane-shell` com `display:none`; a ativa muda para `display:block`. Cada `TerminalSession` abre xterm, mantém transporte e usa `ResizeObserver` + `TerminalFrameScheduler` para `fit()`.

### Causa raiz

A alternância de abas coloca uma instância xterm já aberta em um subtree com **zero layout** (`display:none`) e depois a recoloca em layout. O código CloudOS protege apenas o seu `fit()` com checagens de geometria, porém xterm possui refresh interno assíncrono do viewport. Durante a transição de zero-layout, esse refresh pode executar quando o estado de renderização/dimensões não está disponível e lança dentro de `Viewport._innerRefresh`, fora do `try/catch` do scheduler CloudOS.

O sintoma é coerente com a própria API xterm, onde dimensões de renderização dependem do renderer/`open()`, e com o fato de o erro aparecer durante alternância/lifecycle de tabs, não no transporte WSL.

### Impacto

`pageerror` ALTO, possível quebra visual/foco/restore da sessão, e contaminação das simulações de Terminal.

### Correção permitida

Manter panes inativas fora de interação e visualmente ocultas **sem removê-las do layout com `display:none`**, preservando geometria estável para a instância xterm montada. Não alterar protocolo, transporte, WSL Core ou número de abas.

## DRONE-0006 — restore contado durante loading

### Caminho

O Drone fecha o Terminal, reabre via atalho, espera `.terminal-workspace` ficar visível e imediatamente executa `.terminal-tab.count()`.

### Causa raiz

O estado de carregamento do produto usa a mesma classe raiz `.terminal-workspace` (`.terminal-workspace--loading`). Portanto `toBeVisible()` resolve antes de `readPersistedTerminalWorkspace()` + probe/fallback + `setWorkspace()` produzirem as tabs. O Drone pode observar zero tabs transitórias e declarar divergência mesmo que a restauração aconteça milissegundos depois.

### Impacto

Falso ALTO no gate do Drone.

### Classificação

**BUG DO TESTE.** A comparação deve aguardar o número esperado de tabs ou o fim explícito do estado loading antes de classificar.

# POLÍTICA DE HARDENING

- Produto: corrigir somente DRONE-0005 nesta rodada inicial.
- Teste: corrigir a sincronização do restore do Drone para DRONE-0006.
- Ambiente: contextualizar o 503 WSL do fixture WebOnly para que não bloqueie como defeito de produto.
- Médios/baixos não recebem correção de produto nesta fase.
