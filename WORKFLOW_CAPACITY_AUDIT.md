# WORKFLOW_CAPACITY_AUDIT.md

## Escopo

Branch auditada: `stabilization/cloudos-workflow-batch-4`  
HEAD de produto auditado: `7838e206a54b2c36b8aca1daa7dfb43e72e75a3e`

Auditoria somente. Nenhuma linha de código de produto foi alterada. Os números abaixo distinguem:

- **limite exato do código**: constante, `slice()`, guarda ou rejeição explícita;
- **pressão estimada**: volume bruto de conteúdo que o código pode carregar/manter em memória, sem afirmar overhead exato do engine JS/browser.

---

# CRÍTICO

Nenhum limite crítico adicional foi identificado apenas pela análise de capacidade. Os principais problemas de escala são classificados como ALTOS porque causam perda de referência/truncamento e pressão severa de memória, mas não demonstram corrupção inevitável imediata em todos os usos normais abaixo dos hard caps.

---

# ALTO

## A-01 — Workspaces acima de 100 sofrem truncamento silencioso do índice

**Componente:** Workspace registry

**Limite encontrado:** `MAX_WORKSPACES = 100`.

**Evidência:**

- `persistedWorkspaces()` para ao atingir 100;
- `saveWorkspaceList()` faz `items.slice(0, MAX_WORKSPACES)`;
- `createWorkspace()` monta `[workspace, ...persistedWorkspaces()]` e faz novamente `.slice(0, MAX_WORKSPACES)`.

**Consequência:**

- 10 Workspaces: sem truncamento por capacidade.
- 50 Workspaces: sem truncamento por capacidade.
- 100 Workspaces: ocupa o limite inteiro.
- 101º Workspace: o registro mais antigo é descartado do índice local; a árvore física criada no provider não é removida automaticamente.
- 200 Workspaces criados ao longo do tempo: somente os 100 mais recentes permanecem indexados; até ~100 árvores anteriores podem ficar fisicamente presentes sem referência normal na UI.
- 500 Workspaces: somente 100 indexados; até ~400 podem ficar fora do índice.
- 1000 Workspaces: somente 100 indexados; até ~900 podem ficar fora do índice.

O descarte não é uma rejeição explícita de capacidade: é truncamento por `slice()`. Isso é mais perigoso do que um erro "limite atingido" porque o usuário pode continuar criando Workspaces sem perceber que os mais antigos desapareceram da lista.

---

## A-02 — Notes carrega conteúdo integral de todas as notas do Workspace em memória

**Componente:** Workspace Notes

**Limite encontrado:** `MAX_NOTE_BYTES = 2 MiB` por nota, porém não há hard cap de quantidade carregada por Workspace em `listWorkspaceNotes()`.

**Evidência:**

Para cada `.md` válido, `listWorkspaceNotes()` executa `readFile(...)`, depois `file.text()` e armazena o conteúdo completo em `WorkflowNote.content`. A tela mantém `notes` em estado React. Pesquisa usa `filteredNotes` e percorre `note.content`.

**Consequência — volume bruto de texto potencialmente residente por conjunto carregado:**

| Notas | 10 KB | 100 KB | 500 KB | 1 MiB | 2 MiB |
|---:|---:|---:|---:|---:|---:|
| 100 | ~0.98 MiB | ~9.77 MiB | ~48.83 MiB | 100 MiB | 200 MiB |
| 500 | ~4.88 MiB | ~48.83 MiB | ~244.14 MiB | 500 MiB | 1000 MiB |
| 1000 | ~9.77 MiB | ~97.66 MiB | ~488.28 MiB | 1000 MiB | 2000 MiB |
| 5000 | ~48.83 MiB | ~488.28 MiB | ~2441.41 MiB | 5000 MiB | 10000 MiB |

Esses números são apenas payload bruto. Strings JS, arrays, objetos, versões temporárias durante `file.text()`, filtragem e renderização podem elevar o heap real acima disso.

**Leitura:** custo O(N) em número de notas e O(total bytes) em I/O/text decoding.

**Indexação:** índice persistido é limitado a 200 entradas e 8192 caracteres de `searchText` por nota. Portanto, com 500/1000/5000 notas, apenas 200 permanecem no índice global após ordenação/truncamento.

**Pesquisa na tela:** busca percorre o array `notes` completo carregado e faz comparações sobre título + conteúdo. O número de hits visíveis é limitado a 100, mas o scan do conteúdo ocorre antes desse limite impedir custo sobre todas as notas candidatas.

**Renderização:** a lista/estado mantém objetos de todas as notas carregadas. Mesmo que só parte dos hits seja renderizada, o dataset completo permanece residente.

---

# MÉDIO

## M-01 — Índice global de Notes trunca em 200 entradas

**Componente:** Notes index

**Limite encontrado:** `MAX_NOTE_INDEX_ENTRIES = 200`.

**Evidência:** `indexNotes()` ordena e faz `.slice(0, MAX_NOTE_INDEX_ENTRIES)`; `listNoteIndex()` também corta em 200.

**Consequência:**

- 100 notas: todas podem ser indexadas.
- 500 notas: no máximo 200 indexadas; ~300 deixam de ser encontráveis via índice global.
- 1000 notas: no máximo 200 indexadas; ~800 truncadas.
- 5000 notas: no máximo 200 indexadas; ~4800 truncadas.

O conteúdo físico continua existindo; o impacto é perda de cobertura de busca/launcher baseada no índice.

---

## M-02 — Índice global de Files trunca em 800 entradas

**Componente:** Files index

**Limite encontrado:** `MAX_FILE_INDEX = 800`; cada chamada de `indexFiles()` ainda limita `entries.slice(0, 300)` para o diretório atual.

**Evidência:** `indexFiles()` combina `incoming` + `retained` e aplica `.slice(0, MAX_FILE_INDEX)`.

**Consequência:** após uso prolongado em muitas pastas/providers, apenas 800 referências permanecem. Entradas antigas desaparecem do índice, mesmo que os arquivos físicos continuem válidos. Em diretórios com mais de 300 entradas, somente as 300 primeiras consideradas pela lista entram naquele update de índice.

---

## M-03 — Favoritos/Fixados são bounded, mas stale até o limite

**Componente:** `workflowFileMarks.ts`

**Limite encontrado:** `MAX_FILE_MARKS = 100` para o conjunto persistido.

**Evidência:** leitura e escrita fazem `.slice(0, MAX_FILE_MARKS)`.

**Consequência:** o storage não cresce indefinidamente. Ao ultrapassar 100 marks ativos, os mais antigos deixam de ser mantidos. Não existe reconciliação automática com rename/move/delete; portanto, parte desses 100 pode ser referência stale e ocupar capacidade útil.

---

## M-04 — Recentes são bounded em 30, com descarte FIFO por recência

**Componente:** `workflowRecentFiles.ts`

**Limite encontrado:** `MAX_RECENT_FILES = 30`.

**Evidência:** `recordRecentFile()` escreve `[novo, ...anteriores].slice(0, 30)`.

**Consequência:** não há crescimento ilimitado em `localStorage`; ao abrir o 31º arquivo distinto, o menos recente cai da lista. Referências não são reconciliadas após rename/move/delete, então slots podem apontar para arquivos inexistentes até serem empurrados para fora ou limpos manualmente.

---

## M-05 — Terminal tem hard cap de 8 abas; pedidos acima disso não escalam

**Componente:** Terminal workspace

**Limite encontrado:** `MAX_TERMINAL_TABS = 8`.

**Evidência:** `normalizeTerminalWorkspace()` para quando `tabs.length >= MAX_TERMINAL_TABS`; `addTerminalTab()` retorna o estado atual quando o limite é atingido.

**Consequência:**

- 5 abas: permitido.
- 10 abas: apenas 8 podem existir no workspace normalizado.
- 20 abas: truncado/impedido em 8.
- 50 abas: truncado/impedido em 8.

Persistência serializa apenas metadata das abas (`id`, `profile`, `distribution`, `title`), não o buffer do terminal. Portanto o `localStorage` do Terminal é pequeno e bounded.

Cada `TerminalSession` configura `scrollback: 8000`. Como até 8 sessões podem permanecer montadas, o custo de histórico é bounded por 8 buffers x até 8000 linhas, mais estruturas internas do xterm e do transporte. O código não define um limite em bytes por linha, então não é possível obter heap máximo exato apenas pelas constantes.

---

## M-06 — Export ZIP é limitado a 64 MiB/2000 entradas, mas constrói o pacote inteiro em memória

**Componente:** Workspace ZIP export

**Limites encontrados:**

- `MAX_WORKSPACE_EXPORT_ENTRIES = 2000`;
- `MAX_WORKSPACE_EXPORT_BYTES = 64 MiB`;
- `MAX_WORKSPACE_EXPORT_FILE_BYTES = 16 MiB`.

**Evidência:** `collectFolder()` lê cada arquivo, converte para `ArrayBuffer`/`Uint8Array`, armazena em `zipEntries`; depois `createStoreZip(zipEntries)` cria um novo buffer ZIP completo; em seguida um `Blob` é criado sobre o resultado.

**Consequência:** o payload agregado é limitado a 64 MiB, mas o pico de heap pode ser substancialmente superior a 64 MiB devido a coexistência de:

1. buffers dos arquivos em `zipEntries`;
2. `ArrayBuffer`/`Uint8Array` temporários de leitura;
3. buffer final retornado por `createStoreZip`;
4. `Blob` e estruturas auxiliares.

Não existe streaming ZIP. Portanto, o gargalo é pico de memória proporcional ao tamanho total exportado. O código permite calcular o teto lógico do payload (64 MiB), mas não um teto exato de heap do navegador.

---

## M-07 — Evidence não tem cap físico por Workspace; operações auxiliares têm caps menores

**Componente:** Evidence

**Limite encontrado:** `listWorkspaceEvidence()` apenas lista o diretório Evidence; `saveWorkspaceEvidenceFile()` grava no provider sem quota própria de Evidence nesta camada. Logo não há hard cap de 100 MB/500 MB/1 GB/5 GB imposto pelo Workflow.

**Consequência por volume físico:**

- 100 MB: pode existir fisicamente se o provider/quota permitir; listar metadata ainda é possível, mas export ZIP não aceita agregar mais de 64 MiB de Notes+Evidence.
- 500 MB: armazenamento físico possível dependendo do provider; export ZIP falha antes de incluir tudo.
- 1 GB: mesma situação; operações que precisam ler/copiar conteúdo começam a depender fortemente do provider e dos caps das rotas auxiliares.
- 5 GB: não há suporte de exportação ZIP desse volume; a árvore pode existir, mas Workflow não fornece caminho de export integral dessa escala.

O ZIP não copia Evidence além de 64 MiB agregado. O export portátil JSON também usa o mesmo agregado de 64 MiB e base64, portanto expande dados e é ainda menos apropriado para grandes volumes.

---

# BAIXO

## B-01 — Clipboard é bounded em 30 itens, até 5 MiB por item

**Componente:** Workflow Clipboard

**Limites encontrados:** `MAX_CLIPBOARD_ITEMS = 30`; `MAX_CLIPBOARD_ITEM_BYTES = 5 MiB`.

**Evidência:** metadata é normalizada para no máximo 30; overflow tem payload removido.

**Consequência:** payload lógico máximo permitido pela política é ~150 MiB se os 30 itens estiverem próximos de 5 MiB cada. Na prática, duplicação, política de sensibilidade e remoção de overflow reduzem isso. Falha silenciosa em `removePayload()` pode deixar payload OPFS órfão além do conjunto indexado.

---

## B-02 — localStorage principal é bounded por item count, não cresce indefinidamente nos fluxos auditados

**Componente:** Workspace/Notes/Files/Clipboard/Terminal persistence

**Limites observados:**

- Workspaces: 100 registros;
- Note index: 200;
- File index: 800;
- File marks: 100;
- Recent files: 30;
- Clipboard metadata: 30;
- Terminal tabs: 8.

**Consequência:** não foi encontrado crescimento monotônico ilimitado dessas coleções em `localStorage`. O problema de escala é truncamento/staleness, não crescimento infinito.

---

# MATRIZ DE CAPACIDADE

## Workspaces

| Quantidade | Estado esperado pelo código |
|---:|---|
| 10 | Dentro do limite; sem truncamento por capacidade |
| 50 | Dentro do limite |
| 100 | Limite máximo indexável atingido |
| 200 | Apenas 100 indexados; ~100 antigos podem ficar órfãos |
| 500 | Apenas 100 indexados; ~400 fora do índice |
| 1000 | Apenas 100 indexados; ~900 fora do índice |

**Primeiro ponto em que começa a quebrar semanticamente:** 101º Workspace.

## Notes

| Quantidade | Comportamento estrutural |
|---:|---|
| 100 | Todas podem ser carregadas; índice global comporta até 200 |
| 500 | Todas podem ser carregadas em RAM, mas só 200 permanecem no índice global |
| 1000 | Todas podem ser carregadas; índice continua 200 |
| 5000 | Sem hard cap de load; pressão extrema de RAM/I/O; índice continua 200 |

**Primeiro ponto de degradação:** depende do tamanho médio. Ex.: 500 notas de 500 KB ≈ 244 MiB de payload bruto carregado; 1000 x 1 MiB ≈ 1 GiB bruto.

## Evidence

| Volume | Estado pelo código |
|---:|---|
| 100 MB | Pode existir no provider; ZIP completo não cabe no limite agregado de 64 MiB |
| 500 MB | Pode existir; export Workflow integral não suporta esse volume |
| 1 GB | Pode existir conforme provider; export integral bloqueado pelos caps |
| 5 GB | Storage pode suportar dependendo do provider, mas Workflow export/cópia não foi projetado para esse volume |

## Terminal

| Abas solicitadas | Abas efetivas máximas |
|---:|---:|
| 5 | 5 |
| 10 | 8 |
| 20 | 8 |
| 50 | 8 |

Cada aba usa xterm com `scrollback: 8000`; máximo de 8 sessões montadas.

## Files metadata

| Estrutura | Limite |
|---|---:|
| Recentes | 30 |
| Favoritos/Fixados combinados | 100 |
| Índice global Files | 800 |
| Entradas ingeridas por diretório em `indexFiles()` | 300 |

---

# RESULTADO FINAL

## CAPACIDADE ATUAL

O Workflow atual é claramente dimensionado para **uso pessoal/projeto pequeno a médio**, não para catálogo massivo. Os hard caps mais importantes são 100 Workspaces, 8 abas Terminal, 200 notas no índice global, 800 arquivos no índice, 100 marks e 30 recentes/clipboard.

O storage físico de Notes/Evidence pode superar alguns desses índices, mas a UI/persistência começa a truncar referências muito antes do provider necessariamente ficar cheio.

## PRINCIPAL GARGALO

**Notes carregando conteúdo integral de todas as notas do Workspace.** Não existe paginação/lazy loading do corpo. A quantidade de notas não tem hard cap de load e o custo cresce com o total de bytes, não apenas com a quantidade.

## MAIOR RISCO DE ESCALA

**Truncamento silencioso de Workspaces acima de 100.** O 101º não é rejeitado; o índice é cortado. Isso pode deixar árvores físicas antigas sem referência normal na UI.

## O QUE AGUENTA BEM

- Recentes, favoritos/fixados, clipboard metadata e Terminal workspace são bounded e não crescem indefinidamente em `localStorage`.
- Terminal impede explosão de abas com hard cap de 8.
- ZIP/export possui caps de entradas e bytes e rejeita volumes acima do limite em vez de continuar sem controle.
- Note index e File index também são bounded, evitando crescimento ilimitado de persistence.

## O QUE PRECISA SER REFEITO NO FUTURO

Sem propor implementação nesta auditoria, as áreas cuja estratégia atual não escala para volumes grandes são:

1. **registro de Workspaces** baseado em lista truncada de 100;
2. **Notes** com leitura eager do conteúdo integral;
3. **índices globais** de Notes/Files com truncamento simples em 200/800;
4. **Evidence/export** sem streaming para conjuntos grandes;
5. **ZIP** inteiramente materializado em heap.

Estas são limitações arquiteturais de capacidade observadas no código atual, não funcionalidades novas propostas.

---

**Nenhuma linha de código de produto foi alterada.**
