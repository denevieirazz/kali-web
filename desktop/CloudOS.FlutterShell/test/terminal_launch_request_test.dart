import 'dart:async';

import 'package:cloudos_flutter_shell/features/terminal/presentation/terminal_window.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTerminalBridge extends CloudOSBridge {
  final List<String> createdShells = <String>[];
  final List<String> closedSessions = <String>[];
  int _session = 0;

  @override
  Stream<TerminalDataEvent> get terminalDataStream =>
      const Stream<TerminalDataEvent>.empty();

  @override
  Stream<TerminalExitEvent> get terminalExitStream =>
      const Stream<TerminalExitEvent>.empty();

  @override
  Future<String?> createTerminalSession({
    String shellKind = 'powershell',
    String distro = '',
    int cols = 80,
    int rows = 24,
  }) async {
    createdShells.add(shellKind);
    return 'session_${++_session}';
  }

  @override
  Future<bool> resizeTerminal(String sessionId, int cols, int rows) async => true;

  @override
  Future<bool> closeTerminal(String sessionId) async {
    closedSessions.add(sessionId);
    return true;
  }
}

Widget _harness({
  required CloudOSBridge bridge,
  required TerminalShellKind initialShell,
  TerminalShellKind? requestedShell,
  int revision = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 600,
        child: TerminalWindow(
          bridge: bridge,
          initialShell: initialShell,
          requestedShell: requestedShell,
          launchRevision: revision,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('initial CMD launch creates one ConPTY CMD session', (tester) async {
    final bridge = _RecordingTerminalBridge();
    await tester.pumpWidget(
      _harness(
        bridge: bridge,
        initialShell: TerminalShellKind.cmd,
        requestedShell: TerminalShellKind.cmd,
      ),
    );
    await tester.pumpAndSettle();

    expect(bridge.createdShells, <String>['cmd']);
    expect(find.text('CMD (ConPTY)'), findsOneWidget);
  });

  testWidgets('repeated CMD request focuses existing live tab', (tester) async {
    final bridge = _RecordingTerminalBridge();
    await tester.pumpWidget(
      _harness(
        bridge: bridge,
        initialShell: TerminalShellKind.cmd,
        requestedShell: TerminalShellKind.cmd,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _harness(
        bridge: bridge,
        initialShell: TerminalShellKind.cmd,
        requestedShell: TerminalShellKind.cmd,
        revision: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(bridge.createdShells, <String>['cmd']);
  });

  testWidgets('PowerShell request appends session without destroying CMD', (
    tester,
  ) async {
    final bridge = _RecordingTerminalBridge();
    await tester.pumpWidget(
      _harness(
        bridge: bridge,
        initialShell: TerminalShellKind.cmd,
        requestedShell: TerminalShellKind.cmd,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _harness(
        bridge: bridge,
        initialShell: TerminalShellKind.cmd,
        requestedShell: TerminalShellKind.powershell,
        revision: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(bridge.createdShells, <String>['cmd', 'powershell']);
    expect(find.text('CMD (ConPTY)'), findsOneWidget);
    expect(find.text('PowerShell (ConPTY)'), findsOneWidget);
    expect(bridge.closedSessions, isEmpty);
  });
}
