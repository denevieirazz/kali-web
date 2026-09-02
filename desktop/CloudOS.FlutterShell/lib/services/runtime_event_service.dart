import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/shell_models.dart';
import 'broker_event_bridge_v23.dart';

enum RuntimeBrokerConnectionState {
  unavailable,
  connecting,
  connected,
  disconnected,
}

class BrokerRuntimeEvent {
  const BrokerRuntimeEvent({
    required this.name,
    required this.payload,
    required this.timestampMs,
    required this.rawJson,
    required this.nativeDroppedEvents,
  });

  final String name;
  final Map<String, Object?> payload;
  final int timestampMs;
  final String rawJson;
  final int nativeDroppedEvents;

  static BrokerRuntimeEvent? tryParse(NativeBrokerEventFrame frame) {
    try {
      final decoded = jsonDecode(frame.json);
      if (decoded is! Map) return null;
      final root = Map<String, Object?>.from(decoded);
      if (root['type'] != 'event') return null;

      final name = root['event'];
      if (name is! String || name.trim().isEmpty || name.length > 256) {
        return null;
      }

      final payloadRaw = root['payload'];
      final payload = payloadRaw is Map
          ? Map<String, Object?>.unmodifiable(
              Map<String, Object?>.from(payloadRaw),
            )
          : const <String, Object?>{};
      final timestamp = (root['timestamp'] as num?)?.toInt() ??
          (root['timestamp_ms'] as num?)?.toInt() ??
          0;

      return BrokerRuntimeEvent(
        name: name.trim(),
        payload: payload,
        timestampMs: timestamp < 0 ? 0 : timestamp,
        rawJson: frame.json,
        nativeDroppedEvents: frame.droppedEvents < 0 ? 0 : frame.droppedEvents,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class RuntimeEventService extends ChangeNotifier {
  RuntimeEventService({
    Stream<NativeBrokerEventFrame>? nativeEvents,
    Stream<NativeBrokerConnectionEvent>? nativeConnectionEvents,
  }) : _injectedEvents = nativeEvents,
       _injectedConnectionEvents = nativeConnectionEvents;

  static final RuntimeEventService instance = RuntimeEventService();

  static const int maxJournalEntries = 256;
  static const int maxNotifications = 100;

  final Stream<NativeBrokerEventFrame>? _injectedEvents;
  final Stream<NativeBrokerConnectionEvent>? _injectedConnectionEvents;
  final List<BrokerRuntimeEvent> _journal = <BrokerRuntimeEvent>[];
  final List<CloudNotification> _notifications = <CloudNotification>[];
  final Set<String> _unreadNotificationIds = <String>{};
  final StreamController<BrokerRuntimeEvent> _runtimeEvents =
      StreamController<BrokerRuntimeEvent>.broadcast(sync: true);

  StreamSubscription<NativeBrokerEventFrame>? _eventSubscription;
  StreamSubscription<NativeBrokerConnectionEvent>? _connectionSubscription;
  bool _started = false;
  bool _disposed = false;
  int _invalidFrameCount = 0;
  int _nativeDroppedEventCount = 0;
  int _notificationSequence = 0;
  RuntimeBrokerConnectionState _connectionState =
      RuntimeBrokerConnectionState.unavailable;
  RuntimeBrokerConnectionState _previousStableConnectionState =
      RuntimeBrokerConnectionState.unavailable;
  DateTime? _lastEventAt;

  Stream<BrokerRuntimeEvent> get events => _runtimeEvents.stream;
  List<BrokerRuntimeEvent> get journal =>
      List<BrokerRuntimeEvent>.unmodifiable(_journal);
  List<CloudNotification> get notifications =>
      List<CloudNotification>.unmodifiable(_notifications);
  int get unreadCount => _unreadNotificationIds.length;
  int get invalidFrameCount => _invalidFrameCount;
  int get nativeDroppedEventCount => _nativeDroppedEventCount;
  RuntimeBrokerConnectionState get connectionState => _connectionState;
  DateTime? get lastEventAt => _lastEventAt;

  String get connectionStateLabel => switch (_connectionState) {
    RuntimeBrokerConnectionState.connected => 'Conectado',
    RuntimeBrokerConnectionState.connecting => 'Conectando',
    RuntimeBrokerConnectionState.disconnected => 'Desconectado',
    RuntimeBrokerConnectionState.unavailable => 'Indisponível',
  };

  void start() {
    if (_started || _disposed) return;
    _started = true;

    final nativeBridge = BrokerEventBridgeV23.instance;
    final eventStream = _injectedEvents ?? nativeBridge.events;
    final connectionStream =
        _injectedConnectionEvents ?? nativeBridge.connectionEvents;

    _eventSubscription = eventStream.listen(
      _handleNativeEvent,
      onError: (_) => _setConnectionState(
        RuntimeBrokerConnectionState.disconnected,
      ),
    );
    _connectionSubscription = connectionStream.listen(
      _handleNativeConnection,
      onError: (_) => _setConnectionState(
        RuntimeBrokerConnectionState.disconnected,
      ),
    );
  }

  void _handleNativeConnection(NativeBrokerConnectionEvent event) {
    if (_disposed) return;
    _nativeDroppedEventCount =
        event.droppedEvents > _nativeDroppedEventCount
        ? event.droppedEvents
        : _nativeDroppedEventCount;

    final state = switch (event.state.trim().toLowerCase()) {
      'connected' => RuntimeBrokerConnectionState.connected,
      'connecting' => RuntimeBrokerConnectionState.connecting,
      'disconnected' => RuntimeBrokerConnectionState.disconnected,
      _ => RuntimeBrokerConnectionState.unavailable,
    };
    _setConnectionState(state);
  }

  void _setConnectionState(RuntimeBrokerConnectionState next) {
    if (_disposed || next == _connectionState) return;
    final previous = _connectionState;
    _connectionState = next;

    if (next == RuntimeBrokerConnectionState.connected) {
      if (_previousStableConnectionState ==
          RuntimeBrokerConnectionState.disconnected) {
        _addNotification(
          title: 'System Broker reconectado',
          message: 'O canal de eventos voltou a responder.',
          source: 'System Broker',
          category: 'Sistema',
          icon: Icons.link_rounded,
        );
      }
      _previousStableConnectionState = next;
    } else if (next == RuntimeBrokerConnectionState.disconnected) {
      if (previous == RuntimeBrokerConnectionState.connected ||
          _previousStableConnectionState ==
              RuntimeBrokerConnectionState.connected) {
        _addNotification(
          title: 'System Broker desconectado',
          message: 'O CloudOS está tentando restabelecer o canal de eventos.',
          source: 'System Broker',
          category: 'Sistema',
          icon: Icons.link_off_rounded,
        );
      }
      _previousStableConnectionState = next;
    }
    notifyListeners();
  }

  void _handleNativeEvent(NativeBrokerEventFrame frame) {
    if (_disposed) return;
    if (frame.droppedEvents > _nativeDroppedEventCount) {
      _nativeDroppedEventCount = frame.droppedEvents;
    }

    final event = BrokerRuntimeEvent.tryParse(frame);
    if (event == null) {
      _invalidFrameCount++;
      notifyListeners();
      return;
    }

    if (_connectionState != RuntimeBrokerConnectionState.connected) {
      _setConnectionState(RuntimeBrokerConnectionState.connected);
    }

    _lastEventAt = DateTime.now();
    _journal.add(event);
    if (_journal.length > maxJournalEntries) {
      _journal.removeRange(0, _journal.length - maxJournalEntries);
    }
    _runtimeEvents.add(event);
    _mapEventToNotification(event);
    notifyListeners();
  }

  void _mapEventToNotification(BrokerRuntimeEvent event) {
    if (event.name == 'job.completed') {
      _addNotification(
        title: 'Operação concluída',
        message: _jobMessage(event, fallback: 'O job terminou com sucesso.'),
        source: 'Files / Jobs',
        category: 'Operações',
        icon: Icons.check_circle_outline_rounded,
      );
      return;
    }
    if (event.name == 'job.failed') {
      final error = event.payload['error'];
      _addNotification(
        title: 'Operação falhou',
        message: error is String && error.trim().isNotEmpty
            ? error.trim()
            : _jobMessage(event, fallback: 'O job terminou com erro.'),
        source: 'Files / Jobs',
        category: 'Operações',
        icon: Icons.error_outline_rounded,
      );
      return;
    }
    if (event.name == 'job.cancelled') {
      _addNotification(
        title: 'Operação cancelada',
        message: _jobMessage(event, fallback: 'O job foi cancelado.'),
        source: 'Files / Jobs',
        category: 'Operações',
        icon: Icons.cancel_outlined,
      );
    }
  }

  String _jobMessage(BrokerRuntimeEvent event, {required String fallback}) {
    final jobId = event.payload['jobId'];
    if (jobId is String && jobId.trim().isNotEmpty) {
      return 'Job ${jobId.trim()}';
    }
    return fallback;
  }

  void _addNotification({
    required String title,
    required String message,
    required String source,
    required String category,
    required IconData icon,
  }) {
    final now = DateTime.now();
    final id =
        'runtime-${now.microsecondsSinceEpoch}-${_notificationSequence++}';
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    _notifications.insert(
      0,
      CloudNotification(
        id: id,
        title: title,
        message: message,
        time: '$hour:$minute',
        icon: icon,
        source: source,
        category: category,
      ),
    );
    _unreadNotificationIds.add(id);

    if (_notifications.length > maxNotifications) {
      final removed = _notifications.sublist(maxNotifications);
      _notifications.removeRange(maxNotifications, _notifications.length);
      for (final item in removed) {
        _unreadNotificationIds.remove(item.id);
      }
    }
  }

  void markAllRead() {
    if (_unreadNotificationIds.isEmpty || _disposed) return;
    _unreadNotificationIds.clear();
    notifyListeners();
  }

  void dismissNotification(String id) {
    if (_disposed) return;
    final before = _notifications.length;
    _notifications.removeWhere((item) => item.id == id);
    _unreadNotificationIds.remove(id);
    if (_notifications.length != before) notifyListeners();
  }

  void clearNotifications() {
    if (_disposed ||
        (_notifications.isEmpty && _unreadNotificationIds.isEmpty)) {
      return;
    }
    _notifications.clear();
    _unreadNotificationIds.clear();
    notifyListeners();
  }

  @visibleForTesting
  void ingestForTesting(NativeBrokerEventFrame frame) {
    _handleNativeEvent(frame);
  }

  @visibleForTesting
  void ingestConnectionForTesting(NativeBrokerConnectionEvent event) {
    _handleNativeConnection(event);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_runtimeEvents.close());
    super.dispose();
  }
}
