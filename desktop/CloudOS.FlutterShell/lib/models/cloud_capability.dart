class CloudCapability {
  const CloudCapability({
    required this.id,
    this.supported = true,
    this.available = true,
    this.enabled = true,
    this.writable = true,
    this.reason,
    this.permission = 'allowed',
    this.features = const <String>[],
  });

  final String id;
  final bool supported;
  final bool available;
  final bool enabled;
  final bool writable;
  final String? reason;
  final String? permission;
  final List<String> features;

  bool get isOperational => supported && available;
  bool get isWritable => writable;

  factory CloudCapability.fromMap(Map<String, dynamic> map) {
    return CloudCapability(
      id: map['id'] as String? ?? 'unknown',
      supported: map['supported'] as bool? ?? true,
      available: map['available'] as bool? ?? true,
      enabled: map['enabled'] as bool? ?? true,
      writable: map['writable'] as bool? ?? true,
      reason: map['reason'] as String?,
      permission: map['permission'] as String? ?? 'allowed',
      features: (map['features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'supported': supported,
        'available': available,
        'enabled': enabled,
        'writable': writable,
        if (reason != null) 'reason': reason,
        if (permission != null) 'permission': permission,
        'features': features,
      };

  CloudCapability copyWith({
    String? id,
    bool? supported,
    bool? available,
    bool? enabled,
    bool? writable,
    String? reason,
    String? permission,
    List<String>? features,
  }) {
    return CloudCapability(
      id: id ?? this.id,
      supported: supported ?? this.supported,
      available: available ?? this.available,
      enabled: enabled ?? this.enabled,
      writable: writable ?? this.writable,
      reason: reason ?? this.reason,
      permission: permission ?? this.permission,
      features: features ?? this.features,
    );
  }

  static const CloudCapability unavailable = CloudCapability(
    id: 'unknown',
    supported: false,
    available: false,
    enabled: false,
    writable: false,
    reason: 'Capability not reported by system',
  );
}

class CapabilityRegistry {
  CapabilityRegistry([Map<String, CloudCapability>? capabilities])
      : _capabilities = capabilities != null
            ? Map<String, CloudCapability>.from(capabilities)
            : <String, CloudCapability>{};

  final Map<String, CloudCapability> _capabilities;

  Map<String, CloudCapability> get all =>
      Map<String, CloudCapability>.unmodifiable(_capabilities);

  CloudCapability get(String id) =>
      _capabilities[id] ??
      CloudCapability(
        id: id,
        supported: false,
        available: false,
        enabled: false,
        writable: false,
        reason: 'Recurso não suportado neste host',
      );

  bool isSupported(String id) => _capabilities[id]?.supported ?? false;
  bool isAvailable(String id) => _capabilities[id]?.available ?? false;
  bool isWritable(String id) => _capabilities[id]?.writable ?? false;
  bool isEnabled(String id) => _capabilities[id]?.enabled ?? false;

  void register(CloudCapability capability) {
    _capabilities[capability.id] = capability;
  }

  void registerAll(Iterable<CloudCapability> items) {
    for (final c in items) {
      _capabilities[c.id] = c;
    }
  }

  // Common quick-access capabilities
  CloudCapability get display => get('display');
  CloudCapability get audio => get('audio');
  CloudCapability get brightness => get('brightness');
  CloudCapability get bluetooth => get('bluetooth');
  CloudCapability get network => get('network');
  CloudCapability get battery => get('battery');
  CloudCapability get nightLight => get('nightLight');
  CloudCapability get focusMode => get('focusMode');
  CloudCapability get filesystem => get('filesystem');
  CloudCapability get recycleBin => get('recycleBin');
  CloudCapability get wsl => get('wsl');
  CloudCapability get terminal => get('terminal');
  CloudCapability get browser => get('browser');
  CloudCapability get managedWindows => get('managedWindows');

  factory CapabilityRegistry.fallback() => CapabilityRegistry.defaultCloudOS();

  factory CapabilityRegistry.fromMap(Map<String, dynamic> map) {
    final reg = CapabilityRegistry();
    for (final entry in map.entries) {
      if (entry.value is Map) {
        reg.register(CloudCapability.fromMap(
          Map<String, dynamic>.from(entry.value as Map),
        ));
      }
    }
    return reg;
  }

  factory CapabilityRegistry.defaultCloudOS({
    bool audioAvailable = true,
    bool brightnessAvailable = true,
    bool networkAvailable = true,
    bool bluetoothAvailable = true,
    bool bluetoothWritable = true,
  }) {
    final reg = CapabilityRegistry();
    reg.registerAll(<CloudCapability>[
      const CloudCapability(
        id: 'display',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['listModes', 'applyMode', 'restore'],
      ),
      CloudCapability(
        id: 'audio',
        supported: true,
        available: audioAvailable,
        enabled: true,
        writable: audioAvailable,
        features: ['volume', 'mute', 'outputSelection'],
      ),
      CloudCapability(
        id: 'brightness',
        supported: true,
        available: brightnessAvailable,
        enabled: brightnessAvailable,
        writable: brightnessAvailable,
        features: ['getBrightness', 'setBrightness'],
      ),
      CloudCapability(
        id: 'network',
        supported: true,
        available: networkAvailable,
        enabled: networkAvailable,
        writable: true,
        features: ['interfaces', 'wifiScan', 'status'],
      ),
      CloudCapability(
        id: 'bluetooth',
        supported: true,
        available: bluetoothAvailable,
        enabled: bluetoothAvailable,
        writable: bluetoothWritable,
        features: ['status', 'devices'],
        reason: bluetoothWritable
            ? null
            : (bluetoothAvailable
                ? 'Adaptador em modo de observação/somente leitura'
                : 'Adaptador Bluetooth não detectado'),
      ),
      const CloudCapability(
        id: 'nightLight',
        supported: true,
        available: true,
        enabled: false,
        writable: true,
        features: ['toggle', 'schedule'],
      ),
      const CloudCapability(
        id: 'focusMode',
        supported: true,
        available: true,
        enabled: false,
        writable: true,
        features: ['toggle', 'duration'],
      ),
      const CloudCapability(
        id: 'battery',
        supported: true,
        available: true,
        enabled: true,
        writable: false,
        features: ['status', 'powerProfile'],
      ),
      const CloudCapability(
        id: 'filesystem',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['list', 'create', 'delete', 'copy', 'move', 'openInternal'],
      ),
      const CloudCapability(
        id: 'recycleBin',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['list', 'restore', 'empty'],
      ),
      const CloudCapability(
        id: 'terminal',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['conpty', 'wsl', 'cmd', 'powershell'],
      ),
      const CloudCapability(
        id: 'browser',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['webview2', 'tabs', 'downloads', 'pdfViewer'],
      ),
      const CloudCapability(
        id: 'managedWindows',
        supported: true,
        available: true,
        enabled: true,
        writable: true,
        features: ['containment', 'jobObjects', 'lifecycleEvents'],
      ),
    ]);
    return reg;
  }
}
