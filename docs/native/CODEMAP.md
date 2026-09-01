# CloudOS Native — mapa do código

Este arquivo responde: **“qual arquivo eu leio ou altero para mexer em X?”**

Não use nomes antigos de produto ou o frontend React para deduzir a arquitetura atual. Para o desktop, a fonte compilada é `desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj`.

## Arquivos para entender o sistema

Leia primeiro:

1. `desktop/CloudOS.NativeShell/src/main_shell_v2.cpp` — entrypoint e composição do shell.
2. `desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj` — grafo compilado real.
3. `desktop/CloudOS.NativeRecovery/main.cpp` — Supervisor/recovery externo V11.
4. `scripts/native/CloudOS.Deployment.V13.psm1` — instalação/update/rollback de versões.
5. `scripts/native/CloudOS.ShellActivation.V14.psm1` — ativação opt-in do shell/rollback.
6. `desktop/CloudOS.NativeShell/src/native_integration_v16.*` — boundary Windows + Linux/WSL.
7. `desktop/CloudOS.NativeShell/src/native_integration_v16_launchers.h` — adapter Shell compartilhado para apps Linux.
8. `desktop/CloudOS.NativeShell/src/native_start_index.*` — Unified Start/Search V17.
9. `docs/native/UNIFIED_INTEGRATION_V16.md` e `UNIFIED_START_SEARCH_V17.md` — comportamento e limitações.

`desktop/CloudOS.NativeShell/src/main.cpp` existe por histórico, mas **não é o entrypoint compilado atual**.

---

## 1. Orquestração, boot, health e lifecycle

| Arquivo | Responsabilidade |
|---|---|
| `main_shell_v2.cpp` | cria/coordena superfícies, serviços, message loop e shutdown |
| `runtime_bootstrap.cpp` | bootstrap do runtime DLL |
| `native_health_bootstrap_v9.h` | attach/readiness/heartbeat/graceful exit |
| `native_health_v9.h` | health V9 no shell |
| `native_lifecycle_v10.h` | checkpoints/revalidação V10 |
| `native_watchdog.cpp` | watchdog embutido; não compete sob `--supervised` |
| `native_session_recovery.*` | recuperação de sessão no processo do shell |

Ao mexer em boot/shutdown, verifique também Supervisor V11 e single-instance.

---

## 2. Desktop

| Arquivo | Responsabilidade |
|---|---|
| `native_desktop_window_v2.*` | janela Desktop autoritativa, paint e input |
| `native_desktop_model_v12.h` | modelo event-driven: Desktop usuário + Public Desktop + launchers Linux V16/V17 |
| `native_desktop_surface.*` | superfície/modelo auxiliar |
| `native_desktop_context_menu.*` | menu de contexto |
| `native_desktop_drop_target.*` | drag/drop |
| `native_wallpaper_manager.*` | wallpaper |
| `native_icon_renderer.*`, `native_icon_cache_v12.h` | ícones/cache |

V17: `native_desktop_model_v12.h` observa Desktop/Start/WSL application directories por change notifications. WSL application changes podem pedir `reload_desktop` e `refresh_start_index` independentemente; não existe polling global.

A criação de `.lnk` Linux **não** pertence mais ao DesktopModel. Use `NativeIntegrationV16::EnsureLinuxLauncherShortcut()` definido em `native_integration_v16_launchers.h`.

Regra crítica: `WM_PAINT` só desenha estado preparado. Não introduza filesystem, `SHGetFileInfoW`, WMI, rede ou package discovery no paint.

---

## 3. Taskbar, Start e shell chrome

| Arquivo | Responsabilidade |
|---|---|
| `native_taskbar_appbar_v4.*` | Taskbar/AppBar, grupos, pins, tray/clock geometry |
| `native_taskbar_hover_preview.*` | thumbnails/previews |
| `native_start_menu_window.*` | Start nativo |
| `native_start_index.*` | **Unified Start/Search V17**: Start folders + AppsFolder + Linux V16 + Windows Search |
| `native_search_engine.*` | busca first-party CloudOS |
| `native_quick_settings_window_v4.*` | Quick Settings |
| `native_notification_center.*` | Notification Center |
| `native_toast_overlay.*` | toasts first-party |
| `native_cloudos_tray.*` | tray first-party |
| `native_task_switcher_window.*` | alternador de tarefas |

V17 não cria parser `.desktop` nem comando WSL dentro do Start. `native_start_index.*` consome `NativeIntegrationV16::EnumerateLinuxGuiApps()` e usa o launcher Shell compartilhado.

Sufixos de versão representam contratos deliberados; não crie `vN+1` apenas para evitar entender o módulo atual.

---

## 4. Window Manager, Snap e Workspaces

| Arquivo | Responsabilidade |
|---|---|
| `native_window_manager.*` | inventário/estado/eventos de HWND e workspaces |
| `native_window_manager_recovery.*` | recovery específico do Window Manager |
| `native_window_manager_workspace_studio.*` | Window Manager ↔ Workspace Studio |
| `native_snap_assist.*` | Snap/geometry |
| `native_workspace_overview_window.*` | overview + DWM previews |
| `native_workspace_labels.*` | identidade de workspace |
| `native_workspace_automation.*` | regras/automação |
| `native_workspace_studio_model.*` | modelo Studio |
| `native_workspace_studio_service.*` | serviço residente Studio |
| `native_workspace_studio_window.*` | UI Studio |

Apps WSLg aparecem como janelas Windows/DWM top-level e entram no mesmo Window Manager; não crie um gerenciador de janelas Linux paralelo.

---

## 5. Session Continuity

| Arquivo | Responsabilidade |
|---|---|
| `native_session_continuity_model.*` | ledger/checkpoint model |
| `native_session_continuity_service.*` | persistência/restore conservador |
| `native_session_continuity_window.*` | UI |

Continuity não substitui V13 rollback nem V14 rollback do shell.

---

## 6. Control Plane e integração do sistema

| Arquivo | Responsabilidade |
|---|---|
| `native_control_plane_service.*` | coordenação System Center/Quick Settings |
| `native_system_control_backend.*` | controles reais do Windows |
| `native_system_control_window.*` | UI de controles |
| `native_system_monitor_window.*` | monitoramento |
| `native_system_stats.*` | amostragem de métricas |
| `native_shell_platform.*` | helpers de plataforma |
| `native_shell_actions.*` | catálogo de ações first-party |
| `native_shell_bridge.*` | bridge interna |
| `native_shell_view_host.*` | host de views nativas |
| `native_shell_pins.*` | pins |
| `native_appearance_manager.*` | appearance |
| `native_monitor_manager.*` | monitores/DPI/work areas |
| `native_integration_v16.*` | autoridade para inventário Windows, WinGet, WSL distro/apps e package removal |
| `native_integration_v16_launchers.h` | launcher `.lnk` Linux compartilhado por Desktop/Start |

Não espalhe parsing de uninstall registry, `wsl.exe --list`, `gtk-launch`, WinGet ou mapeamento apt/snap/flatpak por outras surfaces. Se a responsabilidade é Windows↔Linux/package integration, comece em `native_integration_v16.*`.

---

## 7. Browser e downloads V16

| Arquivo | Responsabilidade |
|---|---|
| `native_browser_window.*` | WebView2; registra `DownloadStarting` e controla o destino |
| `native_folder_picker_v16.*` | picker first-party CloudOS de pastas Windows/WSL |
| `native_integration_v16.*` | known folders + `\\wsl.localhost` boundary |

Fluxo: WebView2 `DownloadStarting` → CloudOS Folder Picker → `ResultFilePath` → download WebView2.

O Browser é o único lugar normal onde WebView2 pertence ao shell. Não use essa integração para recolocar WebView2 como Desktop.

---

## 8. Files & Storage

| Arquivo | Responsabilidade |
|---|---|
| `native_files_window_v5.cpp` | janela Files first-party/chrome/sidebar |
| `native_files_navigation_v5.cpp` | navegação/tabs/namespace |
| `native_files_support_v5.cpp` | Shell/context menu/support |
| `native_files_state.*` | estado persistente |
| `native_files_style.*` | desenho |
| `native_files_operations.*` | operações |
| `native_file_operations_files_v5.*` | boundary operações V5 |
| `native_file_operations_window.*` | UI de operações |
| `native_files_search_window.*` | busca limitada |
| `native_file_preview.*` | preview WIC/texto |

Files já expõe `\\wsl.localhost\` no sidebar. Essa é a visão first-party do filesystem Linux dentro do CloudOS.

---

## 9. Apps first-party e gerenciador unificado V16/V17

| Arquivo | Aplicativo/feature |
|---|---|
| `native_apps_window.*` | Apps V16: Windows + Linux, abrir/instalar/remover/refresh |
| `native_integration_v16.*` | descoberta/execução/package boundary |
| `native_integration_v16_launchers.h` | adaptação de app Linux para alvo `.lnk` Shell |
| `native_start_index.*` | V17: expõe apps Linux no Start/Search usando a mesma boundary |
| `native_app_launcher_v3.*` | lançamento first-party/externo |
| `native_browser_window.*` | Browser |
| `native_terminal_window.*` | Terminal ConPTY usado por WinGet/apt/removal visível |
| `native_notepad_window.*` | Notepad |
| `native_calculator_window.*` | Calculator |
| `native_projects_window.*` | Projects |
| `native_process_window.*` | Processos |
| `native_run_window.*` | Run |
| `native_env_doctor_window.*` | diagnóstico |
| `native_cloudos_drive.*` | CloudOS Drive |
| `native_cloudos_trash_window.*` | Trash |

Windows inventory é read-only; uninstall/WinGet só executa após ação explícita. Linux GUI discovery lê `.desktop` e usa WSLg/`gtk-launch`. Start não duplica essa descoberta.

---

## 10. Native Runtime DLL

Diretório: `desktop/CloudOS.NativeRuntime`.

| Arquivo | Responsabilidade |
|---|---|
| `cloudos_native_runtime.*` | runtime exportado/base |
| `cloudos_native_terminal.*` | ConPTY/process boundary |
| `cloudos_native_window_events.*` | WinEvent/HWND events |
| `cloudos_native_wsl.*` | WSL API baixo nível |

A DLL fornece capacidade; não é proprietária da UI. V16/V17 usam a boundary existente onde a WSL API cobre a operação e `wsl.exe` somente dentro da integração para capacidades não expostas pelo runtime atual.

---

## 11. Supervisor / Recovery externo

Diretório: `desktop/CloudOS.NativeRecovery`.

| Arquivo | Responsabilidade |
|---|---|
| `main.cpp` | `CloudOS.Supervisor.exe`: launch, Ready/heartbeat, restart, graceful exit, Explorer fallback |
| `CloudOS.NativeRecovery.vcxproj` | produz Supervisor |

A autoridade continua V11; integração V16/V17 não cria recovery paralelo.

---

## 12. Contratos compartilhados

Diretório: `desktop/CloudOS.NativeCommon`.

- `native_supervisor_protocol_v11.h` — Supervisor↔Shell, health V9/mensagens compartilhadas.

Tamanho, nomes de mapping/event/window class/message e estruturas compartilhadas são protocolo/ABI.

---

## 13. Scripts nativos por fase

### Build/proveniência/release

- `build-cloudos-native.cmd`
- `get-native-build-fingerprint.ps1`
- `write-native-build-manifest.ps1`
- `verify-native-build-manifest.ps1`
- `get-native-build-status.ps1`
- `package-cloudos-native.ps1`
- `start-cloudos-native.cmd`

### Contratos

- `test-native-contract-suite.ps1` — entrypoint único.
- `test-*-contract.ps1` — contrato específico.
- V16: `test-unified-integration-v16-contract.ps1`.
- V17: `test-unified-start-search-v17-contract.ps1`.

### Runtime smokes

- V9: `run-native-soak-v9.ps1`
- V10: `run-native-lifecycle-smoke-v10.ps1`
- V11: `run-native-supervisor-smoke-v11.ps1`
- V12: `run-native-performance-smoke-v12.ps1` + `test-native-surfaces.ps1`
- V13: `run-native-deployment-smoke-v13.ps1`
- V14: `run-native-shell-activation-smoke-v14.ps1`
- V16: `run-native-integration-smoke-v16.ps1` — capability snapshot não destrutivo; não instala/remove software.
- V17: `run-native-unified-start-search-smoke-v17.ps1` — Start/Search boundary + Supervisor sanity, não destrutivo.

### Deploy V13

- `CloudOS.Deployment.V13.psm1`
- install/update/rollback/repair/uninstall/status/start scripts V13.

### Ativação V14

- `CloudOS.ShellActivation.V14.psm1`
- `CloudOS.ShellEntry.V14.ps1`
- activate/rollback/repair/status scripts V14.

### Legado/administrativo

- `configure-cloudos-shell-launcher.ps1` — Windows Shell Launcher/WESL; **não é V14**.

---

---

## 15. Flutter Shell & Native Bridge (V19 / V20)

| Arquivo / Pasta | Responsabilidade |
|---|---|
| `desktop/CloudOS.FlutterShell/lib/main.dart` | Ponto de entrada Flutter e montagem do tema / shell |
| `desktop/CloudOS.FlutterShell/lib/services/cloudos_bridge.dart` | Boundary Flutter ↔ C++ com typed methods e fallback de preview |
| `desktop/CloudOS.FlutterShell/lib/models/shell_models.dart` | Modelos de dados (`CloudApp`, `CloudSystemSnapshot`, etc.) |
| `desktop/CloudOS.FlutterShell/lib/shell/cloudos_shell.dart` | Shell orquestrador, atalhos globais, gerenciamento de janelas e painéis |
| `desktop/CloudOS.FlutterShell/lib/widgets/` | Componentes de apresentação (`start_panel`, `cloud_taskbar`, `files_window`, `quick_settings_panel`, `notification_center`) |
| `desktop/CloudOS.FlutterShell/native_bridge/cloudos_flutter_bridge_v20.*` | Implementação C++ do MethodChannel `cloudos/native/v19` |
| `desktop/CloudOS.FlutterShell/native_bridge/flutter_window.*` | Integração do FlutterViewController no Host Win32 |
| `desktop/CloudOS.FlutterShell/test/shell_smoke_test.dart` | Testes de widget e contratos de MethodChannel |
| `docs/native/FLUTTER_NATIVE_BRIDGE_V20.md` | Especificação completa da integração Flutter ↔ C++ |

---

## 16. System Broker & Event Bus (V21)

| Arquivo / Pasta | Responsabilidade |
|---|---|
| `desktop/CloudOS.SystemBroker/CloudOS.SystemBroker.vcxproj` | Projeto MSBuild do processo System Broker |
| `desktop/CloudOS.SystemBroker/src/broker_main.cpp` | Ponto de entrada, `--self-test`, `--diagnostics` e ciclo de vida |
| `desktop/CloudOS.SystemBroker/src/broker_server_v21.*` | Listener Named Pipe, mutex de sessão, router de mensagens |
| `desktop/CloudOS.SystemBroker/src/protocol_v21.*` | Parser/Serializer JSON UTF-8 e envelopes do Protocolo 21 |
| `desktop/CloudOS.SystemBroker/src/security_v21.*` | Resolução de SID/Sessão e descritor de segurança DACL explícito |
| `desktop/CloudOS.SystemBroker/src/event_bus_v21.*` | Barramento de eventos pub/sub, coalescing e controle de backpressure |
| `desktop/CloudOS.SystemBroker/src/job_manager_v21.*` | Fila de tarefas assíncronas com estados (`Queued`, `Running`, etc.) |
| `desktop/CloudOS.SystemBroker/src/app_service_v21.*` | Catálogo unificado de aplicativos e resolução segura de lançamento |
| `desktop/CloudOS.SystemBroker/src/system_service_v21.*` | Telemetria de hardware (bateria, rede, volume, brilho) |
| `desktop/CloudOS.SystemBroker/src/wsl_service_v21.*` | Enumeração de distros WSL e ambiente WSLg |
| `desktop/CloudOS.SystemBroker/src/diagnostics_v21.*` | Snapshot seguro de telemetria interna |
| `desktop/CloudOS.BrokerProbe/` | Ferramenta CLI de probe/teste de IPC do broker (`ping`, `snapshot`, `apps`) |
| `desktop/CloudOS.FlutterShell/native_bridge/cloudos_broker_client_v21.*` | Cliente IPC C++ no host Flutter conectando ao System Broker |
| `scripts/native/run-system-broker-smoke-v21.ps1` | Suite de smoke e geração do JSON de evidência do broker |
| `scripts/native/test-system-broker-v21-contract.ps1` | Validação de contratos arquiteturais e segurança |
| `scripts/native/test-system-broker-v21-soak.ps1` | Teste de estabilidade e ausência de vazamento de memória (120s) |
| `docs/native/SYSTEM_BROKER_V21.md` | Especificação completa do System Broker & Event Bus |
| `docs/native/SYSTEM_BROKER_SECURITY_V21.md` | Threat model e matriz de mitigação de segurança |

---
| `native_shell_view_host.*` | host de views nativas |
| `native_shell_pins.*` | pins |
| `native_appearance_manager.*` | appearance |
| `native_monitor_manager.*` | monitores/DPI/work areas |
| `native_integration_v16.*` | autoridade para inventário Windows, WinGet, WSL distro/apps e package removal |
| `native_integration_v16_launchers.h` | launcher `.lnk` Linux compartilhado por Desktop/Start |

Não espalhe parsing de uninstall registry, `wsl.exe --list`, `gtk-launch`, WinGet ou mapeamento apt/snap/flatpak por outras surfaces. Se a responsabilidade é Windows↔Linux/package integration, comece em `native_integration_v16.*`.

---

## 7. Browser e downloads V16

| Arquivo | Responsabilidade |
|---|---|
| `native_browser_window.*` | WebView2; registra `DownloadStarting` e controla o destino |
| `native_folder_picker_v16.*` | picker first-party CloudOS de pastas Windows/WSL |
| `native_integration_v16.*` | known folders + `\\wsl.localhost` boundary |

Fluxo: WebView2 `DownloadStarting` → CloudOS Folder Picker → `ResultFilePath` → download WebView2.

O Browser é o único lugar normal onde WebView2 pertence ao shell. Não use essa integração para recolocar WebView2 como Desktop.

---

## 8. Files & Storage

| Arquivo | Responsabilidade |
|---|---|
| `native_files_window_v5.cpp` | janela Files first-party/chrome/sidebar |
| `native_files_navigation_v5.cpp` | navegação/tabs/namespace |
| `native_files_support_v5.cpp` | Shell/context menu/support |
| `native_files_state.*` | estado persistente |
| `native_files_style.*` | desenho |
| `native_files_operations.*` | operações |
| `native_file_operations_files_v5.*` | boundary operações V5 |
| `native_file_operations_window.*` | UI de operações |
| `native_files_search_window.*` | busca limitada |
| `native_file_preview.*` | preview WIC/texto |

Files já expõe `\\wsl.localhost\` no sidebar. Essa é a visão first-party do filesystem Linux dentro do CloudOS.

---

## 9. Apps first-party e gerenciador unificado V16/V17

| Arquivo | Aplicativo/feature |
|---|---|
| `native_apps_window.*` | Apps V16: Windows + Linux, abrir/instalar/remover/refresh |
| `native_integration_v16.*` | descoberta/execução/package boundary |
| `native_integration_v16_launchers.h` | adaptação de app Linux para alvo `.lnk` Shell |
| `native_start_index.*` | V17: expõe apps Linux no Start/Search usando a mesma boundary |
| `native_app_launcher_v3.*` | lançamento first-party/externo |
| `native_browser_window.*` | Browser |
| `native_terminal_window.*` | Terminal ConPTY usado por WinGet/apt/removal visível |
| `native_notepad_window.*` | Notepad |
| `native_calculator_window.*` | Calculator |
| `native_projects_window.*` | Projects |
| `native_process_window.*` | Processos |
| `native_run_window.*` | Run |
| `native_env_doctor_window.*` | diagnóstico |
| `native_cloudos_drive.*` | CloudOS Drive |
| `native_cloudos_trash_window.*` | Trash |

Windows inventory é read-only; uninstall/WinGet só executa após ação explícita. Linux GUI discovery lê `.desktop` e usa WSLg/`gtk-launch`. Start não duplica essa descoberta.

---

## 10. Native Runtime DLL

Diretório: `desktop/CloudOS.NativeRuntime`.

| Arquivo | Responsabilidade |
|---|---|
| `cloudos_native_runtime.*` | runtime exportado/base |
| `cloudos_native_terminal.*` | ConPTY/process boundary |
| `cloudos_native_window_events.*` | WinEvent/HWND events |
| `cloudos_native_wsl.*` | WSL API baixo nível |

A DLL fornece capacidade; não é proprietária da UI. V16/V17 usam a boundary existente onde a WSL API cobre a operação e `wsl.exe` somente dentro da integração para capacidades não expostas pelo runtime atual.

---

## 11. Supervisor / Recovery externo

Diretório: `desktop/CloudOS.NativeRecovery`.

| Arquivo | Responsabilidade |
|---|---|
| `main.cpp` | `CloudOS.Supervisor.exe`: launch, Ready/heartbeat, restart, graceful exit, Explorer fallback |
| `CloudOS.NativeRecovery.vcxproj` | produz Supervisor |

A autoridade continua V11; integração V16/V17 não cria recovery paralelo.

---

## 12. Contratos compartilhados

Diretório: `desktop/CloudOS.NativeCommon`.

- `native_supervisor_protocol_v11.h` — Supervisor↔Shell, health V9/mensagens compartilhadas.

Tamanho, nomes de mapping/event/window class/message e estruturas compartilhadas são protocolo/ABI.

---

## 13. Scripts nativos por fase

### Build/proveniência/release

- `build-cloudos-native.cmd`
- `get-native-build-fingerprint.ps1`
- `write-native-build-manifest.ps1`
- `verify-native-build-manifest.ps1`
- `get-native-build-status.ps1`
- `package-cloudos-native.ps1`
- `start-cloudos-native.cmd`

### Contratos

- `test-native-contract-suite.ps1` — entrypoint único.
- `test-*-contract.ps1` — contrato específico.
- V16: `test-unified-integration-v16-contract.ps1`.
- V17: `test-unified-start-search-v17-contract.ps1`.

### Runtime smokes

- V9: `run-native-soak-v9.ps1`
- V10: `run-native-lifecycle-smoke-v10.ps1`
- V11: `run-native-supervisor-smoke-v11.ps1`
- V12: `run-native-performance-smoke-v12.ps1` + `test-native-surfaces.ps1`
- V13: `run-native-deployment-smoke-v13.ps1`
- V14: `run-native-shell-activation-smoke-v14.ps1`
- V16: `run-native-integration-smoke-v16.ps1` — capability snapshot não destrutivo; não instala/remove software.
- V17: `run-native-unified-start-search-smoke-v17.ps1` — Start/Search boundary + Supervisor sanity, não destrutivo.

### Deploy V13

- `CloudOS.Deployment.V13.psm1`
- install/update/rollback/repair/uninstall/status/start scripts V13.

### Ativação V14

- `CloudOS.ShellActivation.V14.psm1`
- `CloudOS.ShellEntry.V14.ps1`
- activate/rollback/repair/status scripts V14.

### Legado/administrativo

- `configure-cloudos-shell-launcher.ps1` — Windows Shell Launcher/WESL; **não é V14**.

---

---

## 15. Flutter Shell & Native Bridge (V19 / V20)

| Arquivo / Pasta | Responsabilidade |
|---|---|
| `desktop/CloudOS.FlutterShell/lib/main.dart` | Ponto de entrada Flutter e montagem do tema / shell |
| `desktop/CloudOS.FlutterShell/lib/services/cloudos_bridge.dart` | Boundary Flutter ↔ C++ com typed methods e fallback de preview |
| `desktop/CloudOS.FlutterShell/lib/models/shell_models.dart` | Modelos de dados (`CloudApp`, `CloudSystemSnapshot`, etc.) |
| `desktop/CloudOS.FlutterShell/lib/shell/cloudos_shell.dart` | Shell orquestrador, atalhos globais, gerenciamento de janelas e painéis |
| `desktop/CloudOS.FlutterShell/lib/widgets/` | Componentes de apresentação (`start_panel`, `cloud_taskbar`, `files_window`, `quick_settings_panel`, `notification_center`) |
| `desktop/CloudOS.FlutterShell/native_bridge/cloudos_flutter_bridge_v20.*` | Implementação C++ do MethodChannel `cloudos/native/v19` |
| `desktop/CloudOS.FlutterShell/native_bridge/flutter_window.*` | Integração do FlutterViewController no Host Win32 |
| `desktop/CloudOS.FlutterShell/test/shell_smoke_test.dart` | Testes de widget e contratos de MethodChannel |
| `docs/native/FLUTTER_NATIVE_BRIDGE_V20.md` | Especificação completa da integração Flutter ↔ C++ |

---

## 16. System Broker & Event Bus (V21)

| Arquivo / Pasta | Responsabilidade |
|---|---|
| `desktop/CloudOS.SystemBroker/CloudOS.SystemBroker.vcxproj` | Projeto MSBuild do processo System Broker |
| `desktop/CloudOS.SystemBroker/src/broker_main.cpp` | Ponto de entrada, `--self-test`, `--diagnostics` e ciclo de vida |
| `desktop/CloudOS.SystemBroker/src/broker_server_v21.*` | Listener Named Pipe, mutex de sessão, router de mensagens |
| `desktop/CloudOS.SystemBroker/src/protocol_v21.*` | Parser/Serializer JSON UTF-8 e envelopes do Protocolo 21 |
| `desktop/CloudOS.SystemBroker/src/security_v21.*` | Resolução de SID/Sessão e descritor de segurança DACL explícito |
| `desktop/CloudOS.SystemBroker/src/event_bus_v21.*` | Barramento de eventos pub/sub, coalescing e controle de backpressure |
| `desktop/CloudOS.SystemBroker/src/job_manager_v21.*` | Fila de tarefas assíncronas com estados (`Queued`, `Running`, etc.) |
| `desktop/CloudOS.SystemBroker/src/app_service_v21.*` | Catálogo unificado de aplicativos e resolução segura de lançamento |
| `desktop/CloudOS.SystemBroker/src/system_service_v21.*` | Telemetria de hardware (bateria, rede, volume, brilho) |
| `desktop/CloudOS.SystemBroker/src/wsl_service_v21.*` | Enumeração de distros WSL e ambiente WSLg |
| `desktop/CloudOS.SystemBroker/src/diagnostics_v21.*` | Snapshot seguro de telemetria interna |
| `desktop/CloudOS.BrokerProbe/` | Ferramenta CLI de probe/teste de IPC do broker (`ping`, `snapshot`, `apps`) |
| `desktop/CloudOS.FlutterShell/native_bridge/cloudos_broker_client_v21.*` | Cliente IPC C++ no host Flutter conectando ao System Broker |
| `scripts/native/run-system-broker-smoke-v21.ps1` | Suite de smoke e geração do JSON de evidência do broker |
| `scripts/native/test-system-broker-v21-contract.ps1` | Validação de contratos arquiteturais e segurança |
| `scripts/native/test-system-broker-v21-soak.ps1` | Teste de estabilidade e ausência de vazamento de memória (120s) |
| `docs/native/SYSTEM_BROKER_V21.md` | Especificação completa do System Broker & Event Bus |
| `docs/native/SYSTEM_BROKER_SECURITY_V21.md` | Threat model e matriz de mitigação de segurança |

---

## 17. Como decidir se criar arquivo novo

1. procure no `CODEMAP` e `.vcxproj`;
2. abra header + cpp do dono atual;
4. estenda o módulo existente se a responsabilidade for a mesma;
5. crie módulo novo apenas para uma fronteira coesa;
6. adicione contrato/teste;
7. preserve V9–V17 invariantes aplicáveis.

A meta é reduzir duplicação conceitual, não apenas reduzir número de linhas por arquivo.
