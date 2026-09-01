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
- `widgets/files_content.dart` — roteador pequeno entre empty/grid/list.
- `widgets/files_grid.dart` — grade e card de arquivo.
- `widgets/files_list.dart` — apresentação em lista.
- `widgets/files_empty_state.dart` — pasta vazia / filtro sem resultado.
- `widgets/files_status_bar.dart` — contagem, seleção e status de sincronização.

Compatibilidade: `lib/widgets/files_window.dart` é apenas export; não adicionar implementação lá.

### Start / Search

Canônico: `lib/features/start/presentation/start_panel.dart`

Componentes:

- `domain/start_app_filter.dart` — filtros e busca pura de `CloudApp`.
- `presentation/widgets/start_header.dart` — identidade/close do Start.
- `presentation/widgets/start_search_field.dart` — campo de busca/clear.
- `presentation/widgets/start_filter_bar.dart` — filtros horizontais.
- `presentation/widgets/start_overview.dart` — fixados + recentes.
- `presentation/widgets/start_app_views.dart` — cards e resultados.
- `presentation/widgets/start_footer.dart` — sessão/ações do rodapé.

Compatibilidade: `lib/widgets/start_panel.dart` é apenas export.

### Taskbar

Canônico: `lib/features/taskbar/presentation/cloud_taskbar.dart`

Componentes:

- `widgets/taskbar_task_button.dart` — botão de app/estado running/active.
- `widgets/taskbar_workspace_switcher.dart` — seletor das quatro áreas de trabalho.
- `widgets/taskbar_system_tray.dart` — quick tray, relógio e badge de notificações.

Compatibilidade: `lib/widgets/cloud_taskbar.dart` é apenas export.

### Quick Settings

Canônico: `lib/features/quick_settings/presentation/quick_settings_panel.dart`

Componentes:

- `widgets/quick_toggle_tile.dart` — tile binário reutilizado pelos controles rápidos.
- `widgets/quick_slider_row.dart` — volume/brilho.
- `widgets/quick_system_summary.dart` — bateria, WSL e resumo da sessão.

Compatibilidade: `lib/widgets/quick_settings_panel.dart` é apenas export.

### Notifications

Canônico: `lib/features/notifications/presentation/notification_center_panel.dart`

Componentes:

- `domain/notification_date_formatter.dart` — data pt-BR pura.
- `presentation/widgets/notification_card.dart` — item individual e dismiss.
- `presentation/widgets/notification_empty_state.dart` — estado vazio.

Compatibilidade: `lib/widgets/notification_center.dart` é apenas export.

## Models

`lib/models/shell_models.dart` é uma fachada de compatibilidade. Código novo pode importar o modelo focado diretamente:

- `models/cloud_app.dart`
- `models/cloud_file_item.dart`
- `models/cloud_notification.dart`
- `models/cloud_system_snapshot.dart`

Não voltar a colocar modelos distintos dentro de `shell_models.dart`.

## Shared presentation

- `lib/core/cloudos_theme.dart` — cores/theme/tokens compartilhados.
- `lib/widgets/glass_surface.dart` — superfície visual reutilizável.

A pasta `lib/widgets/` deve permanecer pequena: arquivos de compatibilidade e componentes realmente compartilhados. Feature implementation pertence a `lib/features/`.

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
| alterar Taskbar | `lib/features/taskbar/` |
| alterar Quick Settings | `lib/features/quick_settings/` |
| alterar Notifications | `lib/features/notifications/` |
| alterar modelo de app/arquivo/notificação/snapshot | `lib/models/<modelo>.dart` |
| alterar dados nativos expostos ao Dart | `lib/services/cloudos_bridge.dart` + `native_bridge/` |
| alterar IPC Broker | `native_bridge/cloudos_broker_client_v21.*` + `../CloudOS.SystemBroker/src/protocol_v21.*` |
| alterar integração Windows/WSL real | `../CloudOS.SystemBroker/src/` e autoridades nativas descritas no `AGENTS.md` raiz |
| validar UI | `test/shell_smoke_test.dart`, `test/modular_logic_test.dart` + workflow `cloudos-flutter-ui.yml` |

## Regra de contexto para IA

Não comece lendo todos os arquivos. Abra `AGENTS.md`, este mapa e somente a feature necessária. Expanda para Native Bridge/Broker apenas se a mudança atravessar a boundary nativa.
