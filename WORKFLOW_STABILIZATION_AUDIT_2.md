# WORKFLOW BATCH 4 — STABILIZATION AUDIT 2

## Escopo

Segunda auditoria estática profunda da estabilização do Workflow Batch 4.

- Branch auditada: `stabilization/cloudos-workflow-batch-4`
- HEAD auditado: `706a00e9d420c5b54097a8d1e8e1c63c288d211b`
- Base congelada: `ae08460f8c813ed9264ca330ef918071c6f3c2aa`
- Diff confirmado: 10 commits à frente, 0 atrás, merge-base exatamente na base congelada.
- Arquivos de produto alterados e auditados: `CloudOSFiles.tsx`, `windowsDirectorySource.ts`, `TerminalSession.tsx`, `WorkflowWorkspace.tsx`, `WorkflowBatch4Shell.tsx`, `workflowQuickEvidence.ts`, `workflowWorkspace.ts`.
- Arquivos de validação alterados e revisados: `workflowBatch4Stabilization.test.js`, scope gate e workflow CI da estabilização.
- Nenhuma correção foi aplicada nesta auditoria.
- Nenhuma funcionalidade nova foi criada.
- Batch 5, IA, Browser novo, WSLg, Marketplace, CloudOS Core, RC e Productization permanecem fora do escopo.

## Resultado executivo

A segunda auditoria encontrou **2 defeitos ALTOS, 5 MÉDIOS e 2 BAIXOS** dentro da superfície alterada pela estabilização.

Não foi identificado novo defeito CRÍTICO.

Os dois ALTOS concentram-se em concorrência de gravação de Notes e em uma janela de corrida no recovery visual de abas do Terminal. Ambos podem ocorrer justamente sob troca rápida de contexto, que é um dos cenários prioritários desta estabilização.

---

# CRÍTICO

**Nenhum novo defeito crítico encontrado.**

---

# ALTO

## A2-01 — Autosave e save-before-navigation podem gravar a mesma Note concorrentemente e fora de ordem

**Evidência**

`WorkflowWorkspace.tsx` mantém autosave por `setTimeout(..., 650)` e dispara `saveActiveNote()` de forma assíncrona. `saveActiveNote()` delega para `persistDirtyWorkspaceNote()`. Separadamente, troca de nota, troca de workspace, pesquisa/jump, archive, duplicate, export, import e move também chamam `persistDirtyWorkspaceNote()` antes da navegação. Não existe mutex, generation token, fila por arquivo ou serialização das gravações.

Cenário reproduzível por inspeção:

1. usuário digita conteúdo A;
2. autosave inicia gravação A;
3. antes da Promise terminar, usuário digita conteúdo B;
4. usuário troca de nota/workspace;
5. save-before-navigation inicia gravação B;
6. se a gravação A terminar depois da B, A pode voltar a sobrescrever B no provider;
7. `savedNoteContent.current` também pode ser atualizado fora de ordem.

A proteção nova garante que existe um save antes da navegação, mas não garante **ordem de commit** entre saves já em voo.

**Arquivo**

`frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx`

**Impacto**

Perda silenciosa da versão mais recente de uma Note em edição rápida, principalmente sob provider lento, Windows grant, WSL congestionado ou troca rápida de contexto.

**Risco**

ALTO — perda de dados de Notes; o estado visual pode inclusive terminar indicando `saved` para conteúdo que não é o último conteúdo persistido.

**Correção sugerida**

Serializar saves por `{workspaceId,fileName}`. O save-before-navigation deve aguardar qualquer save anterior e depois persistir o snapshot mais recente. Alternativamente usar generation/revision monotônica e impedir completion antiga de atualizar `savedNoteContent` ou sobrescrever uma revisão mais nova. Adicionar teste com duas Promises resolvidas em ordem invertida.

---

## A2-02 — Recovery de aba Terminal ainda possui corrida quando a aba fica visível antes da falha `Layout indisponível`

**Evidência**

`TerminalSession.tsx` continua executando `initialise()` mesmo quando `visible === false`. O recovery novo depende da transição `becameVisible = visible && !previousVisibleRef.current` **e**, naquele mesmo efeito, de `status.state === 'failed' && status.label === 'Layout indisponível'`.

Existe uma janela:

1. aba nasce/restaura invisível;
2. `initialise()` começa e aguarda `waitForTerminalGeometry()`;
3. usuário troca rapidamente para a aba antes do wait terminar;
4. efeito registra `previousVisibleRef.current = true`, mas status ainda não é `failed`, portanto não incrementa `restartGeneration`;
5. a inicialização antiga termina depois e publica `Layout indisponível`;
6. como `visible` já é true e `previousVisibleRef.current` também, `becameVisible` passa a false;
7. nenhum novo restart automático ocorre.

**Arquivo**

`frontend/src/apps/CloudOSTerminal/TerminalSession.tsx`

**Impacto**

Uma aba restaurada/trocada rapidamente pode permanecer morta até reconexão manual, apesar da correção A-05.

**Risco**

ALTO — falha funcional persistente da sessão visual em cenário real de troca rápida de abas; não há perda de arquivo, mas há quebra do lifecycle do Terminal.

**Correção sugerida**

Não iniciar renderer enquanto `visible` for falso, ou fazer o recovery reagir também à combinação posterior `visible && failed(Layout indisponível)` independentemente de `becameVisible`, com guarda de geração para impedir loop. Adicionar teste determinístico em que `visible` muda para true antes da Promise de geometry resolver.

---

# MÉDIO

## M2-01 — Atalhos de Notes continuam globais e não verificam a janela ativa

**Evidência**

`WorkflowWorkspace.tsx` registra `window.addEventListener('keydown', onKey)` e, quando a aba interna é `notes`, captura `Ctrl+S`, `Ctrl+Shift+S`, `Ctrl+N`, `Ctrl+F` e `F3`. O handler não compara `windowId` com `useWindowManager.getState().activeWindowId`.

A correção equivalente foi aplicada em `CloudOSFiles.tsx`, mas não no Workspace/Notes.

**Arquivo**

`frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx`

**Impacto**

Uma janela Workspace/Notes montada em background pode interceptar atalhos destinados à janela ativa. Com mais de uma instância montada, mais de um listener pode reagir ao mesmo atalho.

**Risco**

MÉDIO — foco incorreto, criação/save/pesquisa na janela errada e atalhos aparentemente presos.

**Correção sugerida**

Aplicar o mesmo boundary por `windowId` usado no Files antes de qualquer `preventDefault()` ou ação de Notes. Cobrir duas janelas simultâneas em teste.

---

## M2-02 — Context panel do Batch 4 ainda usa Workspace global, não necessariamente o Workspace exibido

**Evidência**

`WorkflowBatch4Shell.tsx` calcula `activeWorkspace` através de `getActiveWorkspace()` (localStorage global). A correção de Evidence usa corretamente `displayedWorkspaceId()` para `Ctrl+Shift+E`, porém `showWorkspaceContext`, Notes recentes, Evidence recentes, arquivos e cabeçalho lateral continuam derivados de `activeWorkspace` global.

Durante seleção de Workspace, `setActiveId(workspace.id)` ocorre antes/de forma independente do completion de `activateWorkspace(workspace.id)`. Em Workspace arquivado, a função retorna sem ativar globalmente. Portanto a janela pode exibir Workspace X enquanto o painel lateral continua mostrando Y.

**Arquivo**

`frontend/src/components/Workflow/WorkflowBatch4Shell.tsx`

**Impacto**

Perda de contexto visual: usuário pode acreditar que Notes/Evidence/Recentes do painel pertencem ao Workspace mostrado na janela quando pertencem ao global.

**Risco**

MÉDIO — não grava Evidence no lugar errado após A-04, mas pode induzir ação humana sobre contexto incorreto.

**Correção sugerida**

Derivar o contexto lateral do `data-workspace-id` da janela Workspace ativa ou do `workspaceId` da própria janela, e reservar `getActiveWorkspace()` apenas para fallback quando não há Workspace explícito exibido.

---

## M2-03 — Troca de Workspace não resolve dirty state de arquivo externo aberto no Notes

**Evidência**

`persistDirtyWorkspaceNote()` retorna `true` imediatamente quando `externalFile` existe. `selectWorkspace()` chama essa função e depois altera `activeId`, sem confirmar descarte nem salvar o arquivo externo. O `externalFile` permanece montado e `renderNotes()` continua priorizando `renderExternalEditor()`.

`selectNote()` possui confirmação explícita para `externalDirty`, mas `selectWorkspace()` não possui proteção equivalente.

**Arquivo**

`frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx`

**Impacto**

A janela pode trocar o Workspace de contexto enquanto continua exibindo um arquivo externo dirty associado a outro provider/caminho. O arquivo não é apagado, mas contexto, cabeçalho, Evidence e ações de Workspace podem divergir do editor visível.

**Risco**

MÉDIO — perda de contexto e possibilidade de descarte posterior do arquivo externo por interpretação errada do estado.

**Correção sugerida**

Bloquear troca de Workspace enquanto `externalDirty` não for explicitamente salva ou descartada; para arquivo externo limpo, fechar ou manter contexto de forma explicitamente definida e testada.

---

## M2-04 — Rollback da lixeira Windows pode deixar metadata órfã se a segunda gravação de metadata falhar

**Evidência**

No novo fluxo `trash()`:

1. payload é copiado para `.cloudos-trash`;
2. metadata com a entrada é gravada;
3. origem é removida;
4. se remover origem falhar, a entrada é removida do objeto `meta` e `writeTrashMeta(meta)` é tentado dentro de `try/catch` que ignora falha;
5. independentemente do resultado desse rollback de metadata, o payload da lixeira é removido.

Se o passo 4 falhar, o arquivo original permanece, o payload da lixeira é removido, mas o arquivo de metadata persistido ainda referencia `storedName` inexistente. `listTrash()` silencia a falha por item e não apresenta a entrada, deixando estado órfão invisível.

**Arquivo**

`frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts`

**Impacto**

Metadata persistente inconsistente e entradas invisíveis/stale na lixeira após falha rara de I/O durante rollback.

**Risco**

MÉDIO — não perde a origem nesse caminho, mas degrada integridade transacional e pode acumular estado inválido.

**Correção sugerida**

Só remover o payload rollback após confirmar a remoção da entrada na metadata, ou implementar journal/estado de transação recuperável. Nunca ignorar falha de rollback de metadata sem deixar sinal de recovery.

---

## M2-05 — Restore/Delete/Empty Trash não mantêm atomicidade entre payload e metadata

**Evidência**

`restore()` copia o item ao destino, remove o payload da lixeira e só então grava a metadata sem a entrada. Se `writeTrashMeta()` falhar, a metadata aponta para payload já removido.

`deleteTrash()` remove o payload primeiro e só depois grava metadata. A mesma falha deixa referência órfã.

`emptyTrash()` ignora individualmente falhas de `removeEntry()` e, ao final, grava metadata vazia. Um payload cuja remoção falhou passa a existir fisicamente em `.cloudos-trash`, mas sem metadata e sem forma normal de aparecer na UI.

Esses caminhos ficam mais importantes depois que `readTrashMeta()` passou a tratar corrupção de forma fail-closed.

**Arquivo**

`frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts`

**Impacto**

Estados órfãos, payloads escondidos e metadata stale após falhas de I/O/permissão durante restore/delete/empty.

**Risco**

MÉDIO — integridade da lixeira Windows pode divergir do disco real; em restore a cópia restaurada permanece, mas a lixeira fica inconsistente.

**Correção sugerida**

Definir ordem transacional/journal para todas as operações da lixeira, não apenas `trash()`. `emptyTrash()` deve remover da metadata somente entradas cujo payload foi efetivamente removido, mantendo as falhas recuperáveis/visíveis.

---

# BAIXO

## B2-01 — `activateWorkspace()` emite eventos `workflow-changed` redundantes

**Evidência**

`activateWorkspace()` grava `ACTIVE_WORKSPACE_KEY`, chama `touchWorkspace()`, e `touchWorkspace()` chama `saveWorkspaceList()`, que já executa `emitChanged()`. Ao retornar, `activateWorkspace()` executa outro `emitChanged()`.

O loop crítico de Notes foi interrompido, mas este caminho continua gerando duas notificações para uma única ativação.

**Arquivo**

`frontend/src/services/workflowWorkspace.ts`

**Impacto**

Refreshes e leituras duplicadas nos listeners de Workflow; aumenta ruído e amplia janelas de race sem benefício funcional.

**Risco**

BAIXO — custo e complexidade de eventos; não foi demonstrado loop infinito novo.

**Correção sugerida**

Emitir uma única mudança por transação lógica de ativação, preferencialmente no boundary mais externo.

---

## B2-02 — `createWorkspace()` também emite `workflow-changed` duas vezes

**Evidência**

Após criar o registro, `createWorkspace()` chama `saveWorkspaceList(items)`, que já emite `workflow-changed`; depois grava `ACTIVE_WORKSPACE_KEY` e chama `emitChanged()` novamente.

**Arquivo**

`frontend/src/services/workflowWorkspace.ts`

**Impacto**

Listeners de Workspace/Files/Shell executam refresh duplicado durante criação.

**Risco**

BAIXO — evento duplicado e trabalho redundante; sem evidência de perda de dados por si só.

**Correção sugerida**

Consolidar persistência de lista + active id em uma única transação lógica com um único evento ao final.

---

# Validação por domínio

## Workspace

- Identidade explícita para Evidence na janela ativa: preservada.
- Export usa o objeto `active` exibido: preservado.
- Encontrado mismatch residual entre Workspace exibido e painel lateral global: M2-02.
- Encontrado contexto inconsistente com external file dirty durante troca: M2-03.

## Notes

- Save-before-navigation está presente.
- Autosave de 650 ms continua presente.
- Pesquisa e jump agora chamam persist antes de mudar de nota.
- Encontrada race de gravações concorrentes/out-of-order: A2-01.
- Encontrado listener global sem boundary da janela ativa: M2-01.
- Não foi encontrado novo loop infinito de `workflow-changed` no índice de Notes.

## Evidence

- `Ctrl+Shift+E` usa `workspaceId` explícito quando a janela Workspace está ativa.
- `workflowQuickEvidence.ts` resolve `getWorkspace(workspaceId)` antes de fallback global.
- Não foi encontrada perda direta de Evidence introduzida pela correção.
- O painel lateral ainda pode exibir Evidence de Workspace global diferente: M2-02.

## Files

- Boundary de atalhos pela `activeWindowId` está presente no Files.
- Não foi encontrado double listener novo no Files além do listener React esperado com cleanup.
- Favoritos/fixados não foram funcionalmente alterados pela estabilização; o shell continua lendo as marks persistidas.
- Recentes/index não receberam correção funcional nesta estabilização.
- Lixeira Windows ganhou proteção metadata-before-source-delete, mas rollback e demais operações ainda têm janelas de inconsistência: M2-04 e M2-05.

## Terminal

- O efeito principal possui cleanup de ResizeObserver, subscriptions, transport, socket, scheduler e terminal.
- `restartGeneration` força teardown/recreate controlado.
- Recovery de `Layout indisponível` foi adicionado.
- Encontrada corrida entre mudança de visibilidade e publicação tardia da falha: A2-02.
- Não foi encontrado timer órfão novo dentro de `TerminalSession.tsx`.

## Export ZIP

- A estabilização removeu a interceptação global por texto e chama `downloadWorkspaceZip(active)` diretamente.
- O save-before-export é aguardado antes do ZIP.
- O arquivo `workflowWorkspaceZip.ts` não foi alterado nesta estabilização e, por regra desta auditoria, sua implementação interna não foi reaberta como nova frente.
- O risco relevante para export dentro do diff é A2-01: um autosave anterior ainda em voo pode competir com o save-before-export e tornar o snapshot exportado dependente da ordem das gravações.

---

# Regressões / efeitos colaterais prioritários

1. **A2-01** — serialização de Notes não existe; risco real de latest-write perder para save antigo.
2. **A2-02** — recovery visual do Terminal não cobre todas as ordens possíveis entre visibility e geometry failure.
3. **M2-01** — Notes ainda intercepta atalhos globalmente em background.
4. **M2-02** — correção de identidade foi aplicada ao Evidence shortcut, mas não ao painel de contexto inteiro.
5. **M2-03** — external editor dirty atravessa troca de Workspace sem decisão explícita.
6. **M2-04/M2-05** — lixeira melhorou o caminho de entrada, mas a transação ainda não é simétrica em rollback/restore/delete/empty.
7. **B2-01/B2-02** — eventos redundantes permanecem, sem novo loop crítico demonstrado.

# Conclusão

A estabilização corrigiu os sete defeitos prioritários da primeira auditoria, mas a segunda passagem encontrou duas condições ALTAS que impedem classificar o Workflow Batch 4 como totalmente endurecido para edição rápida e troca agressiva de contexto.

**Nenhum novo defeito crítico encontrado.**

Não se aplica a frase `nenhum novo defeito crítico ou alto encontrado`, pois foram encontrados dois defeitos ALTOS.

Esta entrega é **somente auditoria**. Nenhuma das correções sugeridas foi implementada.