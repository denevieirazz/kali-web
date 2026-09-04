import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/features/start/domain/start_running_app.dart';
import 'package:cloudos_flutter_shell/features/task_manager/presentation/task_manager_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';

void main() {
  group('TaskManagerWindow Widget Tests', () {
    const mockSnapshot = CloudSystemSnapshot(
      deviceName: 'CloudOS-Host',
      networkName: 'Wi-Fi 6',
      volume: 0.8,
      brightness: 0.7,
      batteryPercent: 88,
      wslAvailable: true,
      distros: <String>['kali-linux', 'Ubuntu'],
      currentWorkspace: 2,
    );

    testWidgets('renders metrics and process list', (tester) async {
      final runningApps = <StartRunningApp>[
        const StartRunningApp(
          id: 'terminal',
          title: 'Terminal CloudOS',
          icon: Icons.terminal_rounded,
          appIds: <String>{'terminal'},
          isActive: true,
        ),
        const StartRunningApp(
          id: 'browser',
          title: 'Navegador Web',
          icon: Icons.language_rounded,
          appIds: <String>{'browser'},
          isMinimized: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: TaskManagerWindow(
                snapshot: mockSnapshot,
                runningApps: runningApps,
                onSwitchToApp: (_) {},
                onCloseApp: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('88%'), findsOneWidget);
      expect(find.textContaining('Ativo (2 distros)'), findsOneWidget);
      expect(find.text('Área 2'), findsOneWidget);
      expect(find.text('Terminal CloudOS'), findsOneWidget);
      expect(find.text('Navegador Web'), findsOneWidget);
      expect(find.text('Em Execução'), findsOneWidget);
      expect(find.text('Segundo Plano'), findsOneWidget);
    });

    testWidgets('triggers switch and close callbacks', (tester) async {
      String? switchedAppId;
      String? closedAppId;

      final runningApps = <StartRunningApp>[
        const StartRunningApp(
          id: 'notes',
          title: 'CloudOS Notes',
          icon: Icons.description_rounded,
          appIds: <String>{'notes'},
          isActive: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: TaskManagerWindow(
                snapshot: mockSnapshot,
                runningApps: runningApps,
                onSwitchToApp: (id) => switchedAppId = id,
                onCloseApp: (id) => closedAppId = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alternar'));
      await tester.pumpAndSettle();
      expect(switchedAppId, 'notes');

      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();
      expect(closedAppId, 'notes');
    });

    testWidgets('renders empty state message when no apps are running', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: TaskManagerWindow(
                snapshot: mockSnapshot,
                runningApps: const <StartRunningApp>[],
                onSwitchToApp: (_) {},
                onCloseApp: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhum processo em execução.'), findsOneWidget);
    });
  });
}
