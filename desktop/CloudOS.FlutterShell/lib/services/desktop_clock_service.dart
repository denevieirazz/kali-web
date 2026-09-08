import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runtime-owned wall clock for desktop presentation.
///
/// The service is started explicitly by `main()`. Widget tests that construct
/// CloudOSShell directly therefore have no hidden periodic timer and need no
/// process-environment test switch.
class DesktopClockService extends ChangeNotifier {
  DesktopClockService({
    DateTime Function()? now,
    Duration tickInterval = const Duration(seconds: 1),
  })  : _nowProvider = now ?? DateTime.now,
        _tickInterval = tickInterval,
        _now = (now ?? DateTime.now)();

  static final DesktopClockService instance = DesktopClockService();

  final DateTime Function() _nowProvider;
  final Duration _tickInterval;
  DateTime _now;
  Timer? _timer;
  bool _disposed = false;

  DateTime get now => _now;
  bool get isRunning => _timer?.isActive ?? false;

  void start() {
    if (_disposed || isRunning) return;
    _refresh();
    _timer = Timer.periodic(_tickInterval, (_) => _refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _refresh() {
    if (_disposed) return;
    final next = _nowProvider();
    if (next == _now) return;
    _now = next;
    notifyListeners();
  }

  @visibleForTesting
  void refreshForTesting() => _refresh();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    super.dispose();
  }
}
