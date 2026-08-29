# CloudOS NativeShell

Este diretório contém o shell nativo Windows do CloudOS. O executável final é `CloudOS.exe` e o runtime de suporte é `CloudOS.NativeRuntime.dll`.

## Regra de arquitetura

Aplicativos Windows externos **não são embutidos, reparentados, capturados ou renderizados dentro de uma superfície web**.

```text
programa.exe
  -> HWND top-level real do Windows
  -> NativeRuntime observa eventos de janela
  -> NativeWindowManager registra e gerencia o HWND
  -> CloudOS aplica foco, snap, tiling e workspace
```

`SetParent`, captura de frames, WebView2, React, Vite e Node não fazem parte do boot do NativeShell.

## Pesquisa antes de implementação

Toda feature nativa nova deve seguir `docs/native/RESEARCH_POLICY.md`.

Antes de criar um subsistema: pesquisar documentação oficial; procurar exemplos oficiais e projetos open source maduros; verificar licença; reaproveitar componentes nativos comprovados quando isso preservar a arquitetura; registrar a pesquisa em `docs/native/research/`; implementar e validar.

Referência atual do Files: `docs/native/research/FILES_NATIVE_SHELL_RESEARCH.md`.

## Arquivos / Files

O gerenciador de arquivos não recria mais o Explorer com uma tabela branca feita à mão.

Para caminhos Windows e WSL ele hospeda `CLSID_ExplorerBrowser`, componente COM nativo do Windows Shell, encapsulado em `native_shell_view_host.*`. Isso fornece a view real do Shell, incluindo ícones, seleção, ordenação, menus de contexto, drag-and-drop, travel log e integrações do próprio Windows. Não é WebView, HTML ou Chromium.

O CloudOS Drive continua deliberadamente fora dessa fronteira de mutação. Sua tela usa uma grade nativa de ícones grandes e todas as operações persistentes continuam passando por `NativeCloudOSDrive`, preservando validação de raiz, bloqueio de reparse points e lixeira transacional.

Arquitetura:

```text
CloudOSNativeFilesWindow
  +-- sidebar: Início / Desktop / Documentos / Downloads
  |            CloudOS Drive / Projetos / WSL / Disco / Lixeira
  +-- barra: Voltar / Avançar / Acima / Endereço / Atualizar
  +-- Windows/WSL -> NativeShellViewHost -> CLSID_ExplorerBrowser
  +-- CloudOS Drive -> grade de ícones -> NativeCloudOSDrive
  +-- fallback -> enumeração Win32, se o Shell COM estiver indisponível
```

O Files é DPI-aware, usa o volume real do Windows e Known Folders, e mantém o conteúdo como área dominante da janela.

## Módulos ativos

| Arquivo | Responsabilidade |
| --- | --- |
| `src/main.cpp` | lifecycle do shell, COM/GDI+, timers, hotkeys e integração com WindowManager |
| `src/native_desktop_window.*` | desktop CloudOS, busca, widgets reais, workspaces e task switcher |
| `src/native_window_manager.*` | HWNDs reais, workspaces, snap, tiling e foco |
| `src/native_app_launcher.*` | roteamento central de apps internos, Windows, URI e WSL |
| `src/native_terminal_window.*` | terminal ConPTY |
| `src/native_cloudos_drive.*` | armazenamento isolado e seguro do CloudOS |
| `src/native_cloudos_trash_window.*` | lixeira transacional do CloudOS Drive |
| `src/native_shell_view_host.*` | host COM do Windows Shell para Windows/WSL |
| `src/native_files_window.cpp` | criação, layout, sidebar e estrutura visual do Files |
| `src/native_files_navigation.cpp` | roteamento de navegação e histórico |
| `src/native_files_operations.cpp` | operações e conteúdo CloudOS Drive/fallback |
| `src/native_files_support.cpp` | ícones, DPI, pintura e message handling |
| `src/native_projects_window.*` | projetos em `CloudOS Drive\Home\Projects` |
| `src/native_system_monitor_window.*` | monitor de recursos |
| `src/native_env_doctor_window.*` | diagnóstico do ambiente |
| `src/native_shell_platform.*` | Known/Windows paths e formatação local |

## CloudOS Drive

O CloudOS Drive não é sinônimo de `C:\`. A raiz padrão é `%LOCALAPPDATA%\CloudOS\Drive`, com `Home`, `Desktop`, `Documents`, `Downloads`, `Projects`, `Shared`, `Apps/windows`, `Apps/linux` e `.cloudos-system/trash`.

A camada nativa valida segmentos, impede escape da raiz e bloqueia reparse points nas operações protegidas. A lixeira persiste conteúdo e metadados para restauração.

## Regras para agentes/IA

1. leia este README e `docs/native/RESEARCH_POLICY.md`;
2. pesquise antes de implementar uma função nova;
3. registre referências e licenças;
4. preserve HWNDs reais de programas externos;
5. não reintroduza WebView/React/Node no boot nativo;
6. não invente telemetria ou estado do sistema;
7. mantenha CloudOS Drive diferente do disco do Windows;
8. preserve fallback quando uma API nativa opcional puder falhar;
9. não apague o legado até a paridade nativa ser comprovada.

## Hotkeys

O shell usa `Ctrl+Alt` para não sequestrar atalhos comuns dos apps: Space busca; Enter terminal; K WSL; E Arquivos; A Aplicativos; P Monitor; R Executar; T tiling; F floating; J/H foco; M/Z/Q minimizar/maximizar/fechar; setas snap; 1..4 workspaces; Shift+1..4 mover janela; X sair.

## Validação mínima

```bat
scripts\native\build-cloudos-native.cmd Release
Iniciar CloudOS Nativo.cmd
```

Depois validar visualmente: Windows/WSL no Shell view, CloudOS Drive na grade, sidebar, histórico, address bar, criar/renomear/excluir, lixeira, drag-and-drop/context menu do Shell, DPI, workspaces, snap/tiling e shutdown sem matar apps externos indevidamente.

CI verde prova compilação e integração. O teste visual em uma sessão Windows real continua obrigatório antes de declarar paridade.
