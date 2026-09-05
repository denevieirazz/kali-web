import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../shell/cloudos_shell.dart';

class CloudOSApp extends StatelessWidget {
  const CloudOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudThemeConfig>(
      valueListenable: cloudThemeNotifier,
      builder: (context, config, _) {
        return MaterialApp(
          title: 'CloudOS Flutter Preview',
          debugShowCheckedModeBanner: false,
          theme: buildCloudOSTheme(config),
          home: const CloudOSShell(),
        );
      },
    );
  }
}
