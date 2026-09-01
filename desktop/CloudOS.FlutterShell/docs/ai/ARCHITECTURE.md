# CloudOS Flutter Shell V21 — Architecture

## Runtime boundary

O Flutter Shell é uma camada de apresentação. O acesso real a Windows/WSL continua atrás do Native Bridge e do System Broker V21.

```text
Flutter presentation
  |
  | MethodChannel: cloudos/native/v19
  v
CloudOSFlutterBridgeV20
  |
  v
CloudOSBrokerClientV21
  |
  | NamedPipe protocol V21
  v
CloudOS.SystemBroker.exe
  |-- AppServiceV21
  |-- SystemServiceV21
  |-- WslServiceV21
  |-- JobManagerV21
  |-- EventBusV21
  |-- SecurityV21
  `-- DiagnosticsV21
```

## Flutter layering

```text
main.dart
  -> app/cloudos_app.dart
      -> shell/cloudos_shell.dart
          |-> shell/widgets/*
          |-> features/files/*
          |-> features/start/*
          |-> features/taskbar/*
          |-> features/quick_settings/*
          |-> features/notifications/*
          `-> services/cloudos_bridge.dart
                 |-> services/bridge/cloud_app_mapper.dart
                 `-> services/bridge/cloudos_preview_data.dart
```

Modelos compartilhados ficam em `lib/models/` e `shell_models.dart` funciona somente como compatibility barrel.

### Bootstrap

`main.dart` deve permanecer mínimo. Ele inicializa bindings e executa `CloudOSApp`. O arquivo reexporta `CloudOSApp` porque esse é um contrato consumido pelo smoke test e potencialmente por callers existentes.

### App root

`app/cloudos_app.dart` possui a configuração do `MaterialApp`, theme e root `CloudOSShell`. Não colocar feature específica aqui.

### Shell

`shell/cloudos_shell.dart` é o coordenador do desktop Flutter: estado de surfaces abertas, workspace, atalhos e seleção de painel transitório. Elementos puramente visuais do desktop pertencem a `shell/widgets/`.

A shell não deve absorver a implementação interna de Files, Start, Taskbar, Quick Settings ou Notifications.

### Features

Uma feature com estado + múltiplas superfícies deve viver em `lib/features/<feature>/`. A camada `domain/` só deve existir quando há lógica pura que vale separar da UI; não criar abstrações vazias.

Fronteiras atuais:

- `features/files/` — janela e composição do explorador unificado.
- `features/start/` — Start/Search e filtro puro de apps.
- `features/taskbar/` — composição da barra, apps, workspaces e tray.
- `features/quick_settings/` — toggles, sliders e resumo do sistema.
- `features/notifications/` — centro de notificações, cards, empty state e formatação de data.

### Models

Não misturar novamente tipos independentes num arquivo único. Os tipos atuais são:

- `models/cloud_app.dart`
- `models/cloud_file_item.dart`
- `models/cloud_notification.dart`
- `models/cloud_system_snapshot.dart`

`models/shell_models.dart` apenas reexporta esses arquivos para preservar imports existentes.

## Compatibility exports

Durante a modularização, os caminhos antigos foram preservados como exports pequenos:

- `lib/widgets/files_window.dart`
- `lib/widgets/start_panel.dart`
- `lib/widgets/cloud_taskbar.dart`
- `lib/widgets/quick_settings_panel.dart`
- `lib/widgets/notification_center.dart`

Isso reduz churn e permite migração gradual sem manter duas implementações.

## Native bridge contract

`CloudOSBridge` é a boundary Dart. Widgets não devem conhecer detalhes de Named Pipe, framing, broker executable ou comandos arbitrários.

O fluxo de IPC V21 deve continuar tipado/restrito. O CI registra `arbitrary_command_api = false`; não transformar o bridge em shell/command passthrough genérico.

Fixtures de preview e mapping do payload nativo ficam fora do transporte para que mudanças de apresentação não expandam o contexto da boundary IPC.

## Validation boundary

O workflow `.github/workflows/cloudos-flutter-ui.yml` é a prova canônica para esta camada. Ele valida tanto Flutter quanto a integração com o System Broker no Windows.

Além do smoke de UI, `test/modular_logic_test.dart` cobre lógica pura extraída sem depender de host nativo.

Resultados de hosted CI não equivalem a teste físico de WSLg, sessão real, reboot ou hardware específico; mantenha essa distinção nos relatórios.
