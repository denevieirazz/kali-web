# CloudOS Native — Browser, HWNDs externos e política de windowing

## Problema observado

O shell anterior tratava URL e aplicativo Windows do mesmo jeito: criava um host `WS_CHILD`, iniciava o alvo com `ShellExecuteExW`, procurava um HWND na família de processos e tentava aplicar `SetParent` para capturar a janela dentro do CloudOS. Isso falha para URLs, navegadores que reutilizam processos existentes, UWP/WinUI, processos elevados e vários aplicativos multiprocesso. O erro visível ao abrir `https://www.google.com/` foi consequência direta dessa arquitetura.

## Fontes primárias pesquisadas

A implementação desta fase foi baseada em documentação oficial Microsoft, sem copiar código das páginas:

- Microsoft Learn — Get started with WebView2 in Win32 apps
  - https://learn.microsoft.com/microsoft-edge/webview2/get-started/win32
  - O host Win32 cria um `ICoreWebView2Environment`, depois um `ICoreWebView2Controller` associado a um HWND próprio e usa `ICoreWebView2::Navigate` para navegar.
  - A sequência documentada de navegação inclui `NavigationStarting`, `SourceChanged`, `ContentLoading`, `HistoryChanged` e `NavigationCompleted`.

- Microsoft Learn — `ICoreWebView2` / `HistoryChanged`
  - https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/icorewebview2
  - `HistoryChanged` é o ponto apropriado para atualizar `CanGoBack`/`CanGoForward`; `GoBack`, `GoForward` e `Reload` pertencem ao próprio motor WebView2.

- Microsoft Learn — `SetParent`
  - https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setparent
  - `SetParent` não altera automaticamente `WS_CHILD`/`WS_POPUP` e exige sincronização de estado da UI.
  - A documentação registra comportamento inesperado e reset de DPI awareness em cenários cross-process. Portanto ele não é uma fundação confiável para um shell que pretende hospedar qualquer aplicativo arbitrário.

- Microsoft Learn — Shell Launcher overview
  - https://learn.microsoft.com/windows/configuration/assigned-access/shell-launcher
  - O Windows permite substituir Explorer por um shell customizado e esse shell pode iniciar outros aplicativos. O modelo documentado é shell + aplicativos do sistema, não reparentar cada processo externo para dentro de um único HWND.

- Microsoft Learn — DPI awareness para desktop apps
  - https://learn.microsoft.com/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process
  - Processos e janelas podem operar em contextos DPI diferentes; isso reforça que reparenting cross-process é uma fronteira frágil.

## Arquitetura adotada

### 1. Aplicativos centrais do CloudOS

Ferramentas que fazem parte da identidade do CloudOS devem possuir HWNDs e lógica do próprio CloudOS:

- Files
- Projects
- Terminal / WSL
- Notepad
- Calculator
- System Monitor
- Settings
- Run
- Browser

Elas não dependem de capturar uma janela de terceiro para parecer integradas.

### 2. Browser é um app nativo do shell

`CloudOSNativeBrowserWindow` é um HWND Win32 do CloudOS com WebView2 em processo. O WebView2 é apenas o motor de conteúdo web; barra de endereço, histórico, voltar, avançar, recarregar, início, status, ciclo de vida e janela pertencem ao CloudOS.

Isso elimina o caminho defeituoso `LaunchExternal("https://...")`.

O perfil do navegador fica em `%LOCALAPPDATA%\CloudOS\BrowserProfile`, separado do perfil usado pela antiga superfície web do shell.

### 3. Aplicativos Windows externos

Paint, Regedit, Snipping Tool, Settings URI, players e outros programas que não são implementações CloudOS são iniciados como janelas Windows normais. O `CloudOSNativeWindowManager` pode observar, focar, listar e aplicar políticas de workspace às janelas top-level que o Windows/DWM gerencia.

**Política:** não aplicar `SetParent` cross-process por padrão.

Isso é mais próximo da arquitetura de um desktop real: o shell gerencia a sessão e as janelas; não transforma todo aplicativo arbitrário em um child control.

### 4. Contenção futura

Se houver necessidade de uma experiência de app realmente “dentro” do CloudOS, ela deve usar uma integração suportada para aquele tipo de conteúdo:

- conteúdo web: WebView2;
- terminal: ConPTY;
- arquivos: `IExplorerBrowser` / Shell namespace;
- editor: implementação própria ou componente embutível explícito;
- aplicativos terceiros: top-level HWND gerenciado pelo window manager, salvo quando o próprio aplicativo fornece API de embedding.

## Contratos anti-regressão

A suíte nativa deve falhar se:

1. Browser voltar a usar `LaunchWindowsTarget`/`ShellExecuteExW` para abrir `https://www.google.com/`;
2. launcher compilado voltar a conter `SetParent`, `kExternalHostClass` ou política geral de `WS_CHILD` para processos externos;
3. `native_browser_window.cpp` deixar de criar WebView2 via `CreateCoreWebView2EnvironmentWithOptions` + `CreateCoreWebView2Controller`;
4. histórico Back/Forward deixar de ser derivado de `HistoryChanged` e `CanGoBack`/`CanGoForward`;
5. o projeto voltar a compilar `native_app_launcher.cpp` legado no lugar de `native_app_launcher_v2.cpp`.

## Próxima etapa

Depois de estabilizar Browser + launcher, a evolução do shell deve continuar em blocos funcionais: separar taskbar, Start e desktop em superfícies próprias; consolidar gerenciamento de janelas; padronizar chrome dos apps internos; e só então considerar um modo opcional de shell replacement. Cada etapa deve manter um caminho de recuperação para o Explorer/Windows durante desenvolvimento.
