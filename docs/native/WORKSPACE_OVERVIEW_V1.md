# CloudOS Native Workspace Overview V1

## Objetivo

A Visão de Trabalho é a superfície nativa de gerenciamento das quatro áreas de trabalho do CloudOS. Ela não substitui o Windows Task View e não tenta manipular desktops virtuais privados do Explorer. Em vez disso, opera diretamente sobre o modelo de workspaces já controlado por `CloudOSNativeWindowManager`.

O objetivo é oferecer uma visão global e operacional de todas as janelas gerenciadas pelo shell sem introduzir HTML, React, `SetParent` cross-process ou captura de screenshots.

## Autoridade

A implementação autoritativa está em:

- `native_workspace_overview_window.h/.cpp`
- `native_shell_bridge.h/.cpp`
- `main_shell_v2.cpp`
- `native_window_manager.h/.cpp`

O app é compilado no mesmo `CloudOS.exe` do restante do shell e usa Win32, GDI+, DWM thumbnails e Common Controls.

## Descoberta

A superfície pode ser aberta por quatro caminhos:

1. `Ctrl+Alt+O` global;
2. Start, pesquisando `Visão de Trabalho`, `workspace`, `overview`, `janelas`, `task view` ou termos equivalentes;
3. catálogo de aplicativos, id `workspaces`;
4. Quick Hub, em `CloudOS e desenvolvimento > Visão de Trabalho`.

O launcher aceita aliases `workspace`, `overview`, `task-view`, `mission-control` e `areas`, mas todos convergem para o id canônico `workspaces`.

## Modelo visual

A janela tem quatro regiões principais.

### Cabeçalho

Mostra o nome da superfície e os atalhos principais.

### Busca global

O campo de pesquisa filtra simultaneamente por:

- título da janela;
- número da área;
- PID;
- estado flutuante/gerenciado.

A consulta é feita sobre uma cópia reconciliada de `AllManagedWindows()`.

### Quatro cartões de área

Cada cartão mostra:

- Área 1..4;
- número de janelas gerenciadas naquela área;
- indicador da área atual;
- hover nativo.

Clique normal troca para a área. `Shift+clique` move a janela ativa para aquela área e acompanha a janela.

### Lista + preview

A lista apresenta:

- Janela;
- Área;
- Modo;
- PID.

A seleção atual alimenta um preview DWM ao lado. O preview não é screenshot e não depende de captura de outra aplicação.

Fluxo DWM:

1. `DwmRegisterThumbnail` registra a relação entre a janela fonte e a Visão de Trabalho;
2. `DwmQueryThumbnailSourceSize` obtém a razão real da fonte;
3. o destino é ajustado preservando aspect ratio;
4. `DwmUpdateThumbnailProperties` posiciona e torna o thumbnail visível;
5. `DwmUnregisterThumbnail` sempre é chamado ao trocar seleção, ocultar/destroçar a superfície ou destruir a janela.

## Ações sobre janelas

A Visão de Trabalho não cria um segundo window manager. Todas as ações são encaminhadas ao `CloudOSNativeWindowManager` ou à mensagem Win32 apropriada.

As ações disponíveis são:

- focar janela;
- trocar para a área da janela e focá-la;
- mover janela selecionada para Área 1..4;
- mover e acompanhar a janela;
- alternar flutuante/gerenciada;
- minimizar;
- maximizar/restaurar;
- fechar via `WM_CLOSE`;
- alternar tiling da área atual;
- trocar de área sem fechar a superfície.

## Atalhos dentro da Visão de Trabalho

| Tecla | Ação |
| --- | --- |
| `Ctrl+F` | focar busca |
| `↓` na busca | focar lista |
| `Enter` | focar/abrir janela selecionada |
| `Delete` | fechar janela selecionada |
| `Space` | alternar modo flutuante |
| `T` | alternar tiling |
| `1..4` | trocar diretamente para a área |
| `Shift+1..4` | mover janela selecionada para a área |
| `Ctrl+Shift+1..4` | mover janela e acompanhar |
| `Ctrl+PgUp` | área anterior |
| `Ctrl+PgDn` | próxima área |
| `Apps` / `Shift+F10` | menu contextual da janela |
| `F5` | reconciliar e atualizar |
| `Esc` | limpar busca ou ocultar |

## Atalhos globais adicionados

| Atalho | Ação |
| --- | --- |
| `Ctrl+Alt+O` | alternar Visão de Trabalho |
| `Ctrl+Alt+PgUp` | área anterior |
| `Ctrl+Alt+PgDn` | próxima área |
| `Ctrl+Alt+Shift+PgUp` | mover janela ativa para a área anterior e acompanhar |
| `Ctrl+Alt+Shift+PgDn` | mover janela ativa para a próxima área e acompanhar |
| `Ctrl+Alt+D` | alternar Mostrar Área de Trabalho no workspace atual |

Os atalhos diretos existentes `Ctrl+Alt+1..4` e `Ctrl+Alt+Shift+1..4` continuam válidos.

## Mostrar Área de Trabalho

Há agora dois caminhos nativos para o comportamento:

- faixa no extremo direito da Taskbar V4;
- `Ctrl+Alt+D` e Quick Hub, através do `NativeShellBridge`.

O comando global opera somente sobre `CurrentWorkspaceWindows()`. Se existe alguma janela visível e não minimizada, elas são minimizadas. Se não existe, as janelas minimizadas do workspace são restauradas.

O comportamento da faixa extrema da taskbar permanece monitor-aware; o comando global é workspace-aware.

## NativeShellBridge

O launcher precisa abrir uma superfície cujo objeto é propriedade de `CloudOSApplication`. Para não criar singleton global da janela nem acoplar `NativeAppLauncher` ao ciclo de vida completo da aplicação, o CloudOS usa `NativeShellBridge`.

A bridge mantém callbacks `std::function<void()>` protegidos por mutex:

- abrir/toggle da Visão de Trabalho;
- Mostrar Área de Trabalho.

O callback é copiado sob lock e executado depois da liberação do mutex. Isso evita executar UI arbitrária segurando o lock global.

No shutdown `NativeShellBridge::Clear()` remove os callbacks antes da destruição das superfícies.

## Relação com Start e MRU

`workspaces` é um `AppItem` real no catálogo `kAllApps`, portanto:

- aparece em Todos os Aplicativos;
- participa da pesquisa;
- pode ser fixado;
- pode entrar nas recomendações MRU;
- é contabilizado como app CloudOS pelo launcher.

Aberturas por aliases são canonicalizadas para `workspaces`, evitando várias identidades no MRU.

## Relação com Window Manager

A Visão de Trabalho depende das seguintes APIs públicas do manager:

- `AllManagedWindows()`;
- `CurrentWorkspaceWindows()`;
- `ManagedWindowCount()`;
- `CurrentWorkspace()`;
- `ActiveManagedWindow()`;
- `FocusWindow()`;
- `SwitchWorkspace()`;
- `MoveActiveToWorkspace()`;
- `SetWindowFloating()`;
- `ToggleTiling()`;
- `TileCurrentWorkspace()`;
- `MinimizeActive()`;
- `ToggleMaximizeActive()`;
- `Reconcile()`.

Nenhum `HWND` externo é reparentado. O workspace continua sendo representado pelo estado do manager e pelo mecanismo de hide/show já existente.

## Multi-monitor

Ao abrir a Visão de Trabalho, a superfície é posicionada no monitor do owner quando possível e limitada à `rcWork` daquele monitor.

Os quatro workspaces são globais ao modelo CloudOS; a distribuição física das janelas entre monitores continua sendo preservada pelo Window Manager e pelo Windows.

O DWM preview usa a janela selecionada independentemente do monitor em que ela está.

## Segurança de ciclo de vida

Regras importantes:

- a superfície é criada uma vez pela aplicação e depois apenas mostrada/ocultada;
- `WM_CLOSE` oculta em vez de destruir durante uso normal;
- DWM thumbnail é sempre desregistrado antes da destruição;
- bridge é limpa antes da destruição da superfície;
- o timer só executa refresh visual quando a janela está visível;
- a lista é reconstruída a partir de `Reconcile()` para descartar HWNDs mortos;
- ações validam `IsWindow` antes de operar.

## Regressões proibidas

O contrato `scripts/native/test-workspace-overview-contract.ps1` deve falhar se:

- a Visão de Trabalho deixar de ser Win32 nativa;
- HTML/React/WebView2 aparecer nessa superfície;
- `SetParent` for introduzido nela;
- os DWM thumbnails forem removidos silenciosamente;
- a bridge desaparecer;
- os atalhos globais forem removidos;
- o app `workspaces` sair do catálogo ou do launcher;
- os aliases de pesquisa forem removidos;
- os novos `.cpp/.h` saírem do grafo MSVC.

O build autoritativo executa esse contrato antes de iniciar MSVC.

## Próximos níveis possíveis

A arquitetura V1 deixa espaço para evoluções sem trocar o modelo atual:

- thumbnails múltiplos por workspace em mosaico;
- drag-and-drop visual de cards entre áreas;
- nomes personalizados de workspaces;
- persistência do workspace atual entre sessões;
- layouts de tiling por workspace;
- regras de aplicação por workspace;
- histórico de foco por área;
- indicador de monitor em cada linha;
- grupos de janelas por processo no overview;
- ações rápidas diretamente sobre thumbnails.
