import 'package:cloudos_flutter_shell/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CloudOS presentation renders core desktop surfaces', (tester) async {
    await tester.pumpWidget(const CloudOSApp());
    await tester.pumpAndSettle();

    expect(find.text('CloudOS'), findsWidgets);
    expect(find.text('Arquivos'), findsWidgets);
    expect(find.text('Windows + Linux'), findsWidgets);
    expect(find.text('Ubuntu'), findsWidgets);

    await tester.tap(find.byTooltip('Iniciar'));
    await tester.pumpAndSettle();

    expect(find.text('Fixados e recentes'), findsOneWidget);
    expect(find.text('Visual Studio Code'), findsOneWidget);
    expect(find.text('Ubuntu'), findsWidgets);
  });
}
