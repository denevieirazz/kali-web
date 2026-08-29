# Pesquisa de referência — Arquivos nativo

Data: 2026-08-29

## Problema observado

A primeira versão nativa de `Arquivos` usava somente `BUTTON`, `EDIT` e `ListView` clássicos. Ela preservava operações básicas, mas visualmente parecia uma ferramenta Win32 antiga e reimplementava comportamentos que o Shell do Windows já fornece.

Depois da primeira integração com `IExplorerBrowser`, o conteúdo Windows/WSL já era real, porém a moldura do CloudOS ainda estava visualmente desalinhada: chrome escuro forçado, sidebar compacta demais, botões com bordas pesadas e um `ExplorerBrowser` claro no centro. O resultado parecia dois aplicativos colados.

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

A revisão visual agora usa `FVM_DETAILS` + `IFolderView2::SetViewModeAndIconSize(..., 20)` e uma property bag versionada (`CloudOS.NativeFiles.ShellView.v2`). Isso evita que a antiga preferência de ícones grandes deixe cabeçalho de colunas e grade de 48 px misturados.

`IExplorerBrowser` não é navegador web. Não usa Chromium, WebView2, HTML, React ou captura de HWND.

### Microsoft Windows classic samples

Fonte:

- https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/Win7Samples/winui/shell/appplatform/ExplorerBrowserCustomContents
- https://github.com/microsoft/Windows-classic-samples/blob/main/LICENSE

Licença: MIT.

Reaproveitamento: o ciclo `OleInitialize` -> `CoCreateInstance(CLSID_ExplorerBrowser)` -> `Initialize` -> `Advise` -> `BrowseToIDList` -> `Destroy` foi adaptado do exemplo oficial e encapsulado em `native_shell_view_host.*`.

### Microsoft Fluent / Windows 11 — Mica e layering

Fontes oficiais:

- https://learn.microsoft.com/windows/apps/design/style/mica
- https://learn.microsoft.com/windows/apps/design/signature-experiences/layering
- https://learn.microsoft.com/windows/apps/get-started/best-practices
- https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type
- https://learn.microsoft.com/windows/apps/desktop/modernize/ui/apply-windows-themes

Padrões adotados:

- duas camadas claras: navegação/comandos na base e conteúdo como superfície principal;
- `DWMWA_SYSTEMBACKDROP_TYPE` com `DWMSBT_MAINWINDOW` para o backdrop de janela longa no Windows 11;
- `DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND`;
- chrome de Arquivos em tema claro para combinar com o `ExplorerBrowser` real do sistema, em vez de forçar uma barra/painel escuro ao redor de conteúdo claro;
- superfícies suaves, bordas discretas, seleção em pill arredondada e hierarquia por espaçamento em vez de contornos pesados;
- fallback sólido caso o backdrop não exista ou seja desativado pelo sistema.

A escolha de tema claro é local ao aplicativo `Arquivos`. Ela não muda a linguagem escura do Desktop CloudOS. O objetivo é coerência com a superfície do Shell hospedado sem recorrer a APIs privadas de dark mode do Explorer.

### Files Community (`files-community/Files`)

Fonte:

- https://github.com/files-community/Files
- https://files.community/

O projeto é referência de UX para um gerenciador moderno no Windows: sidebar permanente, grande área de conteúdo, comandos pouco intrusivos, espaçamento generoso e foco em navegação rápida.

O repositório contém material sob MIT e MPL-2.0. Nenhum código foi copiado. Foram estudados apenas organização visual e fluxo de uso.

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
- conteúdo principal ocupando a maior parte da janela;
- apresentação de detalhes compacta para o filesystem Windows.

## Arquitetura escolhida

```text
CloudOSNativeFilesWindow
  |
  +-- native_files_style.*
  |     palette Fluent-inspired
  |     Mica/DWM oficial
  |     superfícies e separadores arredondados
  |
  +-- sidebar nativa CloudOS
  |     header Arquivos
  |     Home / Desktop / Documents / Downloads
  |     CloudOS Drive / Projects
  |     WSL / System Drive / CloudOS Trash
  |     ícones reais + seleção owner-draw arredondada
  |
  +-- toolbar nativa CloudOS
  |     Back / Forward / Up / Address / Go / Refresh
  |     New folder / Rename / Delete
  |     layout DPI-aware e command surfaces discretas
  |
  +-- Windows ou WSL
  |     -> NativeShellViewHost
  |     -> CLSID_ExplorerBrowser
  |     -> Shell view real do Windows em FVM_DETAILS
  |
  +-- CloudOS Drive
        -> grade nativa controlada pelo CloudOS
        -> ícones reais do Windows Shell
        -> NativeCloudOSDrive
        -> validação de raiz/reparse/trash
```

O CloudOS Drive propositalmente **não** é entregue diretamente ao Shell view para as operações internas do aplicativo. Ele continua passando pela fronteira `NativeCloudOSDrive`, preservando a semântica de lixeira transacional e as validações de caminho.

## Fallback

Se `CLSID_ExplorerBrowser` não puder ser criado, `Arquivos` mantém um modo de compatibilidade baseado na enumeração Win32 anterior. A falha do componente do Shell não pode tornar o gerenciador de arquivos inutilizável.

Se `DWMWA_SYSTEMBACKDROP_TYPE` não for aceito em runtime, a paleta sólida clara continua sendo o fallback; o visual não depende de Mica para funcionar.

## Próximos passos pesquisáveis

Antes de adicionar tabs, preview, thumbnails próprios, busca indexada ou dual-pane, pesquisar novamente:

1. APIs oficiais do Windows Shell para a função;
2. Windows classic samples;
3. projetos maduros como Files/Explorer++ apenas dentro dos limites de licença;
4. licença de cada referência;
5. impacto sobre CloudOS Drive e WSL;
6. comportamento em DPI alto, High Contrast e Windows sem backdrop moderno.
