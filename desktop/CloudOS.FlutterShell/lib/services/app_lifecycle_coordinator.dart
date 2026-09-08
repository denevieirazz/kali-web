import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'cloudos_logger.dart';
import 'session_service.dart';

typedef DurableSessionFlush = Future<void> Function();

class _DurableFlushRegistration {
  const _DurableFlushRegistration(this.token, this.flush);

  final Object token;
  final DurableSessionFlush flush;
}

/// Process-level lifecycle authority for orderly CloudOS shutdown.
///
/// Production WindowManager registers its strict durable flush callback here.
/// Native WM_CLOSE therefore forces the latest in-memory window/workspace state
/// into Session V3 directly instead of relying on debounce timing. The
/// SessionService-only path remains as a safe fallback for startup/tests before
/// the production WindowManager has registered.
class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    SessionService? sessionService,
    Duration fallbackExitQuiescence = const Duration(milliseconds: 240),
  })  : _sessionService = sessionService ?? SessionService.instance,
        _fallbackExitQuiescence = fallbackExitQuiescence;

  static final AppLifecycleCoordinator instance = AppLifecycleCoordinator();

  final SessionService _sessionService;
  final Duration _fallbackExitQuiescence;
  Future<AppExitResponse>? _pendingExitDecision;
  _DurableFlushRegistration? _durableFlushRegistration;
  bool _disposed = false;

  bool get hasDurableFlushRegistration => _durableFlushRegistration != null;

  Object registerDurableFlush(DurableSessionFlush flush) {
    final token = Object();
    _durableFlushRegistration = _DurableFlushRegistration(token, flush);
    return token;
  }

  void unregisterDurableFlush(Object token) {
    final current = _durableFlushRegistration;
    if (current != null && identical(current.token, token)) {
      _durableFlushRegistration = null;
    }
  }

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
      final registered = _durableFlushRegistration;
      if (registered != null) {
        // The registered callback is responsible for snapshotting the current
        // WindowManager state and using strict Session V3 durability.
        await registered.flush();
      } else {
        // Startup/test fallback for the brief period before WindowManager owns
        // the runtime. Retain a bounded quiescence only on this fallback path.
        if (_fallbackExitQuiescence > Duration.zero) {
          await Future<void>.delayed(_fallbackExitQuiescence);
        }
        await _sessionService.flush(requireSuccessfulWrite: true);
      }
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
    _durableFlushRegistration = null;
    _disposed = true;
  }
}
