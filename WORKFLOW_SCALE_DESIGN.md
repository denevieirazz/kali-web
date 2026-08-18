# WORKFLOW_SCALE_DESIGN.md

## CloudOS Workflow — Projeto Técnico de Escala

**Branch:** `stabilization/cloudos-workflow-batch-4`  
**HEAD de produto analisado:** `7838e206a54b2c36b8aca1daa7dfb43e72e75a3e`  
**Escopo:** projeto técnico apenas. Nenhuma implementação de produto faz parte deste documento.

---

# 1. WORKSPACE SCALE

## PROBLEMA

O catálogo atual de Workspaces possui um limite estrutural fixo de 100 registros. Criar/importar/duplicar além desse ponto não gera erro de capacidade: os registros mais antigos são truncados silenciosamente do índice local, embora as árvores físicas permaneçam no provider.

## CAUSA

A implementação atual usa uma única chave de `localStorage` (`cloudos.workflow.workspaces.v3`) contendo um array completo de `WorkspaceRecord`.

O limite aparece em três pontos:

- `const MAX_WORKSPACES = 100`;
- `persistedWorkspaces()` interrompe leitura após 100 entradas válidas;
- `saveWorkspaceList()` grava `items.slice(0, MAX_WORKSPACES)`;
- `createWorkspace()` também constrói `[workspace, ...existing].slice(0, MAX_WORKSPACES)`.

O limite parece ter sido criado como proteção simples contra crescimento ilimitado de `localStorage` e custo de serialização/sort global. Ele funciona como hard cap de memória/persistência, mas não é adequado como regra de integridade porque o descarte é silencioso.

## LIMITE ATUAL

- 100 Workspaces: capacidade integral do índice atual.
- 500 Workspaces: 400 registros físicos podem existir sem catálogo.
- 1000 Workspaces: até 900 podem ficar fora do índice.
- 5000 Workspaces: até 4900 podem ficar fora do índice.

A UI e todas as operações que dependem de `listWorkspaces()`, `getWorkspace()` ou `getActiveWorkspace()` enxergam apenas o conjunto indexado.

## IMPACTO

- perda de referência lógica sem perda imediata dos dados físicos;
- Workspace físico órfão;
- `getWorkspace(id)` passa a falhar para registros truncados;
- download destination, Evidence, Notes, export e navegação podem tratar o Workspace como inexistente;
- custo de `JSON.parse`, normalize, sort e rewrite cresce linearmente até o limite;
- simplesmente aumentar `MAX_WORKSPACES` desloca o problema, mas mantém leitura/escrita global O(N).

## OPÇÃO A — Aumentar o limite e rejeitar explicitamente ao atingir o teto

### Desenho

Manter o array único em `localStorage`, remover o truncamento silencioso e substituir por um limite explícito maior, por exemplo 1000 ou 5000.

Ao atingir o teto:

- criação/import/duplicate falham antes de criar a árvore física;
- nenhum registro existente é descartado;
- mensagem de capacidade é retornada ao usuário.

### Performance

- 100: praticamente igual ao atual;
- 500: aceitável para metadata pequena;
- 1000: ainda viável, porém toda mutação reserializa o array completo;
- 5000: parse/sort/stringify global começa a se tornar custo recorrente e desnecessário.

### Complexidade

Baixa.

### Risco

Baixo tecnicamente, mas mantém teto artificial e O(N) para toda operação.

### Compatibilidade

Máxima. Mesmo schema e mesma chave.

### Quando usar

Boa correção imediata de integridade, não solução definitiva de escala.

---

## OPÇÃO B — Catálogo paginado/segmentado em localStorage

### Desenho

Manter o modelo `WorkspaceRecord`, porém dividir catálogo em páginas/buckets:

- `cloudos.workflow.workspaces.v4.meta`
- `cloudos.workflow.workspaces.v4.page.0001`
- `...page.0002`

Cada página conteria, por exemplo, 100 registros.

Um pequeno manifesto global armazenaria:

- schema;
- quantidade total;
- páginas existentes;
- activeWorkspaceId;
- version/generation.

Busca/listagem poderia carregar páginas conforme necessário.

### Performance

- 100: semelhante ao atual;
- 500: 5 páginas pequenas;
- 1000: 10 páginas;
- 5000: 50 páginas, sem necessidade de reserializar tudo a cada mutação.

Busca global sem índice ainda seria O(N), mas escrita/atualização de um Workspace seria O(page size).

### Complexidade

Média.

### Risco

Médio: exige migração v3 → v4, atomicidade de páginas/manifest e recuperação de geração incompleta.

### Compatibilidade

Boa se houver migração one-way idempotente e leitura temporária de v3 durante upgrade.

### Vantagem

Resolve truncamento e reduz write amplification sem introduzir banco de dados.

---

## OPÇÃO C — Catálogo persistente em IndexedDB com `workspace.json` como manifesto físico

### Desenho

Usar IndexedDB como catálogo de metadata/index local, mantendo cada `workspace.json` físico exatamente como hoje.

Object store conceitual:

`workspaces`
- key: `id`
- indexes: `status`, `lastActivityAt`, `provider`, `name/client/tags normalized`

Outros stores poderiam futuramente armazenar índices de Notes/Files, sem obrigar essa migração já na primeira etapa.

`workspace.json` continua sendo a cópia portátil/reconciliável no provider; IndexedDB é catálogo local de acesso rápido.

### Performance

- 100: trivial;
- 500: trivial;
- 1000: adequado;
- 5000: adequado com cursor/index e paginação;
- listagens podem retornar 50/100 itens por página;
- update de um Workspace deixa de reescrever 4999 registros.

### Complexidade

Média/alta.

### Risco

Médio: migração, transações, reconcile entre IndexedDB e manifests físicos e comportamento quando IndexedDB é limpo pelo navegador.

### Compatibilidade

Alta se `workspace.json` permanecer fonte física recuperável e IDs/paths/schema atuais não mudarem.

### Vantagem

É a opção que efetivamente suporta milhares de Workspaces sem transformar `localStorage` em banco.

---

## RECOMENDAÇÃO — WORKSPACE

### Fase de estabilização de escala

Primeiro remover o truncamento silencioso imediatamente, mesmo antes de qualquer reestruturação: nunca descartar Workspace existente para aceitar um novo.

### Direção recomendada

**Opção C**, com migração incremental:

1. preservar `WorkspaceRecord` atual;
2. preservar `workspace.json` atual;
3. migrar o catálogo v3 do localStorage para IndexedDB;
4. manter apenas `activeWorkspaceId`, schema/version e flags pequenas em localStorage, se desejado;
5. listar Workspaces paginadamente;
6. adicionar uma rotina explícita de reconcile que possa reconstruir catálogo a partir dos manifests físicos quando aplicável.

A Opção B é um bom estágio intermediário se IndexedDB for considerado mudança grande demais para a fase seguinte. A Opção A é adequada somente como correção curta para eliminar perda de referência.

---

# 2. NOTES SCALE

## PROBLEMA

`listWorkspaceNotes()` atualmente lê o conteúdo integral de todas as notas Markdown do Workspace. A UI guarda `WorkflowNote[]` com `content` completo, e pesquisa trabalha sobre essas strings residentes.

Isso escala pelo total de bytes, não apenas pelo número de notas.

## CAUSA

A estrutura `WorkflowNote` mistura duas responsabilidades:

- metadata: fileName/title/modified/workspaceId;
- payload: `content` integral.

`listWorkspaceNotes()` faz `readFile()` + `file.text()` para cada `.md` até 2 MiB.

O índice global é separado, porém também limitado a 200 entradas e é alimentado a partir do conteúdo já carregado.

## LIMITE ATUAL

Hard caps:

- 2 MiB por nota;
- índice global: 200 notas;
- `searchText`: primeiros 8192 caracteres por nota indexada;
- nenhuma quantidade máxima de notas físicas no diretório `Notes`;
- nenhuma paginação/lazy load do conteúdo.

Cenários de payload bruto máximo teórico se todas as notas forem grandes:

- 500 × 2 MiB ≈ 1 GiB;
- 1000 × 2 MiB ≈ 2 GiB;
- 5000 × 2 MiB ≈ 10 GiB.

Esses valores são payload lógico; memória JS pode ser maior devido a strings, objetos e cópias temporárias.

## IMPACTO

- abertura do Workspace faz N leituras físicas;
- React mantém N conteúdos completos;
- pesquisa filtra e varre strings completas;
- atualização do contexto pode repetir I/O;
- garbage collector recebe grandes volumes de strings;
- 500/1000/5000 notas grandes deixam de ser um cenário razoável no browser.

---

## OPÇÃO A — Paginação de notas, ainda carregando conteúdo por página

### Desenho

Separar listagem em páginas, por exemplo 50 notas:

- listar metadata;
- carregar conteúdo das 50 notas da página;
- descartar conteúdo de páginas antigas.

### Performance

Muito melhor que o modelo atual para 500–5000 notas, mas cada mudança de página ainda pode gerar até 50 leituras completas.

### Complexidade

Baixa/média.

### Risco

Baixo.

### Compatibilidade

Alta; armazenamento físico não muda.

### Limitação

Pesquisa global ainda exige índice suficiente ou leitura de todas as páginas.

---

## OPÇÃO B — Lazy loading por nota + catálogo apenas de metadata

### Desenho

Criar dois tipos lógicos:

`WorkflowNoteMeta`
- workspaceId
- fileName
- title
- modified
- size

`WorkflowNoteDocument`
- metadata
- content

`listWorkspaceNotes()` deixa de ler conteúdo e vira `listWorkspaceNoteMetadata()`.

Conteúdo é carregado somente quando:

- nota se torna ativa;
- preview exige conteúdo;
- usuário abre resultado de pesquisa que precisa do documento.

Manter cache LRU pequeno, por exemplo 5–20 notas, medido por bytes e não apenas por contagem.

### Performance

- 500 notas: listagem barata; 1 documento carregado;
- 1000: idem;
- 5000: listagem maior, mas memória de conteúdo fica bounded pelo cache;
- troca entre notas recentes é rápida pelo LRU.

### Complexidade

Média.

### Risco

Médio: lifecycle de dirty note/cache e invalidação por modified time precisam ser corretos.

### Compatibilidade

Muito alta. Nenhum arquivo precisa mudar de formato.

### Vantagem

Ataca diretamente o principal gargalo de heap.

---

## OPÇÃO C — Lazy loading + índice incremental persistente de pesquisa

### Desenho

Combinar Opção B com índice desacoplado do conteúdo carregado.

Cada nota teria entrada persistente:

- workspaceId;
- fileName;
- modified;
- size;
- title;
- excerpt/searchText bounded;
- optional content hash/version.

O indexador lê uma nota apenas quando:

- é nova;
- `modified` mudou;
- índice está ausente/corrompido.

Depois, pesquisa normal usa o índice. Busca completa pode oferecer uma segunda etapa que lê apenas os candidatos, não todas as notas.

O índice deve deixar de ser truncado globalmente em 200 para milhares de notas. IndexedDB é mais adequado que um JSON monolítico em localStorage.

### Performance

- abertura: metadata + índice, sem conteúdo completo;
- pesquisa: O(N) sobre textos pequenos indexados ou via índice por token;
- edição: somente a nota ativa;
- 5000 notas tornam-se viáveis se excerpts forem bounded.

### Complexidade

Média/alta.

### Risco

Médio: index stale precisa de generation/modified/hash e rebuild determinístico.

### Compatibilidade

Alta. Markdown físico permanece intacto.

---

## RECOMENDAÇÃO — NOTES

A direção correta é **Opção C implementada em duas etapas**:

1. **primeiro Lazy Loading (Opção B)** — separar metadata de conteúdo e manter cache LRU bounded por bytes;
2. **depois índice incremental persistente** — remover o limite global de 200 sem voltar a carregar todas as notas.

Paginação de UI pode ser adicionada sobre esse modelo, mas não deve ser a solução de memória: paginação sozinha ainda carrega dezenas de documentos que não precisam estar na heap.

Objetivo de memória recomendado para desenho futuro:

- catálogo de milhares de notas: apenas metadata;
- conteúdo residente: nota ativa + pequeno LRU;
- índice de busca: excerpts/tokens bounded;
- dirty content: nunca eviction antes de save confirmado.

---

# 3. FILES SCALE

## PROBLEMA

O índice atual não é um catálogo completo de Files. Ele funciona como cache pequeno de contexto recente.

## CAUSA

Hard caps atuais:

- `MAX_FILE_INDEX = 800`;
- cada chamada de `indexFiles()` considera somente `entries.slice(0, 300)`;
- resultado combinado é novamente truncado para 800.

## LIMITE ATUAL

### 800 itens

É o teto global persistido.

### 2000 itens

Pelo menos 1200 não podem coexistir no índice; visitas a diretórios novos empurram entradas antigas para fora.

### 5000 itens

O índice representa apenas uma janela parcial de 800. Um único diretório com 5000 itens indexa apenas os primeiros 300 recebidos pela listagem.

## IMPACTO

- launcher/contexto não representam árvore completa;
- resultados podem desaparecer por simples navegação em outro diretório;
- ordem de truncamento não é explicitamente LRU por acesso global;
- stale references permanecem possíveis após rename/move/delete;
- aumentar 800 para 5000 mantém JSON monolítico e write amplification.

---

## OPÇÃO A — Manter Files index como cache, documentando-o como não-exaustivo

### Desenho

Preservar hard cap e aceitar que ele é apenas "recently indexed files".

### Performance

Excelente e bounded.

### Complexidade

Mínima.

### Risco

Baixo se nenhuma feature assumir cobertura completa.

### Compatibilidade

Total.

---

## OPÇÃO B — Cache LRU explícito maior com invalidação por operações

### Desenho

Manter um cache bounded, mas armazenar `lastSeenAt`/generation e atualizar referências em rename/move/delete.

### Performance

Boa até alguns milhares.

### Complexidade

Média.

### Risco

Médio por invalidação cruzada entre providers.

### Compatibilidade

Alta.

---

## OPÇÃO C — Índice persistente por provider em IndexedDB

### Desenho

Índice completo/consultável por provider/path/name com updates incrementais.

### Performance

Melhor para busca global real sobre milhares/dezenas de milhares de arquivos.

### Complexidade

Alta.

### Risco

Maior que o benefício atual se Files global search ainda não exigir cobertura completa.

### Compatibilidade

Boa se for índice derivado e reconstruível.

---

## RECOMENDAÇÃO — FILES

**Não refazer agora.**

Tratar o índice atual como cache bounded. Antes de aumentar capacidade, corrigir semanticamente referências stale e garantir que features não o tratem como fonte completa da árvore.

Quando houver requisito real de busca global em milhares de arquivos, migrar diretamente para índice derivado em IndexedDB em vez de simplesmente aumentar 800.

---

# 4. EXPORT SCALE

## PROBLEMA

O ZIP atual é criado completamente em memória.

## CAUSA

Fluxo atual:

1. `collectFolder()` lê cada arquivo;
2. `file.arrayBuffer()` cria buffer;
3. `new Uint8Array()` mantém payload em `zipEntries`;
4. todos os entries coexistem;
5. `createStoreZip(zipEntries)` cria o ZIP final;
6. `Blob` é criado sobre o resultado;
7. download usa Object URL.

Hard caps reutilizados:

- 64 MiB agregados;
- 16 MiB por arquivo;
- 2000 entries.

## LIMITE ATUAL

O limite lógico é 64 MiB de Notes + Evidence, mas o pico de heap pode superar bastante 64 MiB, porque payload de origem, arrays individuais, ZIP final e Blob podem coexistir temporariamente.

Não existe um máximo exato dedutível do código para heap real porque implementação do engine/browser e Blob podem copiar ou compartilhar buffers.

## IMPACTO

- picos de heap;
- GC durante export;
- export de 100 MB+ é rejeitado antes de ZIP;
- Evidence de 500 MB/1 GB/5 GB não pode ser exportada pelo fluxo atual.

---

## OPÇÃO A — Aumentar limites mantendo ZIP in-memory

### Performance

Ruim após algumas centenas de MiB.

### Complexidade

Baixa.

### Risco

Alto: OOM/crash de aba depende do dispositivo.

### Compatibilidade

Total.

### Avaliação

Não recomendado.

---

## OPÇÃO B — Streaming ZIP para destino gravável quando disponível

### Desenho

Preservar exatamente a estrutura ZIP atual:

- `Notes/...`
- `Evidence/...`
- `Metadata/workspace.json`
- `Metadata/export.json`

mas escrever entradas sequencialmente para um `WritableStream`/File System Access destination, sem manter todo o payload em heap.

Para ambientes sem writable streaming, manter o export atual como fallback com limite de 64 MiB.

### Performance

Memória tende a O(chunk size) + estruturas do compressor, não O(total archive).

### Complexidade

Média/alta.

### Risco

Médio: diferenças de capacidade entre browser/native host e necessidade de cancelamento/cleanup de arquivo parcial.

### Compatibilidade

Excelente no formato: o ZIP produzido pode continuar usando o mesmo schema e paths.

---

## OPÇÃO C — Export dirigido pelo provider/backend para grandes Workspaces

### Desenho

Para WSL/Host, processo nativo faz streaming do ZIP diretamente do filesystem e devolve arquivo/stream para a UI.

### Performance

Melhor para GBs.

### Complexidade

Alta e cruza fronteira de produto/host.

### Risco

Maior; amplia superfície e não é necessária para corrigir os dois gargalos prioritários.

### Compatibilidade

Formato ZIP pode continuar idêntico.

---

## RECOMENDAÇÃO — EXPORT

**Opção B no futuro**, mantendo o ZIP/schema existente e o export in-memory de 64 MiB como fallback compatível.

Não aumentar o limite atual antes de existir streaming. O limite de 64 MiB é hoje uma proteção contra pressão de heap, não apenas uma limitação arbitrária.

---

# 5. ORDEM TÉCNICA RECOMENDADA

## PRIMEIRO — Integridade do catálogo de Workspaces

O problema de Workspaces é perda de referência silenciosa. Ele deve ser resolvido antes de aumentar qualquer capacidade.

Sequência proposta:

1. proibir truncamento silencioso;
2. preservar todos os registros existentes;
3. migrar catálogo para persistência escalável;
4. adicionar paginação da listagem;
5. só então validar 500/1000/5000 registros.

## SEGUNDO — Modelo de Notes lazy

Sequência proposta:

1. separar `WorkflowNoteMeta` de conteúdo;
2. listar metadata sem `readFile()` de todas as notas;
3. carregar somente nota ativa;
4. LRU bounded por bytes;
5. índice incremental persistente;
6. busca baseada no índice;
7. opcionalmente paginação/virtualização visual.

## TERCEIRO — Files stale/index semantics

Preservar os hard caps enquanto não houver requisito de índice exaustivo. Corrigir stale references quando essa frente for aberta.

## QUARTO — Streaming export

Só após Workspaces e Notes, porque o ZIP atual já falha explicitamente em 64 MiB e, portanto, não causa o mesmo tipo de corrupção silenciosa.

---

# 6. COMPATIBILIDADE E MIGRAÇÃO

Nenhuma das recomendações exige mudar o formato físico atual dos Workspaces.

Devem permanecer compatíveis:

- IDs existentes;
- `WorkspaceRecord` semântico;
- diretórios `Workspaces/<root>`;
- `workspace.json`;
- `Notes/*.md`;
- `Evidence/*`;
- ZIP `cloudos-workspace-zip/v1`;
- import/export legado quando aplicável.

A regra central para evolução deve ser:

**persistência nova é índice/catálogo derivado; arquivos reais continuam sendo a camada recuperável.**

Isso reduz risco de migração e permite reconstrução de índices.

---

# RESULTADO FINAL

## MAIOR GARGALO DE ESCALA

**Notes em memória.** O modelo atual atrela listagem a leitura integral de conteúdo e escala pelo total de bytes do Workspace.

## WORKSPACE

O limite de 100 é uma proteção de `localStorage` implementada como truncamento. Para escala real, substituir catálogo monolítico por persistência paginável/indexada, preferencialmente IndexedDB, preservando `workspace.json` como manifesto físico.

## NOTES

Separar metadata de payload. Lazy load da nota ativa + pequeno cache LRU e índice incremental persistente permitem 500/1000/5000 notas sem manter todos os documentos na heap.

## FILES

800 itens é adequado como cache de contexto, não como índice completo. Não aumentar indiscriminadamente; futuramente, se busca global exigir cobertura total, usar índice persistente derivado.

## EXPORT

64 MiB é uma barreira de segurança de memória. Evolução correta é streaming mantendo o mesmo ZIP/schema, não simplesmente elevar o hard cap.

## O QUE DEVE SER FEITO PRIMEIRO

1. eliminar truncamento silencioso de Workspaces;
2. migrar catálogo de Workspaces para armazenamento escalável;
3. converter Notes para metadata + lazy content;
4. criar índice incremental de Notes sem teto global de 200.

## O QUE PODE ESPERAR

- índice completo de Files;
- aumento de Recentes/Favoritos/Fixados;
- streaming de ZIP para centenas de MiB/GB;
- qualquer mudança arquitetural fora do Workflow.

---

**Este documento não implementa nenhuma alteração de produto.**
