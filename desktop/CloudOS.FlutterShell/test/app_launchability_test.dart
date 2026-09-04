import 'package:cloudos_flutter_shell/features/start/presentation/widgets/start_app_views.dart';
import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:cloudos_flutter_shell/services/bridge/cloud_app_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native canLaunch false is preserved by the app mapper', () {
    final app = cloudAppFromNative(<Object?, Object?>{
      'id': 'windows:vscode',
      'name': 'Visual Studio Code',
      'platform': 'windows',
      'canLaunch': false,
    });

    expect(app.canLaunch, isFalse);
  });

  testWidgets('unavailable Start app cannot invoke launch callback', (tester) async {
    var launches = 0;
    const app = CloudApp(
      id: 'windows:vscode',
      name: 'Visual Studio Code',
      icon: Icons.code_rounded,
      platform: CloudAppPlatform.windows,
      canLaunch: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartPinnedAppCard(
            app: app,
            onTap: () => launches++,
          ),
        ),
      ),
    );

    expect(find.text('Containment ainda não validado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('start-app-windows:vscode')));
    await tester.pump();
    expect(launches, 0);
  });
}
