# CloudOS Flutter Shell V21 — Refactor Status

## Base

- base branch: `work/system-broker-v21`
- base commit: `264a63c281f04039ec1df239fb356d7636a40ac5`
- work branch: `refactor/v21-modular-ai`
- validation PR: `#41`

## Problema inicial

A camada Flutter tinha poucas unidades grandes, o que obrigava agentes a carregar contexto demais para mudanças pequenas.

Maiores concentrações observadas na base:

- `lib/widgets/files_window.dart`: 754 linhas.
- `lib/widgets/start_panel.dart`: 504 linhas.
- `lib/widgets/cloud_taskbar.dart`: 395 linhas.
- `lib/widgets/quick_settings_panel.dart`: 311 linhas.
- `lib/widgets/notification_center.dart`: 227 linhas.
- `lib/shell/cloudos_shell.dart`: shell state/orchestration misturado com wallpaper, desktop icons e desktop status.
- `lib/services/cloudos_bridge.dart`: MethodChannel misturado com parsing, resolução de ícones e fixtures de preview.
- `lib/models/shell_models.dart`: quatro famílias de modelos no mesmo arquivo.

## Resultado estrutural

### Bootstrap

`lib/main.dart` contém somente bindings + `runApp`, mantendo `export 'app/cloudos_app.dart'` por compatibilidade com callers/testes.

`lib/app/cloudos_app.dart` contém o `MaterialApp`.

### Shell

Extraído de `cloudos_shell.dart`:

- `shell/widgets/desktop_wallpaper.dart`
- `shell/widgets/desktop_icons.dart`
- `shell/widgets/desktop_status.dart`

A shell permanece responsável pela orquestração de estado, workspaces, atalhos e surfaces abertas.

### Files

O antigo arquivo de 754 linhas virou export de compatibilidade.

Implementação canônica:

- `features/files/presentation/files_window.dart` — 119 linhas.
- `features/files/presentation/widgets/files_title_bar.dart` — 131 linhas.
- `features/files/presentation/widgets/files_sidebar.dart` — 220 linhas.
- `features/files/presentation/widgets/files_toolbar.dart` — 116 linhas.
- `features/files/presentation/widgets/files_content.dart` — 328 linhas.

### Start

O antigo arquivo de 504 linhas virou export de compatibilidade.

Implementação canônica:

- `features/start/domain/start_app_filter.dart` — 31 linhas.
- `features/start/presentation/start_panel.dart` — 304 linhas.
- `features/start/presentation/widgets/start_app_views.dart` — 216 linhas.
- `features/start/presentation/widgets/start_footer.dart` — 88 linhas.

### Taskbar

O antigo arquivo de 395 linhas virou export de compatibilidade de 2 linhas.

Implementação canônica:

- `features/taskbar/presentation/cloud_taskbar.dart` — 120 linhas.
- `features/taskbar/presentation/widgets/taskbar_task_button.dart` — 77 linhas.
- `features/taskbar/presentation/widgets/taskbar_workspace_switcher.dart` — 75 linhas.
- `features/taskbar/presentation/widgets/taskbar_system_tray.dart` — 189 linhas.

### Quick Settings

O antigo arquivo de 311 linhas virou export de compatibilidade de 2 linhas.

Implementação canônica:

- `features/quick_settings/presentation/quick_settings_panel.dart` — 161 linhas.
- `features/quick_settings/presentation/widgets/quick_toggle_tile.dart` — 73 linhas.
- `features/quick_settings/presentation/widgets/quick_slider_row.dart` — 56 linhas.
- `features/quick_settings/presentation/widgets/quick_system_summary.dart` — 71 linhas.

Estados antigos `powerSaver` e `wslgDisplay`, que não participavam de UI nem comportamento, foram removidos.

### Notifications

O antigo arquivo de 227 linhas virou export de compatibilidade de 2 linhas.

Implementação canônica:

- `features/notifications/domain/notification_date_formatter.dart` — 27 linhas.
- `features/notifications/presentation/notification_center_panel.dart` — 139 linhas.
- `features/notifications/presentation/widgets/notification_card.dart` — 112 linhas.
- `features/notifications/presentation/widgets/notification_empty_state.dart` — 40 linhas.

### Models

`shell_models.dart` caiu de 98 linhas de implementação para um compatibility barrel de 5 linhas.

Modelos canônicos:

- `models/cloud_app.dart` — 27 linhas.
- `models/cloud_file_item.dart` — 25 linhas.
- `models/cloud_notification.dart` — 21 linhas.
- `models/cloud_system_snapshot.dart` — 21 linhas.

### Dart Native Bridge

`CloudOSBridge` foi reduzido e separado por responsabilidade:

- `services/cloudos_bridge.dart` — transporte MethodChannel + fallbacks.
- `services/bridge/cloud_app_mapper.dart` — conversão do payload nativo para `CloudApp`.
- `services/bridge/cloudos_preview_data.dart` — fixtures de preview.

Os contratos públicos `CloudOSBridge.previewApps`, `previewSnapshot`, `previewFiles` e `previewNotifications` foram preservados.

## Compatibilidade preservada

- `lib/widgets/files_window.dart` continua resolvendo `FilesWindow` via export.
- `lib/widgets/start_panel.dart` continua resolvendo `StartPanel` via export.
- `lib/widgets/cloud_taskbar.dart` continua resolvendo `CloudTaskbar` via export.
- `lib/widgets/quick_settings_panel.dart` continua resolvendo `QuickSettingsPanel` via export.
- `lib/widgets/notification_center.dart` continua resolvendo `NotificationCenterPanel` via export.
- `lib/models/shell_models.dart` continua expondo todos os tipos compartilhados antigos.
- `lib/main.dart` continua expondo `CloudOSApp` via export.
- MethodChannel continua `cloudos/native/v19`.
- nenhuma alteração foi feita no protocolo NamedPipe V21 ou no System Broker.

## Testes

- `test/shell_smoke_test.dart` continua sendo o smoke de apresentação/bridge existente.
- `test/modular_logic_test.dart` cobre filtro extraído do Start, data pt-BR do Notification Center e compatibilidade do barrel de modelos.

## Validação

O ambiente de edição atual não possui Flutter/Dart local, portanto não há alegação de validação local.

O primeiro lote deste PR foi validado no GitHub Actions em 2026-09-01:

- `CloudOS Flutter UI` — success.
- `CloudOS CI Baseline` — success.

Depois do segundo lote, o CI deve ser consultado novamente antes de merge.

Validação canônica: `.github/workflows/cloudos-flutter-ui.yml`. Ela cobre:

- build do System Broker V21;
- contratos/smokes/soak do broker;
- `flutter analyze --fatal-infos --fatal-warnings`;
- `flutter test`;
- `flutter build windows --release`.

## Escopo que não foi reorganizado

O lado nativo V21 já possui separação por `broker_server`, `protocol`, `event_bus`, `job_manager`, `app_service`, `system_service`, `wsl_service`, `security` e `diagnostics`, então não foi fragmentado apenas por tamanho.

A regra daqui para frente é modularização semântica, não redução artificial de LOC.
