# WORKFLOW_LONG_SESSION_AUDIT.md

## CloudOS Workflow — Long Session Hardening Audit

**Branch auditada:** `stabilization/cloudos-workflow-batch-4`  
**HEAD de produto auditado:** `7838e206a54b2c36b8aca1daa7dfb43e72e75a3e`  
**Modo:** auditoria somente. Nenhuma correção de produto e nenhuma funcionalidade nova.

## Limite metodológico

Esta auditoria não afirma execução real contínua por 1h/2h/4h/8h. A sessão não possui execução assíncrona em background nem telemetria heap contínua. O que foi feito foi uma auditoria de lifecycle, limites e crescimento acumulativo, modelando os mesmos cenários que aparecem em sessões de 1h, 2h, 4h e 8h: repetição de create/archive/import/export, centenas de Notes, muitas trocas de abas, fechamento/reabertura de janelas, clipboard e índices locais.

Não foram inventadas medições de MB. Quando há limite matemático explícito no código ele é citado; quando o crescimento depende do tamanho real dos arquivos, o risco é descrito qualitativamente.

## Resumo

| Severidade | Quantidade |
|---|---:|
| CRÍTICO | 0 |
| ALTO | 2 |
| MÉDIO | 5 |
| BAIXO | 3 |

Os riscos graves não são leaks clássicos de listener/timer. Os dois pontos de maior risco são **perda de referência ao ultrapassar 100 Workspaces** e **pressão de memória/I/O não limitada pela quantidade de Notes carregadas integralmente**.

---

# CRÍTICO

**Nenhum defeito crítico confirmado.**

Não foi encontrado crescimento exponencial, loop infinito novo, listener que se multiplique a cada render ou observer sem teardown dentro da superfície auditada.

---

# ALTO

## H-01 — Criar/importar/duplicar o 101º Workspace torna o mais antigo órfão no índice

### Evidência

`MAX_WORKSPACES = 100`. `saveWorkspaceList()` aplica `items.slice(0, MAX_WORKSPACES)`. Além disso, `createWorkspace()` cria primeiro a árvore física e o `workspace.json`, depois monta o array `[workspace, ...persistedWorkspaces()]` e novamente aplica `.slice(0, MAX_WORKSPACES)`.

Não existe uma etapa que recuse a criação quando o índice já possui 100 itens, nem uma política que arquive/migre/remova fisicamente a entrada descartada.

### Impacto

No 101º Workspace, um registro antigo deixa de ser retornado por `listWorkspaces()`/`getWorkspace()`, enquanto sua pasta em `Workspaces/...` continua existindo no provider. A UI perde a referência normal ao projeto e aos metadados associados.

O mesmo limite afeta fluxos que internamente chamam `createWorkspace()`, incluindo duplicação e importação.

### Risco em sessão longa

- **1h:** improvável em uso normal, mas reproduzível em stress automatizado.
- **2h:** começa a ser relevante em laboratório que cria muitos projetos temporários.
- **4h/8h:** cenário de 100+ solicitado explicitamente torna o defeito determinístico ao cruzar o limite.

### Correção sugerida

Falhar fechado antes de criar o 101º, ou implementar uma política explícita de retenção/recovery que nunca descarte silenciosamente um registro cujo diretório físico continua existindo.

---

## H-02 — Notes carrega conteúdo integral de todas as notas sem limite de quantidade

### Evidência

Cada nota aceita até `MAX_NOTE_BYTES = 2 MiB`. `listWorkspaceNotes()` percorre todas as entradas `.md` do diretório Notes, lê o arquivo inteiro e guarda `content` completo em cada `WorkflowNote`. Não há paginação, lazy loading nem limite de quantidade de notas por Workspace.

`WorkflowWorkspace` mantém esse array inteiro em estado React e a pesquisa executa filtros sobre `title + content`. Paralelamente, `WorkflowBatch4Shell`, quando o Workspace está ativo, também chama `listWorkspaceNotes()` para construir o contexto e só depois corta o resultado para três notas.

### Impacto

Centenas de notas grandes podem gerar pressão severa de heap, GC frequente e I/O repetido. Exemplo de limite teórico: 500 notas próximas de 2 MiB representam aproximadamente 1 GiB apenas em conteúdo bruto antes de overhead de strings/objetos/cópias transitórias.

Não é um leak clássico: a memória pode ser liberada ao trocar/desmontar. O problema é que o conjunto residente é proporcional ao número e tamanho de notas e não possui teto agregado.

### Risco em sessão longa

- **1h:** perceptível com Workspaces já grandes.
- **2h:** pesquisas/autosaves em centenas de notas aumentam CPU/GC.
- **4h/8h:** o custo se repete a cada reload de contexto e pode transformar a sessão em degradação progressiva aparente.

### Correção sugerida

Separar metadata/listagem de leitura de conteúdo, impor teto agregado ou carregar conteúdo sob demanda. Não aplicar durante esta auditoria.

---

# MÉDIO

## M-01 — Abas de Terminal já visitadas permanecem com sessão/socket e scrollback mesmo invisíveis

### Evidência

O Terminal permite no máximo 8 abas. `CloudOSTerminal` mantém um `TerminalSession` montado para cada aba. Depois que uma aba foi visível e inicializou, torná-la invisível não desmonta `TerminalSession` nem encerra transport/socket. `TerminalSession` possui `scrollback: 8000`.

O cleanup de socket, transport, ResizeObserver, subscriptions e xterm existe e é executado ao desmontar/fechar a aba, portanto não há leak órfão confirmado após close.

### Impacto

Uma sessão longa que visite as oito abas pode manter até oito terminais vivos, cada um recebendo output e preservando até 8000 linhas de scrollback. É crescimento **limitado**, mas o baseline de memória e recursos de backend aumenta conforme mais abas são ativadas.

### Correção sugerida

Para hardening futuro, definir política explícita para abas ocultas (continuar viva por design ou suspender). Não alterar agora.

---

## M-02 — `noteSaveChains` pode reter cadeia indefinidamente se provider nunca resolver/rejeitar

### Evidência

A serialização final de Notes usa `noteSaveChains = new Map<string, Promise<void>>()`. A chave é removida no `finally`, o que cobre sucesso e rejeição normais. Porém, se `fileSourceFacade.writeText()` ou `touchWorkspace()` ficar pendente indefinidamente por um provider travado, `finally` nunca executa e saves seguintes da mesma nota esperam a cadeia anterior.

### Impacto

Não cresce indefinidamente sob operação normal, mas uma operação I/O permanentemente pendente pode manter snapshot/Promise e bloquear saves posteriores daquela nota durante toda a sessão.

### Correção sugerida

Timeout/cancelamento no boundary do provider ou watchdog de operação. Fora do escopo desta auditoria.

---

## M-03 — Clipboard metadata é limitado, mas payload OPFS pode acumular se remoção falhar

### Evidência

Clipboard limita metadata a `MAX_CLIPBOARD_ITEMS = 30`, cada item até 5 MiB. Quando há overflow, `removePayload()` tenta apagar o arquivo OPFS, mas captura e ignora qualquer erro. `removeClipboardEntry()` também remove metadata primeiro e depois tenta payload com falha silenciosa.

### Impacto

`localStorage` não cresce sem limite, mas falhas repetidas de remoção física podem deixar arquivos `.cloudos-workflow/Clipboard/*.txt` sem metadata. Em sessão longa, esses órfãos podem acumular armazenamento.

### Correção sugerida

Reconciliação/garbage collection entre metadata e diretório físico, ou retry observável de remoção.

---

## M-04 — Eventos `workflow-changed` podem causar releituras caras de Notes sem loop infinito

### Evidência

O loop crítico anterior foi interrompido porque `indexNotes()` não emite quando o índice não mudou. Porém operações de save/touch ainda podem emitir mais de um `workflow-changed` legítimo. `WorkflowBatch4Shell` depende de `revision` e, enquanto Workspace está ativo, cada revisão dispara novamente `listWorkspaceNotes()` + `listWorkspaceEvidence()`.

### Impacto

Com muitas notas, eventos válidos em sequência podem cancelar logicamente o resultado anterior, mas não cancelam a leitura física já em andamento. Podem coexistir leituras assíncronas redundantes, aumentando I/O/CPU sem formar loop infinito.

### Correção sugerida

Debounce/coalescing ou carga de contexto por metadata. Não corrigir nesta fase.

---

## M-05 — Export ZIP possui pico de memória proporcional ao limite agregado de 64 MiB

### Evidência

O ZIP coleta Notes + Evidence em `zipEntries`, convertendo cada arquivo para `Uint8Array`, depois `createStoreZip(zipEntries)` cria o archive completo e finalmente um `Blob`. O limite agregado é 64 MiB e 2000 entradas.

### Impacto

Export repetido em Workspace grande pode causar picos de heap significativamente maiores que o tamanho final do ZIP devido à coexistência de buffers de origem + estrutura ZIP + Blob. URLs são revogadas com timer 0, portanto não foi encontrado object URL leak persistente.

### Correção sugerida

Streaming ZIP seria a mitigação futura, mas seria mudança estrutural e não deve ser feita nesta fase.

---

# BAIXO

## L-01 — Favoritos/Fixados são limitados a 100, porém referências stale permanecem

### Evidência

`workflowFileMarks` limita a lista a 100 e substitui/deduplica por provider/path/name. Não há crescimento ilimitado de localStorage. Entretanto não existe reconciliação automática após rename/move/delete externo.

### Impacto

Baixo para memória; afeta qualidade de sessão longa porque uma proporção crescente dos 100 slots pode apontar para caminhos inexistentes.

---

## L-02 — Recentes é limitado a 30, porém também pode ficar stale

### Evidência

`workflowRecentFiles` aplica `MAX_RECENT_FILES = 30`, deduplica e corta a lista. Não cresce indefinidamente, mas não valida existência do arquivo ao manter a entrada.

### Impacto

Sem risco de leak de storage; risco apenas de UX/referência obsoleta após horas de rename/move/delete.

---

## L-03 — Listeners/timers/observers revisados possuem teardown ou limite explícito

### Evidência

- `WorkflowWorkspace`: listeners `cloudos:workflow-changed`, `cloudos:clipboard-changed`, `beforeunload` e teclado possuem cleanup.
- Autosave usa timeout de 650 ms com `clearTimeout` no cleanup.
- `WorkflowBatch4Shell`: listeners de workflow/click/keydown possuem cleanup; retry de troca de tab é limitado a 12 `requestAnimationFrame`.
- `TerminalSession`: `ResizeObserver`, subscriptions, transport, WebSocket, frame scheduler e xterm são liberados em `disposeOnce`.
- `CloudOSTerminal`: listener global de teclado possui cleanup e a lista de abas é limitada a 8.

### Impacto

Nenhum listener/observer/timer órfão determinístico foi confirmado nesta superfície.

---

# Análise por horizonte de sessão

## 1 hora

O sistema não apresenta um leak temporal inevitável: listas principais possuem limites e listeners são removidos. Os primeiros sinais de pressão dependem mais de carga do que do relógio: centenas de Notes ou muitas abas de Terminal com output intenso.

## 2 horas

Ao alternar por várias abas de Terminal, cada aba já inicializada permanece viva até ser fechada. O consumo estabiliza no máximo de 8 sessões, mas o baseline pode ficar maior. Clipboard e Recentes continuam limitados em metadata.

## 4 horas

Em uso pesado de Notes, saves/eventos sucessivos podem provocar releituras redundantes do conjunto completo. Clipboard físico pode começar a divergir da metadata se houver erros persistentes de remoção. Favoritos/Fixados/Recentes acumulam referências stale, mas com limites fixos.

## 8 horas

O maior risco é de **volume acumulado de objetos de usuário**. Se a sessão ou testes cruzarem 100 Workspaces, ocorre perda silenciosa de referência do mais antigo. Se um Workspace reunir centenas de Notes, memória e I/O podem degradar fortemente independentemente de o processo estar vivo há exatamente oito horas.

---

# Validação solicitada por subsistema

## Workspace

- Criar: funcional até 100 registros; 101º expõe H-01.
- Arquivar: não reduz quantidade do índice; arquivados continuam consumindo os 100 slots.
- Duplicar/importar: ambos podem empurrar outro Workspace para fora do índice ao limite.
- Export ZIP: bounded por 64 MiB/2000 itens, com pico de memória descrito em M-05.
- Corrupção exponencial: não encontrada.

## Notes

- Quantidade física de notas: sem limite.
- Conteúdo por nota: 2 MiB.
- Índice global: 200 entradas × 8192 caracteres por nota, portanto o índice localStorage é limitado.
- Estado React `notes`: não limitado por quantidade e contém conteúdo integral.
- Pesquisa: limitada a 100 hits exibidos, mas varre o conteúdo carregado das notas.
- Save queue: limpa após settle; risco apenas se provider ficar pendente indefinidamente.

## Terminal

- Abas: máximo 8.
- Restauração: normalização também corta em 8.
- Pane status: removido quando aba é fechada.
- Session teardown: encontrado e completo no boundary local.
- Scrollback: 8000 por terminal.
- Abas ocultas já inicializadas permanecem conectadas até close.

## Files

- Favoritos/Fixados: máximo 100; stale possível.
- Recentes: máximo 30; stale possível.
- Índice de arquivos: máximo 800.
- Não foi encontrado crescimento ilimitado de localStorage nessas três estruturas.

## Clipboard

- Metadata: máximo 30.
- Payload: máximo 5 MiB por item válido.
- Overflow tenta GC físico; falha silenciosa pode deixar payload órfão.

## Janelas

O store reflete snapshots do kernel e substitui/remapeia arrays; não mantém histórico de janelas fechadas. Na superfície revisada não foi encontrado cache crescente de janelas. O teardown dos componentes desmontados continua sendo o principal mecanismo de liberação.

---

# Conclusão

**Nenhum defeito crítico encontrado em auditoria de sessão longa.**

Foram encontrados **2 defeitos/limitações de severidade alta** que impedem declarar a superfície completamente hardened para stress extremo:

1. o 101º Workspace pode tornar um Workspace físico órfão do índice;
2. centenas de Notes podem produzir consumo de memória/I/O sem teto agregado porque todo conteúdo é carregado integralmente.

Não foi confirmado leak inevitável de listener, timer, observer ou WebSocket após fechamento correto de seus componentes. Terminal, clipboard, favoritos, recentes e índices possuem limites explícitos, embora existam riscos de recursos vivos bounded e referências/payloads stale.

**Nenhuma correção foi aplicada nesta auditoria. Nenhuma funcionalidade foi adicionada.**
