# DRONE_TRIAGE.md

## Workflow Autonomous Hardening — triagem do Drone

Branch: `stabilization/cloudos-workflow-batch-4`

Autoridade: resultados reproduzidos pelo Workflow Drone. Nenhum achado baixo/médio foi usado para expandir escopo de produto.

## Resumo dos defeitos reproduzidos

| Achado | Severidade original | Classificação | Estado |
|---|---|---|---|
| `503 GET /api/wsl/distributions` | ALTO | BUG DO AMBIENTE/EXPECTATIVA DO DRONE | Reclassificado BAIXO/environment; runner usa `CLOUDOS_NATIVE_HOST=0`; produto não alterado. |
| `console.error` do mesmo 503 | MÉDIO | BUG DO AMBIENTE/duplicata | Não duplicar o 5xx já contextualizado. |
| xterm `Cannot read properties of undefined (reading 'dimensions')` | ALTO | BUG DO PRODUTO | Corrigido por geometria estável de panes + teardown visual drenado; protegido por regressão. |
| Terminal restore `esperado=3 recebido=0` | ALTO | BUG DO TESTE | Drone agora aguarda fim do loading e contagem restaurada. |
| `Elemento coberto: Exportar Workspace` | ALTO | BUG DO PRODUTO | Sidecar Batch4 não modal deixou de ficar acima das janelas; regressão unitária + Drone. |
| modal interceptando `Novo workspace` na resiliência | harness | BUG DO TESTE | Harness detecta modal já aberto e reutiliza create modal ou fecha modal incompatível. |
| Evidence marker ausente no texto da lista | harness | BUG DO TESTE | UI lista metadata, não conteúdo; harness valida identidade/contagem persistida. |
| Files acionado através de janela Files já ativa | harness | BUG DO TESTE | Human Simulation reutiliza Files ativo; caso contrário foca Workspace antes de acionar Files. |

# ROOT CAUSE

## 1. WSL probe 503

O fixture Playwright inicia o backend sem Native Host/WSL (`CLOUDOS_NATIVE_HOST=0`). O Terminal consulta `/api/wsl/distributions` para descobrir perfis e o endpoint pode responder 503 nesse ambiente deliberadamente WebOnly. O Drone inicialmente tratava qualquer 5xx como ALTO sem considerar a capacidade desativada pelo próprio fixture.

**Classificação:** BUG DO AMBIENTE/EXPECTATIVA DO DRONE. Nenhum código de WSL/Core/backend foi alterado para satisfazer o runner.

## 2. xterm `dimensions` undefined

### Caminho de execução

1. `CloudOSTerminal` mantém um `TerminalSession` por aba.
2. xterm abre renderer/viewport e agenda refresh interno assíncrono.
3. Panes inativas originalmente saíam do layout com `display:none`, levando a geometria zero enquanto callbacks internos ainda podiam estar pendentes.
4. Ao remover rapidamente uma tab, o cleanup também destruía o renderer com `terminal.dispose()` de forma síncrona.
5. Um callback já enfileirado podia executar durante zero-layout ou depois da destruição do render service e acessar `renderService.dimensions`.

### Prova causal

Adiar apenas `terminal.dispose()` não foi suficiente: ao restaurar o CSS original com `display:none`, o Drone voltou a reproduzir o ALTO. A correção exigida é combinada.

### Correção

- pane xterm inativa permanece dimensionada, `visibility:hidden` e `pointer-events:none`, sem `display:none`;
- scheduler CloudOS, observer, subscriptions, transporte e socket encerram imediatamente;
- somente o dispose visual é drenado por uma task + animation frame antes de `terminal.dispose()`.

A regressão verifica a ordem task/frame/dispose e o Drone executa a sequência real de tabs/close/restore.

**Classificação:** BUG DO PRODUTO CORRIGIDO.

## 3. Restore contado durante loading

`.terminal-workspace--loading` compartilha a classe raiz `.terminal-workspace`. O teste usava apenas visibilidade como sinal de restore concluído e podia contar zero tabs transitórias.

O Drone passou a aguardar remoção de `terminal-workspace--loading` e a contagem esperada.

**Classificação:** BUG DO TESTE CORRIGIDO.

## 4. Export Workspace coberto pelo sidecar Batch4

### Caminho de execução

1. `WorkflowBatch4Shell.css` dava `z-index:9800` ao `.wb4-context`.
2. O painel tinha `pointer-events:none`, mas seus botões reativavam `pointer-events:auto`.
3. Quando o sidecar cruzava a região da janela Workspace, um botão do sidecar podia ocupar o centro físico do botão `Exportar`.
4. `document.elementFromPoint()` do Drone confirmou `target=button`, `blocker=button`; a captura mostrou o painel `PROJETO ATUAL` sobre os quick actions.

### Impacto

Uma ação real da janela ativa ficava inacessível por ponteiro. Não era apenas estética.

### Correção

O `.wb4-context`, que é sidecar não modal, recebeu `z-index:95`, abaixo da faixa das janelas de aplicação. Seus botões continuam interativos apenas na parte não coberta por uma janela. O produto não ganhou nova capacidade.

Foi adicionada regressão em `workflowBatch4Stabilization.test.js`, e o rerun do Drone após a correção produziu `CRÍTICO=0 / ALTO=0 / MÉDIO=0 / BAIXO=1`.

**Classificação:** BUG DO PRODUTO CORRIGIDO.

# HARDENING DO HARNESS

A suíte de resiliência foi corrigida sem alteração de produto para:

- detectar modal `.ww-modal:visible` antes de clicar em `Novo workspace`;
- reutilizar o modal de criação já aberto ou fechar um modal incompatível antes de continuar;
- validar Evidence pela entrada persistida (nome/tamanho), pois a lista não renderiza o conteúdo do arquivo;
- manter o restore do Terminal sincronizado pelo fim do loading.

A Human Simulation foi endurecida para não clicar no Workspace através de uma janela Files ativa e para não converter o 503 WSL WebOnly esperado em falha de missão. O Drone continua sendo a autoridade de pageerror/network para ALTO.

A CI deixou de commitar `HUMAN_SIMULATION_REPORT.md` automaticamente depois dos testes; resultados são artifact + job summary. Isso impede que o próprio teste altere o HEAD que acabou de validar.

# POLÍTICA DE FECHAMENTO

- `CRÍTICO` e `ALTO` de produto: corrigir e proteger por regressão.
- BAIXO WSL em WebOnly: registrar, não corrigir.
- pressão de escala previamente classificada como alerta: registrar, não otimizar nesta fase.
- nenhum Browser novo, IA, WSLg, Core, RC, Productization ou Batch 5 foi aberto.
