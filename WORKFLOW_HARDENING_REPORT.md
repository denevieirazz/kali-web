# WORKFLOW_HARDENING_REPORT.md

## Workflow Autonomous Hardening Program

Branch: `stabilization/cloudos-workflow-batch-4`

Escopo: endurecimento do Workflow Batch 4 já existente. Nenhuma capacidade nova foi aberta; Batch 5, IA, Browser novo, WSLg, CloudOS Core, RC e Productization permanecem fora do trabalho.

> Este relatório pertence ao HEAD que o contém. O fechamento só é válido se Drone, resiliência, Long Session, Stress, TypeScript/build, regressões e scope gate forem executados com sucesso contra esse mesmo HEAD. Os IDs e métricas exatas da execução final ficam nos artifacts/job summaries da CI e na entrega executiva.

# DEFEITOS ENCONTRADOS

## Produto — ALTO

### Terminal/xterm: `dimensions` undefined

O renderer do xterm podia receber refresh interno enquanto panes inativas atravessavam geometria zero e, durante fechamento rápido de tab, o cleanup podia destruir o render service antes de callbacks internos já enfileirados terminarem. O resultado era `Viewport._innerRefresh` acessando `renderService.dimensions` depois de o estado visual ficar indisponível.

### Workspace: Export fisicamente coberto pelo sidecar Batch4

O sidecar de contexto do projeto usava `z-index:9800`. Apesar de o painel ser não modal, seus botões reativavam `pointer-events:auto`; quando cruzavam a janela Workspace, podiam ocupar a mesma coordenada física de `Exportar`. O Drone reproduziu o bloqueio com `elementFromPoint()` e screenshot.

## Teste/harness

- restore do Terminal contado enquanto `.terminal-workspace--loading` ainda estava ativo;
- modal de Workspace já aberto e harness tentando clicar em `Novo workspace` através dele;
- Evidence validada procurando conteúdo em uma lista que, por contrato visual, mostra somente metadata;
- cenário de Export iniciando `click()` sem esperar o dispatch e trocando de Workspace em corrida com a ação Playwright;
- Human Simulation tentando acionar Files pelo Workspace quando a janela Files já estava ativa e cobrindo esse controle;
- Human Simulation tratando o 503 WSL deliberadamente WebOnly como falha de missão;
- CI de Human Simulation fazendo auto-commit de relatório depois de testar e, portanto, alterando o próprio HEAD validado.

## Ambiente

`503 GET /api/wsl/distributions` no fixture com `CLOUDOS_NATIVE_HOST=0`. É limitação esperada do runner WebOnly, mantida como BAIXO/environment.

# DEFEITOS CORRIGIDOS

## Terminal/xterm

- panes inativas permanecem dimensionadas, ocultas por `visibility:hidden` e sem interação, em vez de sair do layout com `display:none`;
- transporte, observers, subscriptions e scheduler são encerrados imediatamente;
- `terminal.dispose()` visual só ocorre depois de uma task + animation frame, drenando callbacks de viewport pendentes;
- regressão unitária protege explicitamente a ordem de teardown;
- Drone continua exercitando create/switch/close/restore real de tabs.

A causalidade foi verificada: manter apenas o teardown drenado e restaurar `display:none` fez o ALTO voltar. Portanto a correção combinada é necessária.

## Workspace sidecar

`.wb4-context` passou a ficar abaixo das janelas de aplicação (`z-index:95`). O sidecar continua existindo, mas não tem prioridade para bloquear ações da janela ativa. Foi adicionada regressão estática e o Drone permanece responsável pela prova E2E de obstrução física.

## Harness e CI

- Drone aguarda restore real do Terminal;
- 503 WSL esperado é classificado como ambiente/BAIXO;
- resiliência reutiliza modal de criação já aberto ou fecha modal incompatível antes de continuar;
- resiliência valida Evidence por identidade/contagem persistida;
- resiliência aguarda o dispatch real do clique de Export em A antes da troca A→B, evitando corrida artificial entre comandos Playwright;
- Human Simulation reutiliza Files quando já ativo e só aciona o quick action depois de focar Workspace quando necessário; a regra está no próprio fonte da simulação;
- Human Simulation não reprova pelo 503 WSL esperado;
- relatório de Human Simulation passa a ser artifact/job summary, sem auto-commit pós-teste, preservando o HEAD auditado.

# DEFEITOS REMANESCENTES

Nenhum CRÍTICO ou ALTO pode ser aceito no fechamento deste programa.

Itens deliberadamente não corrigidos por regra de escopo:

- BAIXO: WSL indisponível no runner WebOnly;
- alerta de escala: aumento de heap/DOM/listeners sob 100 Workspaces e 500/1000 Notes;
- médios/baixos que não representem corrupção/perda de dados e não façam parte do gate pedido.

# LONG SESSION

A simulação longa mede heap, DOM, listeners, timers, intervals, ResizeObserver, MutationObserver, localStorage e janelas em horizontes determinísticos equivalentes a 1h/2h/4h/8h.

O baseline imediatamente anterior ao fechamento mostrou estabilidade de DOM/listeners/observers e heap aproximadamente `4.9 MiB -> 6.3 MiB` até o horizonte 8h. Esse número é histórico de comparação; a decisão final deve usar a execução do mesmo HEAD deste relatório.

# STRESS

O cenário obrigatório mantém:

- 100 Workspaces;
- 500 Notes;
- 1000 Notes;
- busca, troca, edição e export ZIP.

O baseline anterior chegou a 1000 Notes sem truncar catálogo, com pressão de heap/DOM já classificada como ALERTA de escala (`~4.9 MiB -> ~61 MiB`). Por regra do programa, esse alerta não é alvo de otimização nesta fase; a execução final deve confirmar ausência de erro/corrupção no mesmo HEAD deste relatório.

# RESILIÊNCIA

A suíte cobre, em sequência real:

1. dirty Note durante fechamento e reabertura;
2. Notes durante busca + troca de Workspace;
3. Evidence durante troca de projeto, validada pela entrada persistida;
4. Export cujo clique é despachado em Workspace A e cuja seleção muda para B enquanto o fluxo assíncrono conclui;
5. Terminal durante fechamento/restauração.

O harness não usa `force` para atravessar modais, não considera conteúdo invisível da Evidence como requisito de DOM e não cria corrida entre comandos Playwright para simular concorrência.

# RISCO ATUAL

O risco principal deixou de ser criação de capacidades e passou a ser lifecycle sob concorrência visual/assíncrona. Os dois ALTOS de produto conhecidos têm causa raiz específica e proteção de regressão.

O risco de escala permanece observável em 1000 Notes, mas está explicitamente fora do escopo de correção deste hardening porque não foi classificado como CRÍTICO/ALTO de integridade.

# PRÓXIMOS GARGALOS

Sem abrir nova frente, os gargalos conhecidos para futuras decisões são:

- custo de DOM/listeners quando o volume de Notes cresce;
- dependência de capacidades nativas fora do runner WebOnly;
- tipos/recursos externos que continuam fail-closed por design.

Esses pontos não autorizam Batch 5, Core, Browser, WSLg, IA ou Productization dentro deste programa.

# CRITÉRIO DE FECHAMENTO

O programa só pode ser declarado pronto para teste humano quando o mesmo HEAD deste relatório apresentar:

- Drone `CRÍTICO=0` e `ALTO=0`;
- resiliência completa sem falha de harness;
- Long Session concluída;
- Stress 100/500/1000 concluído, admitindo somente o alerta de escala já classificado;
- TypeScript + production build aprovados;
- regressões frontend/backend/E2E aprovadas;
- scope gate aprovado;
- nenhuma modificação posterior automática na branch.
