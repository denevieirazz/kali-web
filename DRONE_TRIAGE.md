# DRONE_TRIAGE.md

## Workflow Autonomous Hardening — triagem do Drone

Branch: `stabilization/cloudos-workflow-batch-4`

Base inicial: `DRONE_REPORT.md` do run válido #10, commit auditado `2225b42c1e0e9df9a0e0411ec4bcf901098680f8`.
Validação após correções: Drone #23, commit auditado `6834fbace3a8a59bf0f551a7dff0eb1917400f7a`.

## Resumo

| Achado | Severidade original | Classificação | Decisão/estado |
|---|---|---|---|
| `503 GET /api/wsl/distributions` | ALTO | BUG DO AMBIENTE/EXPECTATIVA DO DRONE | Runner WebOnly: reclassificado como BAIXO/environment; produto não alterado. |
| `console.error` do mesmo 503 | MÉDIO | BUG DO AMBIENTE/duplicata | Não duplicar o 5xx já capturado por status/URL. |
| `Cannot read properties of undefined (reading 'dimensions')` | ALTO | BUG DO PRODUTO | Corrigido no teardown do Terminal; Drone #23 não reproduziu. |
| restore `esperado=3 recebido=0` | ALTO | BUG DO TESTE | Sincronização do Drone corrigida; aguarda fim do loading e contagem esperada. |

# ROOT CAUSE

## WSL probe 503

### Caminho

O fixture Playwright inicia o backend com `CLOUDOS_NATIVE_HOST=0` e sem lease/token de Host. O Terminal consulta `/api/wsl/distributions` durante o bootstrap para descobrir perfis. Nesse ambiente deliberadamente WebOnly, o endpoint pode responder 503.

### Causa raiz

O Drone tratava qualquer HTTP 5xx como defeito ALTO de produto sem considerar que o próprio fixture desabilitou a capacidade nativa necessária para WSL. O `console.error` era apenas outra manifestação do mesmo 503.

### Impacto

Falso bloqueio do severity gate em CI Linux.

### Classificação

**BUG DO AMBIENTE/EXPECTATIVA DO DRONE.** O backend/WSL não foi alterado para satisfazer o runner.

## xterm `dimensions` undefined

### Caminho de execução

1. `CloudOSTerminal` mantém um `TerminalSession` por aba para preservar contexto.
2. `TerminalSession` executa `terminal.open(host)` e o xterm cria seu `Viewport`/renderer.
3. O xterm 5.3 agenda trabalho interno assíncrono do viewport após `open()` (task e animation frame de refresh/sincronização).
4. No fluxo rápido de tabs (`Ctrl+T`, alternância, `Ctrl+W`), o cleanup React era executado antes de todo esse trabalho interno já enfileirado terminar.
5. O cleanup chamava `terminal.dispose()` imediatamente, destruindo o render service.
6. Um callback interno do viewport já agendado executava depois do dispose e acessava `renderService.dimensions`, produzindo `TypeError: Cannot read properties of undefined (reading 'dimensions')` em `Viewport._innerRefresh`.

### Causa raiz

**Race de teardown entre o cleanup síncrono do `TerminalSession` e callbacks assíncronos já enfileirados pelo viewport do xterm.** Não era uma falha de transporte WSL e a alteração inicial de CSS para preservar geometria, isoladamente, não resolveu o erro.

### Correção

O cleanup continua encerrando imediatamente scheduler CloudOS, `ResizeObserver`, subscriptions, transporte e socket. Somente o `terminal.dispose()` visual é adiado por uma task e um animation frame (`disposeTerminalAfterViewportSettles`) para que callbacks de viewport que já estavam na fila sejam drenados antes da destruição do renderer.

A regressão verifica explicitamente que o dispose não acontece de forma síncrona, não acontece apenas após a task, e ocorre uma única vez após task + frame. O Drone #23 executou a sequência real de tabs/fechamento e não reproduziu o pageerror.

### Impacto anterior

`pageerror` ALTO, quebra potencial de lifecycle visual/foco/restore e falha da Human Simulation.

### Estado

**BUG DO PRODUTO CORRIGIDO E NÃO REPRODUZIDO NO DRONE #23.**

## Restore contado durante loading

### Caminho

O Drone fechava o Terminal, reabria via atalho, esperava `.terminal-workspace` ficar visível e imediatamente contava `.terminal-tab`.

### Causa raiz

O estado de carregamento usa a mesma classe raiz `.terminal-workspace` junto de `.terminal-workspace--loading`. Logo `toBeVisible()` podia resolver antes do restore assíncrono produzir as tabs.

### Correção de teste

O Drone agora espera a remoção de `terminal-workspace--loading` e, para restauração, espera a contagem esperada de tabs antes de classificar divergência.

### Estado

**BUG DO TESTE CORRIGIDO.**

# RESULTADO DO CICLO

Drone inicial válido: **0 CRÍTICOS / 3 ALTOS / 1 MÉDIO**.

Drone #23 após triagem + hardening: **0 CRÍTICOS / 0 ALTOS / 0 MÉDIOS / 1 BAIXO**.

O único BAIXO é a indisponibilidade WSL esperada no runner WebOnly e não recebe correção de produto nesta fase.
