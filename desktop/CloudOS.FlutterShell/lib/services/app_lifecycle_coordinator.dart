import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'cloudos_logger.dart';
import 'session_service.dart';

/// Process-level lifecycle authority for orderly CloudOS shutdown.
///
/// WindowManager persists with a short debounce. A native close request can
/// arrive while that timer is still pending, so the coordinator gives the
/// pending snapshot a small quiescence window, then requires the serialized
/// Session V3 write queue to have completed successfully before allowing the
/// process to exit.
class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    SessionService? sessionService,
    Duration exitQuiescence = const Duration(milliseconds: 240),
  })  : _sessionService = sessionService ?? SessionService.instance,
        _exitQuiescence = exitQuiescence;

  static final AppLifecycleCoordinator instance = AppLifecycleCoordinator();

  final SessionService _sessionService;
  final Duration _exitQuiescence;
  Future<AppExitResponse>? _pendingExitDecision;
  bool _disposed = false;

  Future<AppExitResponse> handleExitRequest() {
    if (_disposed) return Future<AppExitResponse>.value(AppExitResponse.exit);
    final pending = _pendingExitDecision;
    if (pending != null) return pending;

    late Future<AppExitResponse> decision;
    decision = _prepareExit().whenComplete(() {
      if (identical(_pendingExitDecision, decision)) {
        _pendingExitDecision = null;
      }
    });
    _pendingExitDecision = decision;
    return decision;
  }

  Future<AppExitResponse> _prepareExit() async {
    try {
      if (_exitQuiescence > Duration.zero) {
        await Future<void>.delayed(_exitQuiescence);
      }
      await _sessionService.flush(requireSuccessfulWrite: true);
      return AppExitResponse.exit;
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'AppLifecycleCoordinator',
        'handleExitRequest',
        error,
        stackTrace,
      );
      return AppExitResponse.cancel;
    }
  }

  /// Best-effort checkpoint for non-terminal lifecycle transitions. This is
  /// deliberately non-strict: hiding/minimizing the UI must not surface an
  /// unhandled filesystem exception. A later orderly exit remains strict.
  Future<void> checkpoint() async {
    if (_disposed) return;
    try {
      await _sessionService.flush();
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'AppLifecycleCoordinator',
        'checkpoint',
        error,
        stackTrace,
      );
    }
  }

  void dispose() {
    _disposed = true;
  }
}
