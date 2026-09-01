import 'package:flutter/material.dart';

import 'core/cloudos_theme.dart';
import 'shell/cloudos_shell_v21.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CloudOSApp());
}

class CloudOSApp extends StatelessWidget {
  const CloudOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CloudOS V21',
      debugShowCheckedModeBanner: false,
      theme: buildCloudOSTheme(),
      home: const CloudOSShellV21(),
    );
  }
}
