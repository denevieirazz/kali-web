# CloudOS Workflow Batch 4 Review

Branch: `feature/cloudos-workflow-batch-4`  
Base: `feature/cloudos-workflow-batch-3` (`bfe18cecc857e0fe47005b3fa2cfa905f2f5327e`)  
Status de promoção: **não promovido / não publicado**.

## Escopo congelado

O Batch 4 não altera RC, Installer, Update, Rollback, Recovery, Supply Chain, WSL Core v2 nem Browser nativo. O gate `scripts/workflow/test-batch4-scope.mjs` usa allowlist explícita de arquivos e falha se o diff contra Batch 3 sair dessa superfície.

## Problemas do Gemini resolvidos

### Excesso de janelas no Terminal

O Terminal já possuía workspace de abas no Batch 3. O Batch 4 fecha o workflow profissional ao expor os atalhos convencionais no Terminal ativo sem alterar o protocolo existente:

- `Ctrl+T`: nova aba.
- `Ctrl+W`: fecha a aba ativa.
- `Ctrl+Tab`: próxima aba.
- `Ctrl+Shift+Tab`: aba anterior.
- A última aba ativa continua persistida por `terminalWorkspaceState` no armazenamento local.
- A aba ativa continua destacada visualmente.
- O indicador visual de sessão agora mapeia corretamente os estados reais `connecting`, `connected`, `legacy-fallback`, `closing`, `failed` e `closed`.

A tradução dos atalhos acontece na camada de workflow e chama os atalhos internos já existentes do Terminal. Nenhuma mensagem, rota WebSocket, transporte ou contrato do WSL Core v2 foi alterado.

### Files não parecia um gerenciador de arquivos natural

A abertura natural por duplo clique de `txt`, `md`, `json` e `log` já existia no bridge do Batch 3 e foi mantida como contrato explícito do Batch 4. Esses arquivos abrem no editor Notes. Extensões de script ou executáveis, incluindo `sh`, `ps1`, `js` e `exe`, não entram nesse caminho automático.

O Batch 4 complementa o fluxo com:

- Recentes: preservados do Batch 3.
- Favoritos: metadata local, limitada e sem upload.
- Fixados: metadata local, limitada e sem upload.
- Atalhos de acesso rápido aparecem enquanto Files é a janela ativa.

### Workspace parecia uma pasta

Quando Workspace é a janela ativa, o Batch 4 mostra um painel de contexto de projeto com:

- Resumo do projeto atual.
- Últimas notas carregadas do diretório `Notes`.
- Últimos arquivos indexados dentro da raiz do Workspace.
- Últimas evidências do diretório `Evidence`.
- Último acesso e última atividade do Workspace.

A intenção é que abrir Workspace responda imediatamente “em que projeto estou e o que aconteceu por último”, sem exigir navegar primeiro pela árvore física.

### Evidência exigia cliques demais

`Ctrl+Shift+E` executa o fluxo rápido:

`Clipboard -> Workspace ativo -> Evidence`

A captura tenta primeiro uma imagem do clipboard e, quando isso não está disponível, usa texto. Workspace inexistente ou arquivado falha fechado. O dado é salvo pelos mesmos serviços locais de Evidence já existentes.

### Troca entre ferramentas de trabalho exigia navegação manual

Atalhos do Batch 4:

| Atalho | Ação |
| --- | --- |
| `Ctrl+Alt+W` | Fechar janela ativa não-sistema |
| `Ctrl+Alt+1` | Alternar Workspace |
| `Ctrl+Alt+2` | Alternar Notes |
| `Ctrl+Alt+3` | Alternar Terminal |
| `Ctrl+Shift+E` | Capturar clipboard para Evidence |
| `Ctrl+T` | Nova aba no Terminal ativo |
| `Ctrl+W` | Fechar aba no Terminal ativo |
| `Ctrl+Tab` | Próxima aba do Terminal |
| `Ctrl+Shift+Tab` | Aba anterior do Terminal |

`Ctrl+W` só é tratado como fechamento de aba quando o CloudOS Terminal está ativo; fechamento global usa `Ctrl+Alt+W` para evitar conflito.

### Exportação do projeto não era ZIP

O botão `Exportar` do Workspace passa a produzir um ZIP local contendo somente:

- `Notes/*`
- `Evidence/*`
- `Metadata/workspace.json`
- `Metadata/export.json`

O ZIP é montado no cliente, baixado por `Blob` e não possui chamada de cloud, upload ou API remota. O escritor ZIP não adiciona dependência externa e rejeita path traversal.

## Problemas que continuam

1. **Indicador do Terminal não é contador de output não lido.** Ele representa o estado real da sessão/transport (`connected`, `connecting`, fallback, falha etc.). Um contador preciso de bytes/output por aba exigiria instrumentar a camada de transporte; isso foi deliberadamente evitado para respeitar o freeze do WSL Core v2.
2. **ZIP é somente exportação neste Batch.** O import portátil legado continua aceitando o bundle JSON existente. Adicionar import ZIP ampliaria o escopo de transferência e não era requisito desta entrega.
3. **Últimos arquivos dependem do índice local de Files.** Arquivos que nunca foram visitados/indexados pelo Files podem não aparecer imediatamente no resumo contextual.
4. **Favoritos/Fixados são referências locais.** Se uma pasta Windows perder o grant, um item for movido externamente ou um arquivo for apagado fora do CloudOS, a referência pode apontar para um local indisponível até o usuário corrigir o acesso.
5. **Tipos binários e extensões não autorizadas não viram editor automaticamente.** O fail-closed permanece intencional.

## O que ainda obriga sair do CloudOS

- Em sessão WebOnly, navegação web que depende do Browser nativo ainda pode exigir o navegador padrão do sistema. O Browser nativo permanece congelado e não foi alterado.
- Arquivos que exigem um aplicativo externo não suportado pelo CloudOS ainda precisam ser tratados fora do ambiente.
- Recursos fora de uma pasta Windows explicitamente autorizada ou fora dos limites do provider WSL permanecem inacessíveis até o usuário conceder/selecionar uma origem suportada.
- O destino de download do workflow não intercepta fisicamente downloads do Browser nativo congelado.

## Cobertura adicionada

- CRC32 e estrutura ZIP store.
- Rejeição de path traversal no ZIP.
- Contrato de abertura automática apenas para `txt`, `md`, `json` e `log`.
- Contrato de fail-closed para scripts/executáveis.
- Persistência da última aba ativa do Terminal.
- Presença dos atalhos convencionais e de produtividade sem tocar no transporte.
- Contrato de ZIP com Notes, Evidence e Metadata e sem chamadas de upload/cloud.
- Contrato de Favoritos/Fixados locais e limitados.
- Gate de escopo comparando Batch 4 contra Batch 3.

## Limites de entrega

Nenhuma promoção, merge, publicação, alteração de RC ou alteração das branches de productization foi realizada. O CI do Batch 4 é independente e executa regressão frontend, backend, E2E, lint e build em Linux e Windows.
