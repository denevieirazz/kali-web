# CloudOS NativeShell

Este diretório contém o shell nativo Windows do CloudOS. O executável final é `CloudOS.exe` e o runtime de suporte é `CloudOS.NativeRuntime.dll`.

## Regra de arquitetura

Aplicativos Windows externos **não são embutidos, reparentados, capturados ou renderizados dentro de uma superfície web**. O modelo normal é:

```text
programa.exe
  -> HWND top-level real do Windows
  -> NativeRuntime observa eventos de janela
  -> NativeWindowManager registra e gerencia o HWND
  -> CloudOS aplica foco, snap, tiling e workspace
```

`SetParent`, captura de frames, WebView2, React, Vite e Node não fazem parte do boot do NativeShell.

## Módulos ativos

| Arquivo | Responsabilidade |
| --- | --- |
| `src/main.cpp` | ciclo de vida do shell, COM/GDI+, timers, hotkeys e integração entre desktop e WindowManager |
| `src/native_desktop_window.*` | superfície da área de trabalho AETHER, busca, widgets e interação visual |
| `src/native_theme.h` | contratos de UI, catálogo de apps e design tokens; AETHER é a linguagem visual, o produto continua sendo CloudOS |
| `src/native_icon_renderer.*` | desenho GDI+ de ícones e superfícies visuais |
| `src/native_search_engine.*` | filtro local do catálogo de apps |
| `src/native_app_launcher.*` | roteamento central de apps internos, Windows e WSL |
| `src/native_window_manager.*` | descoberta e gerenciamento de HWNDs reais, workspaces, snap, tiling e foco |
| `src/native_terminal_window.*` | UI do terminal baseada no ConPTY do NativeRuntime |
| `src/native_files_window.*` | arquivos Windows e WSL |
| `src/native_apps_window.*` | catálogo detalhado de aplicativos Windows/CloudOS |
| `src/native_process_window.*` | processos Windows |
| `src/native_run_window.*` | diálogo Executar |
| `src/native_notepad_window.*` | editor de texto nativo |
| `src/native_calculator_window.*` | calculadora nativa |
| `src/native_settings_window.*` | configurações persistentes em `HKCU\\Software\\CloudOS\\Native` |
| `src/native_system_monitor_window.*` | monitor de recursos |
| `src/native_system_stats.*` | coleta de telemetria do Windows; nunca deve inventar métricas |
| `src/native_env_doctor_window.*` | diagnóstico do runtime/ConPTY/WSL/ambiente |
| `src/native_start_menu_mru.h` | persistência local de frequência/recência de apps |
| `src/runtime_bootstrap.cpp` | bootstrap/validação do NativeRuntime |

Arquivos vazios que fingiam implementar taskbar/start/dash foram removidos do build e da árvore. Novos módulos só devem ser criados quando tiverem implementação real ou um contrato explicitamente marcado como provisório.

## Identidade visual vs. produto

`AETHER` é somente o nome interno da linguagem visual glassmorphic criada durante a migração. Textos públicos, apps, armazenamento e recursos pertencem ao **CloudOS**. Não renomear funcionalidades para nomes fictícios que escondam o que elas realmente executam.

Exemplos:

- Terminal = Terminal CloudOS/ConPTY.
- WSL / Kali = WSL real com a distribuição configurada pelo usuário.
- Disco Local = volume Windows real.
- CloudOS Drive deve manter sua própria semântica e não ser tratado como sinônimo automático de `C:\\`.

## Ciclo de vida

A ordem de inicialização é:

1. Common Controls Win32.
2. COM STA.
3. GDI+.
4. Desktop nativo.
5. NativeWindowManager + observador de HWNDs.
6. Configurações persistidas.
7. Hotkeys e timers.

A ordem de shutdown é inversa: timers/hotkeys -> WindowManager -> desktop -> GDI+ -> COM.

## Hotkeys do shell

O namespace padrão é `Ctrl+Alt` para não sequestrar atalhos `Alt` usados por aplicativos Windows:

- `Ctrl+Alt+Enter`: Terminal.
- `Ctrl+Alt+K`: WSL.
- `Ctrl+Alt+E`: Arquivos.
- `Ctrl+Alt+A`: Aplicativos.
- `Ctrl+Alt+P`: Monitor do Sistema.
- `Ctrl+Alt+R`: Executar.
- `Ctrl+Alt+T`: Tiling.
- `Ctrl+Alt+F`: Floating da janela ativa.
- `Ctrl+Alt+J/H`: próxima/anterior.
- `Ctrl+Alt+M/Z/Q`: minimizar/maximizar/fechar.
- `Ctrl+Alt+Setas`: snap.
- `Ctrl+Alt+1..4`: trocar workspace.
- `Ctrl+Alt+Shift+1..4`: mover janela ativa para workspace.
- `Ctrl+Alt+X`: sair do CloudOS.

## Regras para agentes/IA

Antes de alterar o NativeShell:

1. leia este arquivo;
2. leia o módulo envolvido e o `native_window_manager` antes de mexer no lifecycle de janelas;
3. preserve HWNDs reais de programas externos;
4. não invente telemetria, clima, calendário, saúde ou estado do sistema;
5. não troque uma função real por mock visual;
6. mantenha a UI separada de execução/processos sempre que possível;
7. não apague o legado do CloudOS até a paridade nativa ser comprovada.

Mudanças de UI devem preservar a capacidade de abrir, mover, minimizar, maximizar, fechar, snapar e trocar de workspace com programas Windows reais.

## Validação mínima

```bat
scripts\native\build-cloudos-native.cmd Release
Iniciar CloudOS Nativo.cmd
```

Depois validar manualmente pelo menos:

- Explorer;
- Notepad;
- CMD/PowerShell;
- navegador instalado;
- Task Manager;
- terminal ConPTY;
- WSL;
- snap e tiling;
- workspaces 1-4;
- pesquisa/launcher;
- encerramento e reinício do shell sem matar apps Windows indevidamente.

CI verde prova compilação/integração, não substitui o teste visual e interativo em uma sessão Windows real.
