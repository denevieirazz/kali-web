import 'dart:async';

import 'package:flutter/services.dart';

class NativeBrokerEventFrame {
  const NativeBrokerEventFrame({
    required this.json,
    required this.droppedEvents,
  });

  final String json;
  final int droppedEvents;
}

class NativeBrokerConnectionEvent {
  const NativeBrokerConnectionEvent({
    required this.state,
    required this.droppedEvents,
  });

  final String state;
  final int droppedEvents;
}

/// Dedicated native <-> Dart transport for System Broker events.
///
/// The only Dart -> native methods are lifecycle/status for this event client.
/// Business RPC remains on cloudos/native/v19, so unsolicited EventBus frames
/// can never be consumed as synchronous RPC responses.
class BrokerEventBridgeV23 {
  BrokerEventBridgeV23._({
    MethodChannel channel = const MethodChannel('cloudos/native/events/v23'),
  }) : _channel = channel;

  /// Isolated channel surface for deterministic lifecycle tests.
  BrokerEventBridgeV23.forTesting(MethodChannel channel) : _channel = channel;

  static final BrokerEventBridgeV23 instance = BrokerEventBridgeV23._();

  final MethodChannel _channel;
  final StreamController<NativeBrokerEventFrame> _events =
      StreamController<NativeBrokerEventFrame>.broadcast(sync: true);
  final StreamController<NativeBrokerConnectionEvent> _connectionEvents =
      StreamController<NativeBrokerConnectionEvent>.broadcast(sync: true);

  bool _started = false;
  bool _disposed = false;
  Future<bool>? _startFuture;

  bool get isStarted => _started;

  Stream<NativeBrokerEventFrame> get events {
    unawaited(start());
    return _events.stream;
  }

  Stream<NativeBrokerConnectionEvent> get connectionEvents {
    unawaited(start());
    return _connectionEvents.stream;
  }

  Future<bool> start() {
    if (_disposed) return Future<bool>.value(false);
    final existing = _startFuture;
    if (_started && existing != null) return existing;

    _started = true;
    _channel.setMethodCallHandler(_handleNativeCall);

    late Future<bool> attempt;
    attempt = _invokeStart().then((ok) {
      if (!ok && identical(_startFuture, attempt)) {
        // MissingPlugin/PlatformException can be transient during host startup.
        // Do not poison the singleton forever; the next subscriber/start call
        // gets a fresh native attempt.
        _started = false;
        _startFuture = null;
      }
      return ok;
    });
    _startFuture = attempt;
    return attempt;
  }

  Future<bool> _invokeStart() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stop() async {
    if (_disposed) return true;
    var stopped = false;
    try {
      stopped = await _channel.invokeMethod<bool>('stop') ?? false;
    } on MissingPluginException {
      stopped = false;
    } on PlatformException {
      stopped = false;
    } finally {
      // A subsequent start must always negotiate a fresh native worker even if
      // the stop acknowledgement was lost while the host was tearing down.
      _started = false;
      _startFuture = null;
    }
    return stopped;
  }

  Future<Map<String, Object?>> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      return raw ?? const <String, Object?>{};
    } on MissingPluginException {
      return const <String, Object?>{};
    } on PlatformException {
      return const <String, Object?>{};
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (_disposed) return null;
    final args = call.arguments;
    if (args is! Map) return null;

    final dropped = (args['droppedEvents'] as num?)?.toInt() ?? 0;
    if (call.method == 'broker.onEvent') {
      final raw = args['json'];
      if (raw is String && raw.isNotEmpty) {
        _events.add(
          NativeBrokerEventFrame(
            json: raw,
            droppedEvents: dropped < 0 ? 0 : dropped,
          ),
        );
      }
      return null;
    }

    if (call.method == 'broker.onConnectionState') {
      final state = args['state'];
      if (state is String && state.isNotEmpty) {
        _connectionEvents.add(
          NativeBrokerConnectionEvent(
            state: state,
            droppedEvents: dropped < 0 ? 0 : dropped,
          ),
        );
      }
    }
    return null;
  }

  /// Intended for isolated test instances. The production singleton is owned
  /// by the application/native runner for the process lifetime.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _channel.setMethodCallHandler(null);
    await _events.close();
    await _connectionEvents.close();
  }
}
