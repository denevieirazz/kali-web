import 'package:flutter/material.dart';

import 'core/cloudos_theme.dart';
import 'services/runtime_event_service.dart';
import 'shell/cloudos_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RuntimeEventService.instance.start();
  runApp(const CloudOSApp());
}

class CloudOSApp extends StatelessWidget {
  const CloudOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CloudOS Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildCloudOSTheme(),
      home: const CloudOSShell(),
    );
  }
}
