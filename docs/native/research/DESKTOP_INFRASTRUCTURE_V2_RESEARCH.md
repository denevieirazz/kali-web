# CloudOS Native Shell V2 — pesquisa e decisões de infraestrutura

## Objetivo

Esta fase substitui o desktop monolítico por infraestrutura de shell com responsabilidades separadas: Desktop HWND, Taskbar AppBar, Start popup, Task Switcher DWM, Quick Settings, Notification Center, desktop OLE drop target, wallpaper persistente e topologia multi-monitor.

O Windows continua fornecendo kernel, drivers, DWM, segurança, áudio e APIs de Shell. O CloudOS assume a experiência de sessão e coordena essas APIs em vez de simular um kernel próprio.

## 1. Taskbar como AppBar real

Fontes primárias:

- https://learn.microsoft.com/windows/win32/shell/application-desktop-toolbars
- https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shappbarmessage
- https://learn.microsoft.com/windows/win32/shell/abm-new

A documentação da Microsoft define Application Desktop Toolbars como barras registradas no sistema por `SHAppBarMessage`. A sequência relevante é:

1. `ABM_NEW` registra a AppBar e fornece a mensagem de callback;
2. `ABM_QUERYPOS` negocia a posição com outras AppBars;
3. `ABM_SETPOS` confirma a área reservada;
4. `ABN_POSCHANGED` exige renegociação quando outra barra muda;
5. `ABM_REMOVE` remove corretamente a reserva ao encerrar.

Decisão CloudOS:

- cada monitor enumerado recebe uma `CloudOSTaskbarAppBar` própria;
- a taskbar deixa de ser apenas desenho dentro do desktop;
- o `WindowManager` deixa de subtrair pixels manualmente e passa a usar `rcWork` já negociado pelo Windows;
- Explorer pode continuar ativo durante desenvolvimento: AppBars negociam entre si, em vez de a barra CloudOS simplesmente cobrir a barra do Windows.

## 2. Start em HWND independente

O Start deixa de ser uma região permanente do HWND do desktop. `CloudOSNativeStartMenuWindow` é um popup top-level `WS_POPUP | WS_EX_TOOLWINDOW | WS_EX_TOPMOST` que:

- abre acima da AppBar que o chamou;
- respeita o monitor da barra clicada;
- fecha ao perder ativação;
- possui busca incremental;
- navegação por teclado;
- Enter e duplo clique;
- acesso à Central de Comandos;
- acesso ao menu de energia.

Isso reduz acoplamento entre desktop, taskbar e launcher.

## 3. Alt+Tab e thumbnails ao vivo do DWM

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmregisterthumbnail
- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmupdatethumbnailproperties
- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmunregisterthumbnail

`DwmRegisterThumbnail` cria uma relação entre uma janela de destino top-level e uma janela fonte top-level. A miniatura só aparece depois de `DwmUpdateThumbnailProperties`; a relação deve ser liberada com `DwmUnregisterThumbnail`.

Decisão CloudOS:

- o seletor usa somente janelas do workspace atual do `CloudOSNativeWindowManager`;
- até oito previews são compostos pelo DWM em tempo real;
- Alt+Tab é tentado como hotkey canônica;
- como o Explorer/Windows pode reservar Alt+Tab enquanto o CloudOS ainda não é shell dedicado, existe fallback `Ctrl+Alt+Tab`;
- o seletor aceita setas, Tab, Enter, clique e Escape;
- um pequeno timer confirma a seleção quando o hotkey deixa de ser repetido.

## 4. OLE drag-and-drop no Desktop

Fontes primárias:

- https://learn.microsoft.com/windows/win32/com/drag-and-drop
- https://learn.microsoft.com/windows/win32/api/ole2/nf-ole2-registerdragdrop

A documentação exige `IDropTarget` + `RegisterDragDrop` para uma janela aceitar objetos OLE e observa que `OleInitialize` deve ser usado no thread que registra o alvo.

Decisão CloudOS:

- o processo já usa `OleInitialize` no `wWinMain`;
- Desktop V2 registra `IDropTarget` real;
- `CF_HDROP` é aceito para arquivos e pastas;
- a cópia é executada por `IFileOperation`, preservando integração com o Shell e suporte a operações grandes;
- `RevokeDragDrop` é chamado no teardown;
- o Desktop é invalidado após o drop para exibir os novos itens.

O ExplorerBrowser usado no aplicativo Arquivos já participa do Shell/OLE, portanto arrastar um item da Shell View para o Desktop CloudOS pode usar o mesmo formato padrão do Windows.

## 5. Quick Settings com áudio e energia reais

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/endpointvolume/nn-endpointvolume-iaudioendpointvolume
- https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-getsystempowerstatus

`IAudioEndpointVolume` representa o volume do endpoint de áudio; o objeto é obtido ativando a interface no dispositivo padrão do MMDevice. `GetSystemPowerStatus` fornece AC/DC, bateria, carregamento e percentual restante.

Decisão CloudOS:

- slider de volume lê/escreve o volume master real;
- botão Mudo usa o estado real do endpoint;
- bateria/AC é exibida quando disponível;
- contagem de monitores é real;
- Wi-Fi, Bluetooth, Rede, Tela/Brilho, Som e Energia abrem os pontos oficiais `ms-settings:`;
- brilho não é falsificado: em hardware sem uma API uniforme de brilho, o botão leva à página real de Tela.

## 6. Notification Center e área de status

Fontes primárias:

- https://learn.microsoft.com/windows/win32/shell/notification-area
- https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shell_notifyicona

A área de notificação representa status e recursos transitórios, tradicionalmente bateria, volume e rede. Nesta fase o CloudOS implementa sua própria área de status dentro da AppBar e uma central de histórico do shell.

Decisão CloudOS:

- taskbar exibe estado rápido e contador de notificações;
- Central de Notificações mantém até 100 eventos da sessão;
- abrir a central marca os itens como lidos;
- eventos como startup, mudança de wallpaper, alteração de topologia e drop de arquivos geram notificações CloudOS;
- `Shell_NotifyIcon` continua pertencendo à área de notificação do Explorer enquanto Explorer estiver ativo; não é usado como substituto da área CloudOS.

## 7. Multi-monitor

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-enumdisplaymonitors
- https://learn.microsoft.com/windows/win32/gdi/multiple-display-monitors-functions

`EnumDisplayMonitors`, `GetMonitorInfo`, `MonitorFromWindow` e a tela virtual são as primitivas Win32 adequadas.

Decisão CloudOS:

- `NativeMonitorManager` enumera todos os monitores;
- Desktop V2 ocupa a tela virtual inteira;
- uma AppBar CloudOS é criada por monitor;
- alterações de topologia geram uma assinatura nova, desmontam as AppBars antigas e reconstroem o conjunto;
- mover janela para monitor adjacente preserva posição relativa e tamanho quando possível;
- CloudOS tenta `Win+Shift+Left/Right`, mantendo `Ctrl+Alt+Shift+Left/Right` como fallback quando o Windows reserva a combinação.

## 8. Wallpaper e Desktop real

A preferência de wallpaper CloudOS é persistida em `HKCU\\Software\\CloudOS\\ShellV2\\WallpaperPath`. GDI+ carrega a imagem e aplica crop proporcional para preencher a superfície. A seleção usa diálogo Win32 e também solicita `SPI_SETDESKWALLPAPER` para manter a sessão Windows visualmente alinhada quando o formato é aceito.

Desktop V2 também enumera `FOLDERID_Desktop`, desenha os primeiros itens com ícones reais obtidos por `SHGetFileInfoW` e abre o item por `ShellExecuteW` em duplo clique.

O menu de contexto do desktop implementa:

- Nova pasta;
- Novo arquivo de texto;
- abrir Desktop em Arquivos;
- abrir Terminal no Desktop;
- Central de Comandos;
- mudar wallpaper;
- restaurar wallpaper padrão;
- configurações de tela;
- personalização;
- auto-organização/refresh.

## 9. Shell Launcher dedicado

Fontes primárias:

- https://learn.microsoft.com/windows/configuration/shell-launcher/
- https://learn.microsoft.com/windows/configuration/shell-launcher/wesl-usersetting
- https://learn.microsoft.com/windows/configuration/shell-launcher/wesl-usersettingsetcustomshell

A Microsoft limita Shell Launcher às edições Enterprise, Enterprise LTSC, Education e IoT Enterprise. A configuração suportada usa `WESL_UserSetting`, não hacks silenciosos em Winlogon.

Decisão CloudOS:

- este bloco NÃO altera o shell de logon automaticamente;
- o modo dedicado só deve ser oferecido por script separado, explícito, elevado, reversível e depois de validar a edição do Windows;
- desenvolvimento normal continua coexistindo com Explorer.

## Critérios de não regressão

O teste V2 deve falhar se:

- `main.cpp` ou `native_desktop_window.cpp` antigos voltarem ao grafo compilado;
- a taskbar deixar de usar `ABM_NEW`, `ABM_QUERYPOS`, `ABM_SETPOS`, `ABM_REMOVE` e `ABN_POSCHANGED`;
- o Start voltar a ser desenhado dentro do Desktop compilado;
- o Task Switcher perder DWM thumbnails;
- OLE drop perder `RegisterDragDrop`, `IDropTarget`, `CF_HDROP` ou `IFileOperation`;
- Quick Settings perder `IAudioEndpointVolume` ou `GetSystemPowerStatus`;
- multi-monitor perder `EnumDisplayMonitors`/`GetMonitorInfoW`;
- o launcher legado com `SetParent` voltar ao build;
- o catálogo de ações cair abaixo de 100 entradas.

## Próximas fronteiras

Depois da validação MSVC/Windows real desta fase, os próximos blocos devem atacar: snap-assist por mouse/hover no maximizar, persistência manual de posição dos ícones, session recovery por janela realmente aberta, clipboard/drag source customizado fora do ExplorerBrowser, ZIP/extract/progresso dedicado em Arquivos e ativação opcional do Shell Launcher em edições compatíveis.
