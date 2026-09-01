# CloudOS Flutter Shell V21 — Refactor Status

## Base

- base branch: `work/system-broker-v21`
- base commit: `264a63c281f04039ec1df239fb356d7636a40ac5`
- work branch: `refactor/v21-modular-ai`
- validation PR: `#41`

## Problema inicial

A camada Flutter tinha poucas unidades grandes, o que obrigava agentes a carregar contexto demais para mudanças pequenas.

Maiores concentrações observadas na base:

- `lib/widgets/files_window.dart`: 754 linhas em um único arquivo.
- `lib/widgets/start_panel.dart`: 504 linhas em um único arquivo.
- `lib/shell/cloudos_shell.dart`: shell state/orchestration misturado com wallpaper, desktop icons e desktop status.
- `lib/services/cloudos_bridge.dart`: MethodChannel misturado com parsing, resolução de ícones e fixtures de preview.

## Resultado estrutural

### Bootstrap

`lib/main.dart` agora contém somente bindings + `runApp`, mantendo `export 'app/cloudos_app.dart'` por compatibilidade com callers/testes.

`lib/app/cloudos_app.dart` contém o `MaterialApp`.

### Shell

Extraído de `cloudos_shell.dart`:

- `shell/widgets/desktop_wallpaper.dart`
- `shell/widgets/desktop_icons.dart`
- `shell/widgets/desktop_status.dart`

A shell permanece responsável pela orquestração de estado, workspaces, atalhos e surfaces abertas.

### Files

O antigo arquivo de 754 linhas virou export de compatibilidade de 3 linhas.

Implementação canônica:

- `features/files/presentation/files_window.dart` — 119 linhas.
- `features/files/presentation/widgets/files_title_bar.dart` — 131 linhas.
- `features/files/presentation/widgets/files_sidebar.dart` — 220 linhas.
- `features/files/presentation/widgets/files_toolbar.dart` — 116 linhas.
- `features/files/presentation/widgets/files_content.dart` — 328 linhas.

### Start

O antigo arquivo de 504 linhas virou export de compatibilidade de 3 linhas.

Implementação canônica:

- `features/start/domain/start_app_filter.dart` — 31 linhas.
- `features/start/presentation/start_panel.dart` — 304 linhas.
- `features/start/presentation/widgets/start_app_views.dart` — 216 linhas.
- `features/start/presentation/widgets/start_footer.dart` — 88 linhas.

### Dart Native Bridge

`CloudOSBridge` foi reduzido e separado por responsabilidade:

- `services/cloudos_bridge.dart` — transporte MethodChannel + fallbacks.
- `services/bridge/cloud_app_mapper.dart` — conversão do payload nativo para `CloudApp`.
- `services/bridge/cloudos_preview_data.dart` — fixtures de preview.

Os contratos públicos `CloudOSBridge.previewApps`, `previewSnapshot`, `previewFiles` e `previewNotifications` foram preservados.

## Compatibilidade preservada

- `lib/widgets/files_window.dart` continua resolvendo `FilesWindow` via export.
- `lib/widgets/start_panel.dart` continua resolvendo `StartPanel` via export.
- `lib/main.dart` continua expondo `CloudOSApp` via export.
- MethodChannel continua `cloudos/native/v19`.
- nenhuma alteração foi feita no protocolo NamedPipe V21 ou no System Broker.

## Validação

O ambiente de edição atual não possui Flutter/Dart local, portanto não há alegação de validação local.

Validação canônica: `.github/workflows/cloudos-flutter-ui.yml`, disparada pelo PR #41. Ela cobre:

- build do System Broker V21;
- contratos/smokes/soak do broker;
- `flutter analyze --fatal-infos --fatal-warnings`;
- `flutter test`;
- `flutter build windows --release`.

Status deve ser consultado no PR/Actions antes de merge.

## Próximos candidatos, sem urgência estrutural equivalente

Ainda existem componentes médios em `lib/widgets/` (`cloud_taskbar.dart`, `quick_settings_panel.dart`, `notification_center.dart`). Eles devem ser divididos somente quando a separação produzir boundaries semânticas reais; não criar fragmentação apenas para reduzir LOC.

O lado nativo V21 já possui separação por `broker_server`, `protocol`, `event_bus`, `job_manager`, `app_service`, `system_service`, `wsl_service`, `security` e `diagnostics`, então não foi reorganizado nesta etapa.
