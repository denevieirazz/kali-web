# CloudOS Flutter Shell V21 — guia para agentes

Este arquivo vale para `desktop/CloudOS.FlutterShell/**`.
Leia também o `AGENTS.md` da raiz: o CloudOS nativo C++/Win32 continua sendo a autoridade geral do desktop; esta pasta é a apresentação Flutter V20/V21 integrada ao Native Bridge e ao System Broker V21.

## Regra principal

Não concentre uma feature inteira em `main.dart`, `shell/cloudos_shell.dart` ou em `lib/widgets/`.
Código novo de uma feature deve ficar em `lib/features/<feature>/` sempre que houver estado, lógica ou múltiplos widgets relacionados.

## Mapa rápido

- bootstrap: `lib/main.dart`
- root MaterialApp/theme wiring: `lib/app/cloudos_app.dart`
- shell/orquestração do desktop: `lib/shell/cloudos_shell.dart`
- wallpaper/ícones/status do desktop: `lib/shell/widgets/`
- Files: `lib/features/files/`
- Start/Search: `lib/features/start/`
- Taskbar: `lib/features/taskbar/`
- Quick Settings: `lib/features/quick_settings/`
- Notifications: `lib/features/notifications/`
- modelos focados: `lib/models/cloud_*.dart`
- facade de modelos legada: `lib/models/shell_models.dart`
- MethodChannel Flutter -> Native Bridge: `lib/services/cloudos_bridge.dart`
- mapper/preview do bridge: `lib/services/bridge/`
- bridge Windows C++: `native_bridge/cloudos_flutter_bridge_v20.*`
- cliente do System Broker V21: `native_bridge/cloudos_broker_client_v21.*`
- broker nativo: `../CloudOS.SystemBroker/`
- smoke Flutter: `test/shell_smoke_test.dart`
- lógica modular: `test/modular_logic_test.dart`

## Caminhos legados de compatibilidade

Estes arquivos existem para não quebrar imports antigos; não coloque novas implementações grandes neles:

- `lib/widgets/files_window.dart` -> `features/files/presentation/files_window.dart`
- `lib/widgets/start_panel.dart` -> `features/start/presentation/start_panel.dart`
- `lib/widgets/cloud_taskbar.dart` -> `features/taskbar/presentation/cloud_taskbar.dart`
- `lib/widgets/quick_settings_panel.dart` -> `features/quick_settings/presentation/quick_settings_panel.dart`
- `lib/widgets/notification_center.dart` -> `features/notifications/presentation/notification_center_panel.dart`
- `lib/models/shell_models.dart` -> barrel dos modelos focados em `lib/models/`

`lib/widgets/glass_surface.dart` continua sendo componente compartilhado real e não um shim de compatibilidade.

## Fronteiras

Fluxo esperado:

```text
Flutter widget
  -> estado/composição da feature
  -> CloudOSBridge (MethodChannel cloudos/native/v19)
  -> native_bridge/cloudos_flutter_bridge_v20.*
  -> cloudos_broker_client_v21.*
  -> CloudOS.SystemBroker (NamedPipe V21)
  -> serviços Windows/WSL
```

Não faça widgets conhecerem framing de Named Pipe, protocolo interno do broker ou comandos nativos arbitrários.
Não crie uma segunda implementação do catálogo Windows/Linux dentro do Flutter.
Não mova responsabilidade privilegiada do System Broker para Dart.

## Organização de feature

Use complexidade proporcional:

```text
features/<feature>/
  domain/                 # apenas lógica pura/modelos quando necessário
  presentation/
    <feature>_panel.dart  # composição/estado da superfície
    widgets/              # componentes semânticos da feature
```

Não crie camadas vazias só para seguir um padrão.
Não use `part` para esconder god files.
Não troque um arquivo gigante por outro `manager.dart` gigante.

## Modelos

Novo código deve importar o modelo específico quando isso reduzir contexto. `shell_models.dart` existe para compatibilidade, não para voltar a concentrar tipos.

Arquivos atuais:

- `cloud_app.dart`
- `cloud_file_item.dart`
- `cloud_notification.dart`
- `cloud_system_snapshot.dart`

## Compatibilidade

Antes de mover um símbolo público, procure testes/imports existentes. Quando um caminho público antigo precisar continuar válido, prefira um export pequeno de compatibilidade e documente o caminho canônico novo.

`test/shell_smoke_test.dart` atualmente importa `main.dart` e espera `CloudOSApp`; por isso `main.dart` reexporta `app/cloudos_app.dart`.

## Validação

O CI canônico é `.github/workflows/cloudos-flutter-ui.yml`.
Ele executa, no Windows:

1. build do System Broker e Broker Probe V21;
2. contratos/smokes/soak do broker;
3. geração do host Flutter Windows;
4. `flutter pub get`;
5. `flutter analyze --fatal-infos --fatal-warnings`;
6. `flutter test`;
7. `flutter build windows --release`.

Não declare build/test verde se esse fluxo não foi executado ou se o ambiente local não possui Flutter.
