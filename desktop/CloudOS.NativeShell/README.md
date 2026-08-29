# CloudOS NativeShell

Este diretorio contem o shell nativo Windows do CloudOS. O executavel final e `CloudOS.exe` e o runtime de suporte e `CloudOS.NativeRuntime.dll`.

## Regra de arquitetura

Aplicativos Windows externos **nao sao embutidos, reparentados, capturados ou renderizados dentro de uma superficie web**. O modelo normal e:

```text
programa.exe
  -> HWND top-level real do Windows
  -> NativeRuntime observa eventos de janela
  -> NativeWindowManager registra e gerencia o HWND
  -> CloudOS aplica foco, snap, tiling e workspace
```

`SetParent`, captura de frames, WebView2, React, Vite e Node nao fazem parte do boot do NativeShell.

## Modulos ativos

| Arquivo | Responsabilidade |
| --- | --- |
| `src/main.cpp` | ciclo de vida do shell, COM/GDI+, timers, hotkeys e integracao entre desktop e WindowManager |
| `src/native_desktop_window.*` | superficie AETHER do CloudOS, busca, widgets verdadeiros, workspaces e task switcher |
| `src/native_theme.h` | contratos de UI, catalogo de apps e design tokens; AETHER e linguagem visual, nao nome do produto |
| `src/native_icon_renderer.*` | desenho GDI+ de icones e superficies |
| `src/native_search_engine.*` | filtro local do catalogo de apps |
| `src/native_app_launcher.*` | roteamento central de apps internos, Windows, URI do Shell e WSL |
| `src/native_window_manager.*` | descoberta e gerenciamento de HWNDs reais, workspaces, snap, tiling e foco |
| `src/native_terminal_window.*` | UI do terminal baseada no ConPTY do NativeRuntime |
| `src/native_files_window.*` | arquivos Windows e WSL |
| `src/native_apps_window.*` | catalogo detalhado de aplicativos Windows/CloudOS |
| `src/native_process_window.*` | processos Windows |
| `src/native_run_window.*` | dialogo Executar |
| `src/native_notepad_window.*` | editor de texto nativo |
| `src/native_calculator_window.*` | calculadora nativa |
| `src/native_settings_window.*` | configuracoes persistentes em `HKCU\Software\CloudOS\Native` |
| `src/native_shell_platform.*` | caminhos/volume do Windows e formatacao local de data/hora |
| `src/native_system_monitor_window.*` | monitor de recursos |
| `src/native_system_stats.*` | telemetria do Windows com flags de disponibilidade; nunca inventa metricas |
| `src/native_env_doctor_window.*` | diagnostico do runtime/ConPTY/WSL/ambiente |
| `src/native_start_menu_mru.h` | frequencia/recencia persistida em LocalAppData usando Known Folders e troca atomica |
| `src/runtime_bootstrap.cpp` | bootstrap/validacao do NativeRuntime |

Arquivos vazios que fingiam implementar taskbar/start/dash foram removidos do build. Novos modulos so entram quando tiverem implementacao real ou contrato explicitamente provisorio.

## Desktop nativo

O desktop atual nao e mais apenas um mock visual.

- busca digitavel com teclado;
- `Ctrl+Alt+Space` leva foco direto para a busca;
- `Enter` abre o item selecionado;
- setas navegam pelos resultados;
- `Esc` limpa a busca;
- acesso rapido usa MRU real persistido;
- atividade recente mostra contagem real de aberturas;
- workspaces 1-4 podem ser clicados;
- janelas HWND reais do workspace atual aparecem como tarefas clicaveis;
- o dock abre apps reais;
- CPU/RAM/disco vem das APIs do Windows e mostra `--` quando a amostra nao existe;
- data/hora usa `GetDateFormatEx` / `GetTimeFormatEx` e o locale do usuario;
- o widget de clima nao fabrica temperatura: ele apenas abre a previsao;
- status mostra ABI real do NativeRuntime, workspace, numero de HWNDs, tiling e uptime;
- o status abre o Native Environment Doctor.

## Persistencia de atividade

`native_start_menu_mru.h` grava em:

```text
%LOCALAPPDATA%\CloudOS\start_mru.dat
```

A pasta e resolvida por `SHGetKnownFolderPath(FOLDERID_LocalAppData)`. A gravacao e feita em arquivo temporario e promovida com `MoveFileExW(..., MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)` para reduzir risco de arquivo parcialmente escrito.

IDs alternativos como `wsl`, `comms`, `mail` e `more` sao normalizados para IDs canonicos antes de serem persistidos.

## Identidade visual vs. produto

`AETHER` e somente o nome interno da linguagem visual glassmorphic criada durante a migracao. Textos publicos, apps, armazenamento e recursos pertencem ao **CloudOS**.

Nao renomear funcionalidades para nomes ficticios que escondam o que realmente executam.

Exemplos:

- Terminal = Terminal CloudOS/ConPTY.
- WSL / Kali = WSL real com a distribuicao configurada pelo usuario.
- Disco do Sistema = volume onde o Windows esta instalado, sem assumir `C:`.
- CloudOS Drive deve manter sua propria semantica e nao ser tratado como sinonimo automatico do volume do Windows.

## Ciclo de vida

A ordem de inicializacao e:

1. Common Controls Win32.
2. COM STA.
3. GDI+.
4. Desktop nativo.
5. NativeWindowManager + observador de HWNDs.
6. Configuracoes persistidas.
7. Hotkeys e timers.

A ordem de shutdown e inversa: timers/hotkeys -> WindowManager -> desktop -> GDI+ -> COM.

## Hotkeys do shell

O namespace padrao e `Ctrl+Alt` para nao sequestrar atalhos `Alt` usados pelos aplicativos Windows:

- `Ctrl+Alt+Space`: foco na busca.
- `Ctrl+Alt+Enter`: Terminal.
- `Ctrl+Alt+K`: WSL.
- `Ctrl+Alt+E`: Arquivos.
- `Ctrl+Alt+A`: Aplicativos.
- `Ctrl+Alt+P`: Monitor do Sistema.
- `Ctrl+Alt+R`: Executar.
- `Ctrl+Alt+T`: Tiling.
- `Ctrl+Alt+F`: Floating da janela ativa.
- `Ctrl+Alt+J/H`: proxima/anterior.
- `Ctrl+Alt+M/Z/Q`: minimizar/maximizar/fechar.
- `Ctrl+Alt+Setas`: snap.
- `Ctrl+Alt+1..4`: trocar workspace.
- `Ctrl+Alt+Shift+1..4`: mover janela ativa para workspace.
- `Ctrl+Alt+X`: sair do CloudOS.

## Regras para agentes/IA

Antes de alterar o NativeShell:

1. leia este arquivo;
2. leia o modulo envolvido e o `native_window_manager` antes de mexer no lifecycle de janelas;
3. preserve HWNDs reais de programas externos;
4. nao invente telemetria, clima, calendario, saude ou estado do sistema;
5. nao troque uma funcao real por mock visual;
6. mantenha UI separada de execucao/processos;
7. normalize aliases para IDs canonicos antes de persistir atividade;
8. use Known Folders em codigo novo em vez de CSIDL/`SHGetFolderPath`;
9. nao apague o legado do CloudOS ate a paridade nativa ser comprovada.

Mudancas de UI devem preservar a capacidade de abrir, focar, mover, minimizar, maximizar, fechar, snapar e trocar de workspace com programas Windows reais.

## Gate automatico

Antes do build, o workflow executa:

```powershell
./scripts/native/test-cloudos-native-shell-contracts.ps1
```

O gate falha se dados sinteticos conhecidos voltarem para o desktop, se o launcher voltar a assumir `C:`, se MRU deixar de usar Known Folders/troca atomica ou se placeholders vazios retornarem ao build.

## Validacao minima

```bat
scripts\native\build-cloudos-native.cmd Release
Iniciar CloudOS Nativo.cmd
```

Depois validar manualmente pelo menos:

- busca por mouse e `Ctrl+Alt+Space`;
- Explorer;
- Notepad;
- CMD/PowerShell;
- navegador instalado;
- terminal ConPTY;
- WSL;
- task switcher;
- workspaces 1-4;
- snap e tiling;
- atividade recente/MRU;
- widgets de data, desempenho e diagnostico;
- encerramento e reinicio do shell sem matar apps Windows indevidamente.

CI verde prova compilacao/integracao. O teste visual e interativo em uma sessao Windows real continua obrigatorio antes de declarar paridade.
