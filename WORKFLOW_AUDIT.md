# WORKFLOW AUDIT — CloudOS Batch 3.5

Base do Batch 3.5: `3d8a80dda0193c3a02182c846ef49e4fcdc00a67`

Base RC congelada preservada pelo gate de escopo: `be36ba9d01f207f56b03c9f5e824e500b83b8e22`

Objetivo: eliminar atrito real de uso entre Workspace, Notes, Files, Viewer, Downloads, WebOnly e gerenciamento de janelas sem alterar Browser nativo, WSL Core v2, Productization, Installer, Update, Rollback, Backup/Restore, Supply Chain, System Center ou CI principal.

## Workspace real

O Workspace continua sem banco real. O índice local mantém apenas metadata e cada raiz conserva `workspace.json`.

Batch 3.5 acrescenta:

- renomear Workspace;
- arquivar e reativar Workspace sem apagar arquivos;
- duplicar Workspace na mesma origem;
- pesquisa por nome, descrição, cliente, tags, tipo, status e provider;
- `cliente`;
- `tags`;
- `status` (`active` ou `archived`);
- `ultimaAtividade` separada de `ultimoAcesso`;
- tipo continua explícito.

### Renomear

Renomear é **metadata-only**. O nome no índice e no `workspace.json` muda, mas a raiz física `Workspaces/<slug-id>` permanece estável. Isso evita recriar ou mover a árvore inteira só para alterar o nome visível.

### Arquivar

Arquivar não remove nem move a raiz. Um Workspace arquivado deixa de ser considerado Workspace ativo e fica somente leitura nas superfícies de Notes/Evidence do hub até ser reativado. Não existe exclusão disfarçada de arquivamento.

### Duplicar

A duplicação usa o mesmo provider e as primitivas de arquivo já existentes. Não cria bridge nova.

Limites explícitos:

- até 2.000 entradas por duplicação;
- até 1 GiB agregado;
- até 256 MiB por arquivo;
- symlink encerra a duplicação em fail-closed;
- falha tenta remover a cópia parcial do índice e enviar a raiz parcial à lixeira gerenciada do mesmo provider;
- a origem nunca é alterada.

## Notes

A pesquisa do Workspace compara **título e conteúdo carregado**, não apenas o título.

O índice global usado pelo App Launcher é simples, local e limitado:

- até 200 notas indexadas;
- até 8.192 caracteres de conteúdo por nota no índice global;
- cada nota continua limitada a 2 MiB para leitura/edição rápida;
- sem embeddings;
- sem IA;
- sem banco novo.

Arquivos `txt`, `md`, `json` e `log` podem ser abertos diretamente do Files no Notes. O arquivo permanece no provider e caminho original; o Notes não copia nem executa o conteúdo.

Scripts e executáveis não entram nessa allowlist.

## Abertura de arquivos

Política de abertura do Batch 3.5:

| Tipo | Duplo clique |
|---|---|
| diretório regular | navega na pasta existente |
| `txt`, `md`, `json`, `log` | Notes |
| `png`, `jpg`, `jpeg`, `webp` | Viewer existente |
| `pdf` | Viewer PDF sandboxed existente |
| desconhecido / script / executável | informações/preview fail-closed |
| symlink | somente informação; nunca seguido |

O roteamento de texto é feito por uma camada fina de UX sobre o Files já existente. O provider transacional, o backend e o WSL Core não foram reescritos.

## Viewer de imagem

O Viewer de imagem existente ganhou somente controles de visualização:

- zoom mínimo: 25%;
- zoom máximo: 400%;
- passo: 25%;
- `+` / `=` aumenta;
- `-` diminui;
- `0` retorna ao Fit;
- Wheel altera o zoom dentro do Viewer;
- arrastar faz pan quando o modo manual está ativo;
- `Fit` encaixa a imagem;
- `1:1` usa tamanho original.

Não existe crop, desenho, filtro, gravação ou editor de imagem novo.

PDF continua em iframe sandboxed e não recebe privilégio adicional.

## Downloads

Quando não existe preferência salva, a UX de Downloads resolve o destino como:

1. Workspace ativo `/Downloads`, se houver Workspace ativo;
2. OPFS, caso contrário.

O usuário ainda pode escolher explicitamente:

- Workspace atual;
- OPFS;
- Windows grant;
- Linux Home.

A tela mostra o destino atual em texto antes das opções.

**Limitação preservada:** o Browser nativo continua congelado. Batch 3.5 não intercepta o callback de download, não redireciona o processo nativo e não declara que a preferência já controla o destino físico do Browser.

## Files — uma superfície, três origens

CloudOS Files continua sendo um único aplicativo para OPFS, Windows grant e Linux Home.

O Batch 3.5 reforça o contexto com uma faixa de ação contextual que mostra a origem canônica:

- `OPFS`;
- `Windows`;
- `Linux`.

O breadcrumb e o provider existente continuam sendo a fonte do caminho. A faixa contextual acrescenta ações rápidas sem criar outro gerenciador de arquivos:

- Abrir no Terminal;
- Abrir em Notes;
- Adicionar à Evidence.

`Abrir no Terminal` continua disponível literalmente apenas em Linux Home porque OPFS não tem cwd de sistema operacional e File System Access não expõe um caminho físico confiável do grant Windows.

`Adicionar à Evidence`:

- exige Workspace ativo;
- exige confirmação explícita;
- aceita arquivo regular;
- rejeita symlink;
- preserva o original;
- não sobrescreve nome já existente;
- mantém limite de 256 MiB por arquivo.

## Lixeira por provider

Não existe uma afirmação falsa de “Lixeira do sistema”. O comportamento mostrado ao usuário é:

### OPFS

Lixeira transacional privada do CloudOS. Restore é suportado pelo provider OPFS.

### Windows grant

Lixeira gerenciada pelo CloudOS **dentro da pasta explicitamente autorizada**, usando `.cloudos-trash` e metadata própria. Não é a Lixeira do Windows. Restore depende dessa metadata do CloudOS.

### Linux Home

Lixeira gerenciada pela integração Files/WSL existente. Restore só aparece quando o provider fornece o identificador de lixeira necessário.

Symlinks continuam fora das operações destrutivas gerenciadas.

## WebOnly UX

Nenhum código do Browser nativo foi alterado.

Quando o Native Host não está disponível e a pesquisa tem intenção de Browser/Web/Navegador, o App Launcher apresenta:

- `Browser disponível apenas em modo Full`;
- explicação de que o Browser nativo não existe na sessão WebOnly;
- botão `Abrir navegador padrão`.

O botão usa apenas a capacidade normal do navegador de abrir uma nova guia. Não cria Browser alternativo, bridge nativa nem fallback escondido.

## Window UX

Os atalhos existentes continuam usando o Window Manager atual:

- `Alt+Shift+Esquerda`;
- `Alt+Shift+Direita`;
- `Alt+Shift+Cima`;
- `Alt+Shift+Baixo`;
- `Win/Meta+Esquerda` e `Win/Meta+Direita` quando o WebView entrega os eventos.

No Batch 3.5, o gate desses atalhos roda **antes** da navegação do App Launcher. Assim, `Alt+Shift+Left/Right` pode organizar a janela mesmo quando o campo de pesquisa do Launcher está focado. Depois da ação, o foco retorna ao campo do Launcher.

O Window Manager não foi reescrito.

# Métricas de produtividade

## Cliques removidos

**Não medido.**

O teste de uso forneceu dores qualitativas, mas não forneceu uma gravação/baseline quantitativa do número de cliques antes do Batch 3.5. Portanto nenhum número de cliques removidos é declarado.

## Passos removidos

**Não medido como número agregado.**

Há reduções estruturais verificáveis no código, mas não há baseline reproduzível para convertê-las em um total humano de passos:

- duplo clique em texto compatível encaminha diretamente ao Notes;
- busca de Notes usa conteúdo no mesmo campo de pesquisa;
- renomear Workspace não exige recriar/mover a árvore;
- arquivar não exige apagar/recriar;
- Files oferece Evidence/Notes/Terminal no contexto selecionado;
- atalhos de janela funcionam mesmo com Launcher focado;
- Browser em WebOnly apresenta uma ação útil em vez de depender de um estado vazio;
- Downloads apresenta o destino atual e resolve Workspace ativo como default lógico quando nenhuma preferência existe.

## Fluxos simplificados

O Batch 3.5 modifica objetivamente estes fluxos de UX:

1. Workspace → renomear;
2. Workspace → arquivar/reativar;
3. Workspace → duplicar;
4. Workspace → pesquisar por metadata;
5. Notes → pesquisar título + conteúdo;
6. Files → texto compatível → Notes por duplo clique;
7. Files → imagem → Viewer com zoom/pan;
8. Files → Evidence por ação contextual;
9. WebOnly → Browser indisponível → navegador padrão;
10. Launcher focado → organizar janela sem abandonar o campo de pesquisa;
11. Downloads → visualizar/selecionar destino.

Essa lista é contagem de **fluxos de código/UX alterados**, não uma alegação de “11 passos economizados”.

# Fronteiras que continuam abertas

Continuam fora do Batch 3.5 por restrição arquitetural/freeze:

- Terminal real com cwd de OPFS;
- Terminal real no caminho físico oculto por Windows File System Access;
- roteamento físico dos downloads iniciados pelo Browser nativo;
- clipboard interno do Browser nativo fora da árvore DOM do frontend;
- validação física/visual de ganho de produtividade em máquina real.

# Release Freeze

O gate de escopo continua comparando a linha de workflow com a base RC e bloqueia mudanças inesperadas/frozen, incluindo `desktop/`, `scripts/productization/`, `frontend/src/apps/Browser/` e os adaptadores/backend de WSL Core protegidos.

Batch 3.5 não promove, não publica release e não altera a linha RC.
