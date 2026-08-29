# CloudOS Native Shell — modelo de desktop baseado em arquitetura real de sistema

## Objetivo

O CloudOS Native não deve fingir ser um kernel. No computador atual, o kernel, drivers, scheduler, memória virtual, segurança de processos, DWM e a pilha gráfica continuam sendo do Windows. O CloudOS ocupa a camada que, em um sistema operacional de desktop, corresponde ao **shell de sessão / desktop environment**: desktop, launcher/Start, taskbar, pesquisa, gerenciamento de janelas, workspaces, arquivos, terminal e pontos de entrada para serviços do sistema.

Essa distinção é importante porque copiar a aparência de um sistema operacional sem copiar a arquitetura da experiência produz um "dashboard". O objetivo desta fase é o oposto: organizar o CloudOS como um shell de desktop real.

## Pesquisa usada

Fontes primárias da Microsoft consultadas antes desta implementação:

- Microsoft Learn — Shell Launcher overview  
  https://learn.microsoft.com/windows/configuration/assigned-access/shell-launcher
- Microsoft Learn — Desktop Window Manager overview  
  https://learn.microsoft.com/windows/win32/dwm/dwm-overview
- Microsoft Learn — DirectComposition architecture and components  
  https://learn.microsoft.com/windows/win32/directcomp/architecture-and-components
- Microsoft Learn — The Taskbar  
  https://learn.microsoft.com/windows/win32/shell/taskbar
- Microsoft Learn — Common Explorer Concepts  
  https://learn.microsoft.com/windows/win32/shell/explorer-concepts
- Microsoft Learn — Windowing overview for WinUI and Windows App SDK  
  https://learn.microsoft.com/windows/apps/develop/ui/windowing-overview
- Microsoft Learn — Title bar customization  
  https://learn.microsoft.com/windows/apps/develop/title-bar

Nenhum código dessas páginas foi copiado. Elas foram usadas para definir arquitetura e comportamento.

## O que um desktop de sistema realmente faz

### 1. Sessão

Depois do logon existe um shell de usuário responsável por apresentar a sessão. No Windows comum essa função é exercida principalmente pelo Explorer. O Shell Launcher documenta que o Explorer pode ser substituído por um shell customizado em cenários suportados.

**Mapeamento CloudOS:** `CloudOS.exe` é o shell visual da sessão CloudOS.

### 2. Composição

Aplicativos não "pintam o desktop inteiro". Cada janela possui sua própria superfície/`HWND`; o DWM compõe as superfícies em uma imagem final do desktop.

**Mapeamento CloudOS:** o `CloudOSNativeWindowManager` acompanha janelas reais. Aplicativos externos que precisam permanecer visualmente dentro do CloudOS, enquanto o Explorer ainda é o shell principal do Windows, passam por um host filho. Em um futuro modo de substituição de shell, janelas top-level normais continuarão corretas: elas serão compostas pelo DWM sobre o desktop CloudOS, exatamente como em um desktop tradicional.

### 3. Desktop

O desktop é a raiz visual e conceitual do namespace do shell. Ele oferece atalhos e acesso a objetos do sistema, sem ser um painel gigante contendo todos os aplicativos.

**Mapeamento CloudOS:** a superfície principal passa a ser um desktop limpo com atalhos persistentes, wallpaper, status real e nenhuma grade permanente de "cards de dashboard".

### 4. Taskbar

A taskbar representa aplicações, atalhos fixados e uma área de notificação/status. Janelas de aplicação são refletidas nela.

**Mapeamento CloudOS:** a barra inferior agora separa quatro conceitos:
- workspaces;
- tarefas/janelas ativas;
- launcher + aplicativos fixados;
- estado real do sistema e relógio.

### 5. Start / launcher

O launcher serve para encontrar e iniciar programas, configurações e ferramentas. Ele é uma superfície temporária, não o desktop inteiro.

**Mapeamento CloudOS:** a pesquisa e a grade de aplicativos passam a viver em um Start menu sobreposto que abre sob demanda e fecha ao iniciar algo ou clicar fora.

### 6. Namespace e arquivos

O Shell do Windows trata arquivos, pastas e objetos virtuais como um namespace. O CloudOS já usa `IExplorerBrowser` para a camada Windows e mantém um namespace próprio no CloudOS Drive.

**Mapeamento CloudOS:** Files continua sendo a interface de namespace; o desktop apenas oferece atalhos para entrar nela.

### 7. Workspaces e window manager

Workspaces são política do window manager, não "páginas" de um dashboard.

**Mapeamento CloudOS:** `CloudOSNativeWindowManager` continua responsável por foco, workspace, snap, floating e tiling. O tiling permanece manual.

## Decisões desta fase

1. Remover o dashboard central permanente.
2. Transformar a superfície em desktop real.
3. Transformar pesquisa + apps em Start menu modal/temporário.
4. Transformar a barra inferior em taskbar, não dock decorativo.
5. Usar apenas telemetria real para CPU/RAM, workspace, relógio e ABI.
6. Manter atalhos de desktop separados dos apps fixados na taskbar.
7. Manter MRU apenas em "Recentes" no Start.
8. Não reativar WebView como shell.
9. Não reativar tiling automático.
10. Continuar usando DWM/Win32 como infraestrutura real de janelas.

## Próxima fronteira arquitetural

O passo seguinte para aproximar ainda mais o CloudOS de um desktop de sistema é separar definitivamente:

- `SessionShell`: ciclo de vida da sessão;
- `DesktopSurface`: wallpaper + ícones;
- `Taskbar`: tarefas, pinned apps, tray;
- `StartMenu`: launcher e busca;
- `WindowManager`: foco/workspaces/snap;
- `SystemBroker`: serviços Windows/WSL;
- `AppHost`: contenção/integração de aplicativos externos.

Essa separação deve acontecer sem voltar a criar componentes vazios ou placeholders. Cada módulo só entra no build quando tiver comportamento funcional.
