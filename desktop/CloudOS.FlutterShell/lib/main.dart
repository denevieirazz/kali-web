import 'dart:async';

import 'package:flutter/material.dart';

import 'core/cloudos_theme.dart';
import 'services/app_lifecycle_coordinator.dart';
import 'services/runtime_event_service.dart';
import 'shell/cloudos_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RuntimeEventService.instance.start();
  runApp(const CloudOSApp());
}

class CloudOSApp extends StatefulWidget {
  const CloudOSApp({super.key});

  @override
  State<CloudOSApp> createState() => _CloudOSAppState();
}

class _CloudOSAppState extends State<CloudOSApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: AppLifecycleCoordinator.instance.handleExitRequest,
      onPause: () => unawaited(AppLifecycleCoordinator.instance.checkpoint()),
      onHide: () => unawaited(AppLifecycleCoordinator.instance.checkpoint()),
      onDetach: () => unawaited(AppLifecycleCoordinator.instance.checkpoint()),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

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
