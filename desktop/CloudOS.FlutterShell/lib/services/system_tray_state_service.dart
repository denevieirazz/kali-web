import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/shell_models.dart';
import 'cloudos_bridge.dart';
import 'runtime_event_service.dart';

/// Live, truthful system snapshot used by desktop chrome.
///
/// The service has one authority: `system.snapshot` from the System Broker.
/// EventBus frames are used to patch low-latency values (volume) and to
/// invalidate/reload broader hardware state. A slow periodic refresh exists
/// only for hardware state that Windows does not yet publish through a typed
/// CloudOS native event (battery/network/WSL topology).
class SystemTrayStateService extends ChangeNotifier {
  SystemTrayStateService({
    required CloudOSBridge bridge,
    RuntimeEventService? runtime,
    this.pollInterval = const Duration(seconds: 30),
    this.eventRefreshDebounce = const Duration(milliseconds: 250),
  }) : _bridge = bridge,
       _runtime = runtime ?? RuntimeEventService.instance;

  final CloudOSBridge _bridge;
  final RuntimeEventService _runtime;
  final Duration? pollInterval;
  final Duration eventRefreshDebounce;

  CloudSystemSnapshot _snapshot = CloudOSBridge.unavailableSnapshot;
  StreamSubscription<BrokerRuntimeEvent>? _eventSubscription;
  Timer? _pollTimer;
  Timer? _eventDebounceTimer;

  bool _started = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _brokerConnected = false;
  int _refreshEpoch = 0;
  DateTime? _lastRefreshAt;
  Object? _lastRefreshError;
  RuntimeBrokerConnectionState _lastRuntimeConnection =
      RuntimeBrokerConnectionState.unavailable;

  CloudSystemSnapshot get snapshot => _snapshot;
  bool get started => _started;
  bool get refreshing => _refreshing;
  bool get brokerConnected => _brokerConnected;
  DateTime? get lastRefreshAt => _lastRefreshAt;
  Object? get lastRefreshError => _lastRefreshError;

  bool get hasAnyLiveCapability =>
      _snapshot.networkAvailable ||
      _snapshot.volumeAvailable ||
      _snapshot.batteryAvailable ||
      _snapshot.brightnessAvailable ||
      _snapshot.wslAvailable ||
      _snapshot.deviceName.trim().isNotEmpty;

  void start() {
    if (_started || _disposed) return;
    _started = true;

    _runtime.start();
    _lastRuntimeConnection = _runtime.connectionState;
    _brokerConnected =
        _lastRuntimeConnection == RuntimeBrokerConnectionState.connected;
    _runtime.addListener(_handleRuntimeStateChanged);
    _eventSubscription = _runtime.events.listen(
      _handleRuntimeEvent,
      onError: (_) => _markBrokerDisconnected(),
    );

    if (pollInterval case final interval?) {
      if (interval > Duration.zero) {
        _pollTimer = Timer.periodic(interval, (_) {
          if (!_disposed) unawaited(refresh(reason: 'periodic-hardware-refresh'));
        });
      }
    }

    unawaited(refresh(reason: 'service-start'));
  }

  Future<void> refresh({String reason = 'manual', bool force = false}) async {
    if (_disposed) return;
    if (_refreshing && !force) return;

    final epoch = ++_refreshEpoch;
    _refreshing = true;
    _lastRefreshError = null;
    notifyListeners();

    try {
      final loaded = await _bridge.loadSystemSnapshot();
      if (_disposed || epoch != _refreshEpoch) return;

      _snapshot = loaded.normalized();
      _lastRefreshAt = DateTime.now();
      _lastRefreshError = null;
    } catch (error) {
      if (_disposed || epoch != _refreshEpoch) return;
      _lastRefreshError = error;
    } finally {
      if (!_disposed && epoch == _refreshEpoch) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> setVolume(double requested) async {
    if (_disposed || !_snapshot.volumeAvailable) return false;
    final value = requested.clamp(0.0, 1.0).toDouble();
    final previous = _snapshot;
    _snapshot = _snapshot.copyWith(volume: value, volumeAvailable: true);
    notifyListeners();

    final updated = await _bridge.setVolume(value);
    if (_disposed) return updated;
    if (!updated) {
      _snapshot = previous;
      notifyListeners();
      return false;
    }

    _snapshot = _snapshot.copyWith(volume: value, volumeAvailable: true);
    notifyListeners();
    return true;
  }

  Future<bool> setBrightness(double requested) async {
    if (_disposed || !_snapshot.brightnessAvailable) return false;
    final value = requested.clamp(0.0, 1.0).toDouble();
    final previous = _snapshot;
    _snapshot = _snapshot.copyWith(
      brightness: value,
      brightnessAvailable: true,
    );
    notifyListeners();

    final updated = await _bridge.setBrightness(value);
    if (_disposed) return updated;
    if (!updated) {
      _snapshot = previous;
      notifyListeners();
      return false;
    }

    _snapshot = _snapshot.copyWith(
      brightness: value,
      brightnessAvailable: true,
    );
    notifyListeners();
    return true;
  }

  void _handleRuntimeStateChanged() {
    if (_disposed) return;
    final next = _runtime.connectionState;
    if (next == _lastRuntimeConnection) return;
    final previous = _lastRuntimeConnection;
    _lastRuntimeConnection = next;
    _brokerConnected = next == RuntimeBrokerConnectionState.connected;

    if (next == RuntimeBrokerConnectionState.connected &&
        previous != RuntimeBrokerConnectionState.connected) {
      unawaited(refresh(reason: 'broker-reconnected', force: true));
    }
    notifyListeners();
  }

  void _markBrokerDisconnected() {
    if (_disposed || !_brokerConnected) return;
    _brokerConnected = false;
    notifyListeners();
  }

  void _handleRuntimeEvent(BrokerRuntimeEvent event) {
    if (_disposed) return;

    if (event.name == 'system.volumeChanged') {
      final raw = event.payload['volume'];
      if (raw is num && raw.isFinite) {
        _snapshot = _snapshot.copyWith(
          volume: raw.toDouble().clamp(0.0, 1.0).toDouble(),
          volumeAvailable: true,
        );
        notifyListeners();
      }
      return;
    }

    if (event.name == 'broker.ready' ||
        event.name == 'system.snapshotChanged' ||
        event.name == 'system.networkChanged' ||
        event.name == 'system.powerChanged' ||
        event.name == 'system.batteryChanged' ||
        event.name == 'wsl.changed' ||
        event.name == 'wsl.distributionsChanged') {
      _scheduleEventRefresh(event.name);
    }
  }

  void _scheduleEventRefresh(String reason) {
    _eventDebounceTimer?.cancel();
    _eventDebounceTimer = Timer(eventRefreshDebounce, () {
      if (!_disposed) unawaited(refresh(reason: reason, force: true));
    });
  }

  @visibleForTesting
  void ingestEventForTesting(BrokerRuntimeEvent event) {
    _handleRuntimeEvent(event);
  }

  @visibleForTesting
  void replaceSnapshotForTesting(CloudSystemSnapshot value) {
    if (_disposed) return;
    _snapshot = value.normalized();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshEpoch++;
    _pollTimer?.cancel();
    _eventDebounceTimer?.cancel();
    _runtime.removeListener(_handleRuntimeStateChanged);
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }
}
