import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class CloudOSBrokerEvent {
  const CloudOSBrokerEvent({
    required this.name,
    required this.payload,
    required this.timestamp,
    required this.rawJson,
  });

  final String name;
  final Map<String, Object?> payload;
  final int timestamp;
  final String rawJson;
}

/// Typed Dart-side view of the native V23 broker event stream.
///
/// Native code owns the approved Broker EventBus subscriptions and invokes the
/// `brokerEvent` method only after response/event demultiplexing. Dart cannot
/// expand subscription patterns through the generic RPC surface.
class CloudOSBrokerEvents {
  CloudOSBrokerEvents._({
    MethodChannel channel = const MethodChannel('cloudos/native/v19'),
  }) : _channel = channel;

  static final CloudOSBrokerEvents instance = CloudOSBrokerEvents._();

  final MethodChannel _channel;
  final StreamController<CloudOSBrokerEvent> _controller =
      StreamController<CloudOSBrokerEvent>.broadcast(sync: true);

  bool _handlerInstalled = false;
  Future<bool>? _startFuture;

  Stream<CloudOSBrokerEvent> get stream => _controller.stream;

  Future<bool> start() {
    final existing = _startFuture;
    if (existing != null) return existing;
    final future = _startInternal();
    _startFuture = future;
    return future;
  }

  Future<bool> _startInternal() async {
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_handleNativeMethodCall);
      _handlerInstalled = true;
    }

    try {
      final started = await _channel.invokeMethod<bool>('startBrokerEvents');
      return started ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Object?> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != 'brokerEvent') return null;
    final raw = call.arguments;
    if (raw is! String || raw.isEmpty || raw.length > 1024 * 1024) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> || decoded['type'] != 'event') {
        return null;
      }
      final name = decoded['event'];
      final payload = decoded['payload'];
      if (name is! String || name.isEmpty || payload is! Map<String, Object?>) {
        return null;
      }

      _controller.add(
        CloudOSBrokerEvent(
          name: name,
          payload: Map<String, Object?>.unmodifiable(payload),
          timestamp: (decoded['timestamp'] as num?)?.toInt() ?? 0,
          rawJson: raw,
        ),
      );
    } on FormatException {
      // Native event delivery is fail-closed. A malformed frame is dropped and
      // never converted into guessed UI state.
    }
    return null;
  }
}
