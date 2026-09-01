# CloudOS Flutter Shell V21 — Codebase Map

## Objetivo

Mapa curto para localizar a responsabilidade correta sem carregar todo o Flutter Shell no contexto.

## Entry points

| Área | Caminho | Leia quando |
|---|---|---|
| bootstrap | `lib/main.dart` | startup Dart / export público de `CloudOSApp` |
| app root | `lib/app/cloudos_app.dart` | MaterialApp, theme e root shell |
| shell | `lib/shell/cloudos_shell.dart` | janelas abertas, workspaces, atalhos e painéis transitórios |
| desktop visuals | `lib/shell/widgets/` | wallpaper, ícones e status do desktop |

## Features

### Files

Canônico: `lib/features/files/presentation/files_window.dart`

Componentes:

- `widgets/files_title_bar.dart` — drag, minimize, maximize visual e close.
- `widgets/files_sidebar.dart` — modelo/itens da navegação lateral e UI da sidebar.
- `widgets/files_toolbar.dart` — navegação visual, breadcrumb, filtro e alternância grid/list.
- `widgets/files_content.dart` — grid/list/empty state/status bar.

Compatibilidade: `lib/widgets/files_window.dart` é apenas export; não adicionar implementação lá.

### Start / Search

Canônico: `lib/features/start/presentation/start_panel.dart`

Componentes:

- `domain/start_app_filter.dart` — filtros e busca pura de `CloudApp`.
- `presentation/widgets/start_app_views.dart` — cards fixados, recentes e resultados.
- `presentation/widgets/start_footer.dart` — sessão/ações do rodapé.

Compatibilidade: `lib/widgets/start_panel.dart` é apenas export.

## Shared presentation

- `lib/core/cloudos_theme.dart` — cores/theme/tokens compartilhados.
- `lib/models/shell_models.dart` — `CloudApp`, `CloudSystemSnapshot`, `CloudFileItem`, notificações e enums de apresentação.
- `lib/widgets/glass_surface.dart` — superfície visual reutilizável.
- `lib/widgets/cloud_taskbar.dart` — taskbar.
- `lib/widgets/quick_settings_panel.dart` — quick settings.
- `lib/widgets/notification_center.dart` — notification center.

## Native boundary

Dart não fala Named Pipe diretamente.

```text
lib/services/cloudos_bridge.dart
  -> MethodChannel cloudos/native/v19
  -> native_bridge/cloudos_flutter_bridge_v20.*
  -> native_bridge/cloudos_broker_client_v21.*
  -> ../CloudOS.SystemBroker/src/
```

System Broker V21 já possui módulos próprios para servidor, protocolo, event bus, jobs, apps, sistema, WSL, segurança e diagnósticos. Não duplicar essas responsabilidades no Flutter.

## Onde começar por tarefa

| Tarefa | Abra primeiro |
|---|---|
| alterar startup Flutter | `lib/main.dart`, `lib/app/cloudos_app.dart` |
| alterar abertura/fechamento de superfícies | `lib/shell/cloudos_shell.dart` |
| alterar ícones/status/wallpaper | `lib/shell/widgets/` |
| alterar Files | `lib/features/files/` |
| alterar Start/Search | `lib/features/start/` |
| alterar dados nativos expostos ao Dart | `lib/services/cloudos_bridge.dart` + `native_bridge/` |
| alterar IPC Broker | `native_bridge/cloudos_broker_client_v21.*` + `../CloudOS.SystemBroker/src/protocol_v21.*` |
| alterar integração Windows/WSL real | `../CloudOS.SystemBroker/src/` e autoridades nativas descritas no `AGENTS.md` raiz |
| validar UI | `test/shell_smoke_test.dart` + workflow `cloudos-flutter-ui.yml` |

## Regra de contexto para IA

Não comece lendo todos os arquivos. Abra `AGENTS.md`, este mapa e somente a feature necessária. Expanda para Native Bridge/Broker apenas se a mudança atravessar a boundary nativa.
