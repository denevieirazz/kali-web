import 'dart:async';

import 'package:flutter/material.dart';

import 'core/cloudos_theme.dart';
import 'services/app_lifecycle_coordinator.dart';
import 'services/desktop_clock_service.dart';
import 'services/runtime_event_service.dart';
import 'shell/cloudos_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RuntimeEventService.instance.start();
  DesktopClockService.instance.start();
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
      onPause: _checkpointAndPausePresentation,
      onHide: _checkpointAndPausePresentation,
      onDetach: _checkpointAndPausePresentation,
      onResume: DesktopClockService.instance.start,
      onShow: DesktopClockService.instance.start,
    );
  }

  void _checkpointAndPausePresentation() {
    DesktopClockService.instance.stop();
    unawaited(AppLifecycleCoordinator.instance.checkpoint());
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
