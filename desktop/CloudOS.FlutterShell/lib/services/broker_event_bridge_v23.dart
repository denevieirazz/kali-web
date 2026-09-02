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

  static final BrokerEventBridgeV23 instance = BrokerEventBridgeV23._();

  final MethodChannel _channel;
  final StreamController<NativeBrokerEventFrame> _events =
      StreamController<NativeBrokerEventFrame>.broadcast(sync: true);
  final StreamController<NativeBrokerConnectionEvent> _connectionEvents =
      StreamController<NativeBrokerConnectionEvent>.broadcast(sync: true);

  bool _started = false;
  Future<bool>? _startFuture;

  Stream<NativeBrokerEventFrame> get events {
    start();
    return _events.stream;
  }

  Stream<NativeBrokerConnectionEvent> get connectionEvents {
    start();
    return _connectionEvents.stream;
  }

  Future<bool> start() {
    if (_started && _startFuture != null) return _startFuture!;
    _started = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    _startFuture = _invokeStart();
    return _startFuture!;
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
}
