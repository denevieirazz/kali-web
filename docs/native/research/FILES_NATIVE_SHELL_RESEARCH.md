# Pesquisa de referência — Arquivos nativo

Data: 2026-08-29

## Problema observado

A primeira versão nativa de `Arquivos` usava somente `BUTTON`, `EDIT` e `ListView` clássicos. Ela preservava operações básicas, mas visualmente parecia uma ferramenta Win32 antiga e reimplementava comportamentos que o Shell do Windows já fornece.

A regra deste projeto é pesquisar antes de criar um subsistema novo e reaproveitar implementações maduras quando isso não reintroduzir WebView/HTML nem quebrar o contrato do CloudOS.

## Referências pesquisadas

### Microsoft Windows Shell — `IExplorerBrowser`

Fontes oficiais:

- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexplorerbrowser
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorerbrowser-initialize
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorerbrowser-browsetoidlist
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexplorerbrowserevents
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifolderview2

Decisão: reutilizar o `CLSID_ExplorerBrowser`, implementação COM nativa do Windows Shell. Isso entrega pastas Windows/WSL com ícones, menu de contexto, drag-and-drop, seleção, ordenação, visualizações e travel log do próprio sistema.

O host parte de `FVM_ICON` e usa `IFolderView2::SetViewModeAndIconSize` para uma superfície de ícones mais espaçada, em vez de repetir a tabela branca que motivou esta revisão.

`IExplorerBrowser` não é navegador web. Não usa Chromium, WebView2, HTML, React ou captura de HWND.

### Microsoft Windows classic samples

Fonte:

- https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/Win7Samples/winui/shell/appplatform/ExplorerBrowserCustomContents
- https://github.com/microsoft/Windows-classic-samples/blob/main/LICENSE

Licença: MIT.

Reaproveitamento: o ciclo `OleInitialize` -> `CoCreateInstance(CLSID_ExplorerBrowser)` -> `Initialize` -> `Advise` -> `BrowseToIDList` -> `Destroy` foi adaptado do exemplo oficial e encapsulado em `native_shell_view_host.*`.

### Explorer++

Fonte:

- https://github.com/derceg/explorerplusplus

Referência de produto para navegação rápida, múltiplos modos de exibição, atalhos, preview, drag-and-drop e produtividade.

Licença: GPL-3.0.

Regra aplicada: nenhum código GPL do Explorer++ foi copiado para o CloudOS. Apenas comportamento/UX foi estudado.

### VibeOS (`mr-foxxo/vibe-os`)

Fonte:

- https://github.com/mr-foxxo/vibe-os
- `userland/applications/filemanager.c`

O projeto foi estudado porque também implementa um desktop/file manager nativo. Os conceitos úteis para o CloudOS foram separar resolução de ícones em uma camada própria, usar ícones semânticos por tipo/local, manter barra de status com contexto e privilegiar uma superfície visual de arquivos em vez de uma tabela administrativa.

Nenhum código do VibeOS foi copiado. Há uma inconsistência de licença no próprio repositório: o arquivo `LICENSE` declara MIT, enquanto o README atualmente afirma GPLv3. Até essa divergência ser esclarecida, o CloudOS trata o VibeOS somente como referência de UX/arquitetura, não como fonte de código.

### File Explorer / Windows 11

Fonte:

- https://support.microsoft.com/windows/experience/fileexplorer/file-explorer-in-windows

Padrões aproveitados:

- painel de navegação permanente à esquerda;
- barra de navegação separada da barra de comandos;
- ações frequentes visíveis e ações específicas no contexto;
- conteúdo principal ocupando a maior parte da janela.

## Arquitetura escolhida

```text
CloudOSNativeFilesWindow
  |
  +-- sidebar nativa CloudOS
  |     Home / Desktop / Documents / Downloads
  |     CloudOS Drive / Projects
  |     WSL / System Drive / CloudOS Trash
  |
  +-- toolbar nativa CloudOS
  |     Back / Forward / Up / Address / Refresh
  |     New folder / Rename / Delete
  |     layout DPI-aware + janela DWM escura
  |
  +-- Windows ou WSL
  |     -> NativeShellViewHost
  |     -> CLSID_ExplorerBrowser
  |     -> Shell view real do Windows
  |
  +-- CloudOS Drive
        -> grade nativa de ícones grandes controlada pelo CloudOS
        -> ícones reais do Windows Shell
        -> NativeCloudOSDrive
        -> validação de raiz/reparse/trash
```

O CloudOS Drive propositalmente **não** é entregue diretamente ao Shell view para as operações internas do aplicativo. Ele continua passando pela fronteira `NativeCloudOSDrive`, preservando a semântica de lixeira transacional e as validações de caminho.

## Fallback

Se `CLSID_ExplorerBrowser` não puder ser criado, `Arquivos` mantém um modo de compatibilidade baseado na enumeração Win32 anterior. A falha do componente do Shell não pode tornar o gerenciador de arquivos inutilizável.

## Próximos passos pesquisáveis

Antes de adicionar tabs, preview, thumbnails próprios, busca indexada ou dual-pane, pesquisar novamente:

1. APIs oficiais do Windows Shell para a função;
2. Windows classic samples;
3. projetos C++ maduros;
4. licença de cada referência;
5. impacto sobre CloudOS Drive e WSL.
