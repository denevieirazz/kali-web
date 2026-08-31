# CloudOS Native — mapa do código

Este arquivo responde à pergunta: **“qual arquivo eu leio ou altero para mexer em X?”**

Não use nomes antigos de produto ou o frontend React para deduzir a arquitetura atual. Para o desktop, a fonte compilada é `desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj`.

## Cinco arquivos para entender o sistema

Se você acabou de chegar no projeto, leia primeiro:

1. `desktop/CloudOS.NativeShell/src/main_shell_v2.cpp` — entrypoint e composição do shell.
2. `desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj` — grafo compilado real.
3. `desktop/CloudOS.NativeRecovery/main.cpp` — Supervisor/recovery externo V11.
4. `scripts/native/CloudOS.Deployment.V13.psm1` — instalação/update/rollback de versões.
5. `scripts/native/CloudOS.ShellActivation.V14.psm1` — ativação opt-in do shell/rollback para estado anterior.

`desktop/CloudOS.NativeShell/src/main.cpp` existe na árvore por histórico, mas **não é o entrypoint compilado atual**. Não o trate como fonte de verdade e não o apague sem uma migração deliberada do projeto.

---

## 1. Orquestração, boot, health e lifecycle

| Arquivo | Responsabilidade |
|---|---|
| `main_shell_v2.cpp` | cria/coordena superfícies, serviços, message loop e shutdown |
| `runtime_bootstrap.cpp` | bootstrap do runtime DLL |
| `native_health_bootstrap_v9.h` | attach/readiness/heartbeat e graceful-exit compartilhado |
| `native_health_v9.h` | health V9 no shell |
| `native_lifecycle_v10.h` | checkpoints/revalidação V10 |
| `native_watchdog.cpp` | watchdog embutido; não compete quando `--supervised` |
| `native_session_recovery.*` | recuperação de sessão no processo do shell |

Quando mexer em boot ou shutdown, verifique também Supervisor V11 e single-instance. Não crie outro loop de recovery.

---

## 2. Desktop

| Arquivo | Responsabilidade |
|---|---|
| `native_desktop_window_v2.*` | janela Desktop autoritativa e interação principal |
| `native_desktop_surface.*` | desenho/modelo da superfície Desktop |
| `native_desktop_context_menu.*` | menu de contexto |
| `native_desktop_drop_target.*` | drag/drop |
| `native_wallpaper_manager.*` | wallpaper |
| `native_icon_renderer.*` | render/cache de ícones compartilhável |

Regra crítica: `WM_PAINT` deve desenhar estado já preparado. Não introduza enumeração de filesystem, `SHGetFileInfoW`, WMI, rede ou outras operações lentas no paint.

---

## 3. Taskbar, Start e shell chrome

| Arquivo | Responsabilidade |
|---|---|
| `native_taskbar_appbar_v4.*` | Taskbar/AppBar, grupos, pins, tray/clock geometry |
| `native_taskbar_hover_preview.*` | thumbnails/previews de hover |
| `native_start_menu_window.*` | Start nativo |
| `native_start_index.*` | indexação do Start |
| `native_search_engine.*` | busca |
| `native_quick_settings_window_v4.*` | Quick Settings |
| `native_notification_center.*` | Notification Center |
| `native_toast_overlay.*` | toasts first-party |
| `native_cloudos_tray.*` | tray first-party CloudOS |
| `native_task_switcher_window.*` | alternador de tarefas |

Os sufixos `v4`, `v2` etc. marcam contratos deliberadamente versionados; não são convite para criar `v5` só para evitar editar o módulo atual.

---

## 4. Window Manager, Snap e Workspaces

| Arquivo | Responsabilidade |
|---|---|
| `native_window_manager.*` | inventário/estado/eventos de HWND e workspaces |
| `native_window_manager_recovery.*` | recuperação específica do Window Manager |
| `native_window_manager_workspace_studio.*` | integração Window Manager ↔ Workspace Studio |
| `native_snap_assist.*` | Snap/geometry |
| `native_workspace_overview_window.*` | overview com previews DWM |
| `native_workspace_labels.*` | labels/identidade de workspace |
| `native_workspace_automation.*` | automações/regras |
| `native_workspace_studio_model.*` | estado/modelo Studio |
| `native_workspace_studio_service.*` | serviço residente Studio |
| `native_workspace_studio_window.*` | UI Studio |

Mudanças de janela devem preferir eventos de WinEvent/runtime em vez de polling global.

---

## 5. Session Continuity

| Arquivo | Responsabilidade |
|---|---|
| `native_session_continuity_model.*` | ledger/checkpoint model |
| `native_session_continuity_service.*` | persistência e restore conservador |
| `native_session_continuity_window.*` | UI do centro de continuidade |

A continuidade não substitui V13 rollback nem V14 rollback do shell. Cada camada possui estado diferente.

---

## 6. Control Plane e integração do sistema

| Arquivo | Responsabilidade |
|---|---|
| `native_control_plane_service.*` | estado/coordenação do System Center/Quick Settings |
| `native_system_control_backend.*` | boundary para controles reais do Windows |
| `native_system_control_window.*` | UI de controles do sistema |
| `native_system_monitor_window.*` | UI de monitoramento |
| `native_system_stats.*` | amostragem de estatísticas |
| `native_shell_platform.*` | helpers/boundary de plataforma |
| `native_shell_actions.*` | catálogo/execução das ações first-party |
| `native_shell_bridge.*` | bridge interna do shell |
| `native_shell_view_host.*` | host de views nativas |
| `native_shell_pins.*` | armazenamento/ações de pins |
| `native_appearance_manager.*` | appearance/tokens/configuração visual |
| `native_monitor_manager.*` | monitores/DPI/work areas |

Consultas lentas devem ser assíncronas ou amostradas fora do paint/UI hot path.

---

## 7. Files & Storage

| Arquivo | Responsabilidade |
|---|---|
| `native_files_window_v5.*` | janela Files first-party |
| `native_files_navigation_v5.*` | navegação/tabs/namespace |
| `native_files_support_v5.*` | suporte Shell/namespace |
| `native_files_state.*` | estado da janela/files |
| `native_files_style.*` | desenho/estilo Files |
| `native_files_operations.*` | operações do Files |
| `native_file_operations_files_v5.*` | integração do boundary de operações V5 |
| `native_file_operations_window.*` | UI de operações |
| `native_files_search_window.*` | busca limitada |
| `native_file_preview.*` | preview WIC/texto |

Files usa APIs Shell onde necessário. Não faça acesso a filesystem síncrono dentro de `WM_PAINT`.

---

## 8. Apps first-party

| Arquivo | Aplicativo/feature |
|---|---|
| `native_apps_window.*` | catálogo/launcher de Apps |
| `native_app_launcher_v3.*` | lançamento first-party/externo |
| `native_browser_window.*` | Navegador; WebView2 é permitido aqui |
| `native_terminal_window.*` | Terminal nativo |
| `native_notepad_window.*` | Notepad |
| `native_calculator_window.*` | Calculator |
| `native_projects_window.*` | Projects |
| `native_process_window.*` | Processos |
| `native_run_window.*` | Run |
| `native_env_doctor_window.*` | diagnóstico de ambiente |
| `native_cloudos_drive.*` | CloudOS Drive |
| `native_cloudos_trash_window.*` | Trash |

WebView2 no Browser não torna WebView2 autoridade do Desktop.

---

## 9. Native Runtime DLL

Diretório: `desktop/CloudOS.NativeRuntime`.

| Arquivo | Responsabilidade |
|---|---|
| `cloudos_native_runtime.*` | runtime exportado/base |
| `cloudos_native_terminal.*` | ConPTY/process terminal boundary |
| `cloudos_native_window_events.*` | WinEvent/HWND events |
| `cloudos_native_wsl.*` | integração WSL |

A DLL fornece capacidade; ela não é proprietária da UI do shell.

---

## 10. Supervisor / Recovery externo

Diretório: `desktop/CloudOS.NativeRecovery`.

| Arquivo | Responsabilidade |
|---|---|
| `main.cpp` | `CloudOS.Supervisor.exe`: launch, Ready/heartbeat, restart, graceful exit e Explorer fallback |
| `CloudOS.NativeRecovery.vcxproj` | projeto que hoje produz `CloudOS.Supervisor.exe` |

O nome da pasta é histórico. A autoridade atual é o Supervisor V11.

---

## 11. Contratos compartilhados

Diretório: `desktop/CloudOS.NativeCommon`.

Principais contratos:

- `native_supervisor_protocol_v11.h` — Supervisor↔Shell, incluindo layout compatível do health V9 e mensagens compartilhadas.

Alterar esse diretório pode quebrar mais de um binário. Tamanho, nome de mapping/event/window class/message e estrutura compartilhada são ABI/protocolo, não detalhes internos.

---

## 12. Scripts nativos por fase

### Build/proveniência/release

- `build-cloudos-native.cmd`
- `get-native-build-fingerprint.ps1`
- `write-native-build-manifest.ps1`
- `verify-native-build-manifest.ps1`
- `get-native-build-status.ps1`
- `package-cloudos-native.ps1`
- `start-cloudos-native.cmd`

### Contratos

- `test-native-contract-suite.ps1` — entrypoint único da suite.
- `test-*-contract.ps1` — contrato específico por feature/marco.

### Runtime smokes

- V9: `run-native-soak-v9.ps1`
- V10: `run-native-lifecycle-smoke-v10.ps1`
- V11: `run-native-supervisor-smoke-v11.ps1`
- V12: `run-native-performance-smoke-v12.ps1` + `test-native-surfaces.ps1`
- V13: `run-native-deployment-smoke-v13.ps1`
- V14: `run-native-shell-activation-smoke-v14.ps1`

### Deploy V13

- `CloudOS.Deployment.V13.psm1`
- `install-cloudos-native-v13.ps1`
- `update-cloudos-native-v13.ps1`
- `rollback-cloudos-native-v13.ps1`
- `repair-cloudos-native-v13.ps1`
- `uninstall-cloudos-native-v13.ps1`
- `get-cloudos-deployment-status-v13.ps1`
- `start-cloudos-installed-v13.ps1`

### Ativação V14

- `CloudOS.ShellActivation.V14.psm1`
- `CloudOS.ShellEntry.V14.ps1`
- `activate-cloudos-shell-v14.ps1`
- `rollback-cloudos-shell-v14.ps1`
- `repair-cloudos-shell-v14.ps1`
- `get-cloudos-shell-status-v14.ps1`

### Legado/administrativo

- `configure-cloudos-shell-launcher.ps1` — controla o recurso Windows Shell Launcher/WESL; **não é V14 e não pertence ao fluxo normal de instalação/ativação**.

Veja `scripts/native/README.md` para detalhes.

---

## 13. Como decidir se criar um arquivo novo

Antes de criar um módulo:

1. procure pelo conceito no `CODEMAP` e no projeto `.vcxproj`;
2. abra header + cpp do dono atual;
3. confira se o estado já possui uma fonte de verdade;
4. adicione ao módulo existente se a responsabilidade for a mesma;
5. crie módulo novo somente para uma fronteira coesa e nomeável;
6. adicione contrato/teste correspondente.

A meta é reduzir duplicação conceitual, não apenas reduzir número de linhas por arquivo.
