# CloudOS Files real e transacional

Status: experimental. Branch isolada: `feature/cloudos-files-real-transactional`.
Base oficial usada para criação da branch: `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`.

## Objetivo

Evoluir o aplicativo existente **CloudOS Files** para três origens explícitas e isoladas:

1. `opfs` — armazenamento privado do origin já existente no CloudOS.
2. `windows` — pasta real escolhida explicitamente pelo usuário via File System Access API.
3. `wsl` — `$HOME` Linux real através do CloudOS Core v2 autenticado e protegido.

Nenhum novo aplicativo Files paralelo é criado.

## Referências pesquisadas antes da implementação

- **File Browser (`filebrowser/filebrowser`) — Apache-2.0**: referência de produto para servir somente árvores explicitamente concedidas e manter um gerenciador de arquivos web com operações básicas. Nenhum código foi copiado.
- **opfs-worker (`kachurun/opfs-worker`) — MIT**: referência para serialização de operações sobre o mesmo caminho, workers e operações de OPFS. Nenhum código foi copiado e nenhuma dependência foi adicionada.
- **File System Access API / OPFS**: referência normativa para grants explícitos de diretório e armazenamento privado do origin.
- **Linux `openat2` / resolução beneath/no-symlink**: referência de segurança. A implementação atual usa primitivas `*at` do Go/syscall e `O_NOFOLLOW` em cada componente relativo ao descritor da raiz autorizada. Uma migração futura para `openat2(RESOLVE_BENEATH|RESOLVE_NO_SYMLINKS|RESOLVE_NO_MAGICLINKS)` pode endurecer ainda mais kernels compatíveis.

## Fronteira de autorização

A API real WSL exige simultaneamente:

- JWT CloudOS válido;
- header `X-CloudOS-File-Actor: user-ui`;
- confirmação explícita (`confirmed: true`) para mutações.

O valor `agent` não é aceito nesta etapa. O runtime futuro de agentes deverá receber uma capability própria, limitada por origem, raiz, operações permitidas e expiração. Não existirá fallback de agente para o grant da UI.

## Windows

A origem Windows só é montada depois de `showDirectoryPicker({ mode: 'readwrite' })` em resposta a uma ação do usuário.

O `FileSystemDirectoryHandle`:

- fica somente em memória;
- não é salvo em `localStorage`, IndexedDB ou banco;
- é descartado ao desconectar ou recarregar o aplicativo;
- nunca é convertido em um caminho absoluto enviado ao backend.

A navegação é feita handle por handle usando segmentos normalizados. A lixeira transacional usa `.cloudos-trash` dentro da raiz concedida.

## Linux / WSL

A origem Linux usa o mesmo protocolo v2 e o mesmo `SecureFrameCodec` já aprovado pelo Terminal. Não há uma segunda implementação de AES-GCM.

A raiz é o `$HOME` do usuário do `cloudos-core`. O cliente envia somente arrays de segmentos relativos. O core:

- rejeita `.`, `..`, `/`, `\\`, NUL e nomes excessivos;
- abre a raiz uma única vez por manager;
- resolve cada diretório com `Openat` + `O_NOFOLLOW`;
- não segue symlinks;
- preserva `mode` POSIX ao copiar arquivos e diretórios;
- expõe UID/GID/modo para a UI;
- mantém `.cloudos-trash` fora do namespace navegável normal.

## Transações, progresso e cancelamento

`operationManager` agora suporta, além de processos filhos, operações JavaScript gerenciadas por `AbortController` e journal persistente.

A cópia WSL:

1. faz preflight e contabiliza árvore/bytes;
2. copia em blocos de 256 KiB;
3. atualiza progresso no journal;
4. verifica o destino;
5. se falhar ou for cancelada, move o destino parcial para a lixeira interna e o remove.

Movimentos dentro do WSL usam `Renameat` e são atômicos quando permanecem no mesmo filesystem.

No Windows, a cópia usa streams do File System Access API, permite `AbortSignal` e remove o destino parcial em caso de falha/cancelamento.

## Preview

O preview continua usando a política existente do CloudOS:

- limite por tipo/tamanho antes da leitura completa;
- SVG como texto em vez de execução direta;
- PDF em `iframe sandbox=""`;
- URLs de objeto revogadas;
- SHA-256 somente até o limite configurado;
- symlink apenas como metadado, nunca seguido.

## OPFS

O OPFS existente permanece a origem padrão ao abrir o app. Nenhuma origem real é enumerada no boot do Files.

A primeira etapa mantém as operações OPFS já existentes e isola transferências entre providers. Transferência `Windows ↔ WSL ↔ OPFS` permanece fail-closed até existir um gate transacional cross-provider com streaming, verificação e rollback; a UI não faz cópia silenciosa via memória como atalho.

## Não alterado

Esta frente não deve modificar:

- Browser;
- System Center / Task Manager;
- banco;
- `backend/src/terminal/wslCoreAdapter.js`;
- protocolo/crypto do WSL Core;
- configuração, instalação, importação, atualização ou encerramento global do WSL.

## Gate de promoção

Nenhuma promoção é permitida apenas com CI. Antes disso é necessário validar fisicamente:

- seleção real de pasta Windows e perda do grant após reload;
- criação/edição/rename/copy/move/trash/restore no Windows;
- traversal e symlink escape recusados;
- WSL Home real com permissões preservadas;
- cancelamento de cópia grande com ausência de destino parcial;
- preview limitado;
- fechamento do Files cancela operação real ativa;
- zero acesso iniciado por ator `agent`;
- OPFS original preservado.
