# CloudOS Native — pesquisa de hospedagem de apps, navegador e comportamento de shell

## Problema que motivou esta fase

A tentativa anterior tratava qualquer destino externo como se fosse um executável Win32 simples que sempre:

1. retornaria `hProcess` em `ShellExecuteExW`;
2. criaria uma janela top-level previsível;
3. aceitaria `SetParent` entre processos;
4. poderia ser convertido para `WS_CHILD` sem efeitos colaterais.

Esse modelo falhou na prática com URLs (`https://www.google.com/`) e é arquiteturalmente incorreto para um shell de desktop genérico.

## Fontes primárias consultadas

### Shell Launcher

Microsoft Learn — Shell Launcher overview:
https://learn.microsoft.com/windows/configuration/assigned-access/shell-launcher

O Shell Launcher substitui `Explorer.exe` por um shell customizado, mas não transforma as janelas dos outros aplicativos em child windows do processo do shell. O próprio documento deixa claro que um shell customizado pode iniciar outros aplicativos e que esses aplicativos continuam sendo aplicativos Windows normais.

**Conclusão CloudOS:** "estar no CloudOS" deve significar fazer parte da sessão visual gerenciada pelo desktop/taskbar/window manager do CloudOS, não obrigatoriamente possuir o HWND do CloudOS como `parent`.

### Desktop Window Manager / composição

Microsoft Learn — Desktop Window Manager overview:
https://learn.microsoft.com/windows/win32/dwm/dwm-overview

Microsoft Learn — DirectComposition architecture and components:
https://learn.microsoft.com/windows/win32/directcomp/architecture-and-components

No desktop composto, janelas top-level têm superfícies próprias e o DWM compõe essas superfícies em uma imagem final do desktop.

**Conclusão CloudOS:** janelas de aplicações são entidades top-level por natureza. O window manager deve observar, focar, mover, minimizar, maximizar e organizar essas janelas; não convertê-las indiscriminadamente em controles filhos.

### SetParent

Microsoft Learn — `SetParent`:
https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setparent

A documentação registra explicitamente que:

- `SetParent` não corrige automaticamente `WS_CHILD`/`WS_POPUP`;
- é necessário sincronizar UI state;
- processos com modos diferentes de DPI awareness podem sofrer reset forçado ou comportamento inesperado;
- cross-process parenting tem implicações diferentes de in-process parenting.

**Conclusão CloudOS:** `SetParent` cross-process não é uma fundação correta para o AppHost universal. Pode ser usado apenas em integrações explicitamente compatíveis e testadas, nunca como política padrão de lançamento.

### ShellExecuteEx

Microsoft Learn — ShellExecute / ShellExecuteEx e Shell execution:
https://learn.microsoft.com/windows/win32/shell/launch
https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shellexecuteexw

O Shell pode resolver um destino por associação, protocolo, DDE ou por um aplicativo já em execução. Um `hProcess` não é uma identidade universal de sucesso para toda ativação de Shell.

**Conclusão CloudOS:** sucesso de `ShellExecuteExW` é o contrato principal. `hProcess` é um dado opcional e nunca deve ser exigido para URLs, protocolos ou ativações do Shell.

Foi exatamente esse erro que produziu a mensagem:

`Nao foi possivel abrir https://www.google.com/ dentro do CloudOS.`

O navegador padrão podia ser reutilizado/ativado pelo Shell sem satisfazer a suposição artificial de `hProcess + HWND capturável`.

### WebView2

Microsoft Learn — Get started with WebView2 in Win32 apps:
https://learn.microsoft.com/microsoft-edge/webview2/get-started/win32

Microsoft Learn — WebView2 API overview:
https://learn.microsoft.com/microsoft-edge/webview2/concepts/overview-features-apis

A documentação mostra WebView2 como a solução oficial para hospedar conteúdo web dentro de um aplicativo Win32. Ela fornece:

- `Navigate`;
- histórico (`CanGoBack`, `CanGoForward`, `GoBack`, `GoForward`);
- `Reload` e `Stop`;
- eventos de origem/navegação;
- `NewWindowRequested` para controlar popups;
- isolamento do conteúdo web dentro de uma superfície controlada pelo host.

**Conclusão CloudOS:** o app `browser` deve ser um navegador CloudOS nativo com WebView2, em vez de pedir ao Shell para abrir Google em um navegador externo e tentar capturar sua janela depois.

### Top-level windows e taskbar

Microsoft Learn — The Taskbar:
https://learn.microsoft.com/windows/win32/shell/taskbar

A documentação explica que janelas não-owned/top-level são justamente o modelo normal de janelas de aplicação e são refletidas pelo Shell/taskbar.

**Conclusão CloudOS:** o `CloudOSNativeWindowManager` deve tratar HWNDs top-level como tarefas da sessão. Aplicações externas compatíveis devem permanecer top-level e ser representadas na taskbar CloudOS.

### AppUserModelID

Microsoft Learn — Application User Model IDs:
https://learn.microsoft.com/windows/win32/shell/appids

AppUserModelIDs existem para associar processos, janelas e atalhos a identidades de aplicação e controlar agrupamento/integração com o Shell.

**Conclusão CloudOS:** identidade e agrupamento devem ser resolvidos como metadados do shell, não por parenting artificial.

### IExplorerBrowser

Microsoft Learn — `IExplorerBrowser`:
https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexplorerbrowser

A implementação do Windows oferece navegação real pelo namespace do Shell e histórico automático.

**Conclusão CloudOS:** o CloudOS Files já está no caminho correto ao usar `IExplorerBrowser` para o namespace Windows. O volume do sistema deve abrir dentro do Files do CloudOS, não via `explorer.exe`.

### Aplicativos modernos / UWP

Microsoft Learn — `IApplicationActivationManager`:
https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-iapplicationactivationmanager

Aplicativos modernos podem ser ativados por contrato e AppUserModelID em vez do modelo clássico "um exe => um HWND => um processo retornado".

**Conclusão CloudOS:** protocolos como `ms-settings:` não devem passar pelo mesmo caminho de hospedagem de um executável Win32 clássico.

### DPI awareness

Microsoft Learn — DPI awareness contexts:
https://learn.microsoft.com/windows/win32/hidpi/dpi-awareness-context

Per Monitor V2 é o modo apropriado para janelas modernas que mudam entre monitores. O manifest do CloudOS já declara `PerMonitorV2`.

**Conclusão CloudOS:** outra razão para não usar cross-process `SetParent` como estratégia universal é evitar misturar contextos de DPI e forçar resets/compatibilidade do processo filho.

---

## Nova matriz de lançamento

### Tier A — apps internos CloudOS

Executam no processo/arquitetura CloudOS e possuem UI nativa própria:

- Terminal / PowerShell / WSL (ConPTY);
- Files;
- CloudOS Drive;
- Projects;
- Notepad;
- Calculator;
- Settings;
- System Monitor;
- Apps;
- Run;
- Environment Doctor;
- Browser WebView2.

Esses aplicativos são a experiência preferencial.

### Tier B — conteúdo web

URLs HTTP/HTTPS abrem no **CloudOS Browser**, que usa WebView2 diretamente.

Não existe mais fluxo:

`URL -> ShellExecute -> exigir hProcess -> caçar HWND -> SetParent`.

### Tier C — Shell/system handoff

Recursos cuja UI pertence ao Windows ou a outro produto continuam como janelas top-level:

- Paint;
- Media Player;
- Regedit;
- Snipping Tool;
- Windows Settings / `ms-settings:`;
- VS Code quando instalado.

O CloudOS inicia a operação e o `CloudOSNativeWindowManager` passa a tratá-la como uma tarefa/window da sessão quando a janela aparece.

`ShellExecuteExW` pode retornar um handle de processo; se retornar, ele é usado apenas para um pequeno `WaitForInputIdle` e fechado. A falta de `hProcess` não transforma uma ativação válida em erro.

### Tier D — integrações especiais futuras

Somente quando uma aplicação for explicitamente testada e suportar hospedagem controlada, poderá existir um host dedicado. Esse host deve ter contrato próprio e não será chamado de "universal".

---

## Navegador CloudOS implementado nesta fase

O novo `CloudOSNativeBrowserWindow` possui:

- WebView2 Evergreen já usado pelo projeto;
- barra de endereço;
- normalização de URL;
- busca Google quando a entrada não parece hostname/URL;
- suporte a UTF-8 na query;
- voltar;
- avançar;
- recarregar;
- home;
- status;
- atualização da barra de endereço via `SourceChanged`;
- popups capturados por `NewWindowRequested` e navegados na mesma superfície;
- bloqueio de esquemas arbitrários: navegação principal limitada a `http`, `https` e `about:blank`.

O host WebView2 agora possui dois modos claramente separados:

1. `TrustedLocalUi`: preserva a política rígida de `https://cloudos.local` para UI local legada/fallback;
2. `Browser`: permite navegação web normal, sem habilitar o canal `postMessage` do CloudOS para páginas externas.

Essa separação evita transformar a superfície web local privilegiada em um navegador geral com ponte nativa exposta.

---

## Contratos que devem impedir regressão

Os testes devem falhar se:

- o launcher voltar a exigir `hProcess` para considerar uma ativação do Shell bem sucedida;
- `SetParent` cross-process voltar a ser política universal;
- o app `browser` voltar a abrir Google com `ShellExecute`;
- o Browser deixar de usar `CreateBrowser`/WebView2;
- os controles essenciais de navegação desaparecerem;
- `native_browser_window.cpp` deixar de ser compilado;
- o volume Windows voltar a abrir por `explorer.exe` em vez de CloudOS Files.

---

## Próximos blocos arquiteturais

1. Separar Desktop, Taskbar e Start em HWNDs próprios e independentes.
2. Adicionar identidade explícita AppUserModelID às janelas internas que precisem agrupamento distinto.
3. Implementar um `SystemActivationBroker` para Win32, protocolos e AppUserModelIDs/UWP.
4. Implementar modo de sessão CloudOS opcional, que coordene Explorer/taskbar Windows sem depender de hacks de Z-order.
5. Persistir pinned apps, posição de atalhos e preferências do shell.
6. Adicionar notificações e quick settings baseados em dados reais.
7. Melhorar a taskbar para agrupamento por app/processo, overflow e previews via DWM thumbnails.
