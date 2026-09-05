class CloudDisplayMode {
  const CloudDisplayMode({
    required this.width,
    required this.height,
    required this.frequency,
    required this.orientation,
    required this.bitsPerPel,
  });

  final int width;
  final int height;
  final int frequency;
  final int orientation;
  final int bitsPerPel;

  factory CloudDisplayMode.fromMap(Map<String, dynamic> map) {
    return CloudDisplayMode(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      frequency: (map['frequency'] as num?)?.toInt() ?? 60,
      orientation: (map['orientation'] as num?)?.toInt() ?? 0,
      bitsPerPel: (map['bitsPerPel'] as num?)?.toInt() ?? 32,
    );
  }

  Map<String, dynamic> toMap() => {
    'width': width,
    'height': height,
    'frequency': frequency,
    'orientation': orientation,
    'bitsPerPel': bitsPerPel,
  };
}

class CloudDisplayMonitor {
  const CloudDisplayMonitor({
    required this.deviceName,
    required this.friendlyName,
    required this.isPrimary,
    required this.width,
    required this.height,
    required this.frequency,
    required this.orientation,
    required this.bitsPerPel,
    required this.dpiX,
    required this.dpiY,
    required this.scale,
  });

  final String deviceName;
  final String friendlyName;
  final bool isPrimary;
  final int width;
  final int height;
  final int frequency;
  final int orientation;
  final int bitsPerPel;
  final int dpiX;
  final int dpiY;
  final double scale;

  factory CloudDisplayMonitor.fromMap(Map<String, dynamic> map) {
    return CloudDisplayMonitor(
      deviceName: map['deviceName'] as String? ?? '',
      friendlyName: map['friendlyName'] as String? ?? 'Monitor',
      isPrimary: map['isPrimary'] as bool? ?? false,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      frequency: (map['frequency'] as num?)?.toInt() ?? 60,
      orientation: (map['orientation'] as num?)?.toInt() ?? 0,
      bitsPerPel: (map['bitsPerPel'] as num?)?.toInt() ?? 32,
      dpiX: (map['dpiX'] as num?)?.toInt() ?? 96,
      dpiY: (map['dpiY'] as num?)?.toInt() ?? 96,
      scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class CloudAudioEndpoint {
  const CloudAudioEndpoint({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.isInput,
  });

  final String id;
  final String name;
  final bool isDefault;
  final bool isInput;

  factory CloudAudioEndpoint.fromMap(Map<String, dynamic> map) {
    return CloudAudioEndpoint(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      isDefault: map['isDefault'] as bool? ?? false,
      isInput: map['isInput'] as bool? ?? false,
    );
  }
}

class CloudAudioState {
  const CloudAudioState({
    this.available = false,
    this.volume = 0.0,
    this.isMuted = false,
    this.defaultDevice = '',
    this.endpoints = const [],
  });

  final bool available;
  final double volume;
  final bool isMuted;
  final String defaultDevice;
  final List<CloudAudioEndpoint> endpoints;

  factory CloudAudioState.fromMap(Map<String, dynamic> map) {
    final rawEndpoints = map['endpoints'] as List<dynamic>? ?? const [];
    return CloudAudioState(
      available: map['available'] as bool? ?? false,
      volume: (map['volume'] as num?)?.toDouble() ?? 0.0,
      isMuted: map['isMuted'] as bool? ?? false,
      defaultDevice: map['defaultDevice'] as String? ?? '',
      endpoints: rawEndpoints
          .whereType<Map<String, dynamic>>()
          .map(CloudAudioEndpoint.fromMap)
          .toList(),
    );
  }
}

class CloudPowerStatus {
  const CloudPowerStatus({
    this.acOnline = true,
    this.batteryPresent = false,
    this.batteryPercent = 100,
    this.isCharging = false,
    this.batterySaver = false,
    this.remainingSec = -1,
    this.powerSource = 'AC',
  });

  final bool acOnline;
  final bool batteryPresent;
  final int batteryPercent;
  final bool isCharging;
  final bool batterySaver;
  final int remainingSec;
  final String powerSource;

  factory CloudPowerStatus.fromMap(Map<String, dynamic> map) {
    return CloudPowerStatus(
      acOnline: map['ac_online'] as bool? ?? true,
      batteryPresent: map['battery_present'] as bool? ?? false,
      batteryPercent: (map['battery_percent'] as num?)?.toInt() ?? 100,
      isCharging: map['is_charging'] as bool? ?? false,
      batterySaver: map['battery_saver'] as bool? ?? false,
      remainingSec: (map['remaining_sec'] as num?)?.toInt() ?? -1,
      powerSource: map['power_source'] as String? ?? 'AC',
    );
  }
}

class CloudNetworkInterface {
  const CloudNetworkInterface({
    required this.id,
    required this.name,
    required this.friendlyName,
    required this.type,
    required this.status,
    required this.ipv4,
    required this.ipv6,
    required this.gateway,
    required this.dns,
    required this.isInternetConnected,
  });

  final String id;
  final String name;
  final String friendlyName;
  final String type;
  final String status;
  final String ipv4;
  final String ipv6;
  final String gateway;
  final String dns;
  final bool isInternetConnected;

  factory CloudNetworkInterface.fromMap(Map<String, dynamic> map) {
    return CloudNetworkInterface(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      friendlyName: map['friendlyName'] as String? ?? map['friendly_name'] as String? ?? '',
      type: map['type'] as String? ?? 'Ethernet',
      status: map['status'] as String? ?? 'Up',
      ipv4: map['ipv4'] as String? ?? '',
      ipv6: map['ipv6'] as String? ?? '',
      gateway: map['gateway'] as String? ?? '',
      dns: map['dns'] as String? ?? '',
      isInternetConnected: map['is_internet_connected'] as bool? ?? false,
    );
  }
}

class CloudWifiNetwork {
  const CloudWifiNetwork({
    required this.ssid,
    required this.signalQuality,
    required this.security,
    required this.isConnected,
  });

  final String ssid;
  final int signalQuality;
  final String security;
  final bool isConnected;

  factory CloudWifiNetwork.fromMap(Map<String, dynamic> map) {
    return CloudWifiNetwork(
      ssid: map['ssid'] as String? ?? '',
      signalQuality: (map['signal_quality'] as num?)?.toInt() ?? 0,
      security: map['security'] as String? ?? 'Secured',
      isConnected: map['is_connected'] as bool? ?? false,
    );
  }
}

class CloudBluetoothStatus {
  const CloudBluetoothStatus({
    this.available = false,
    this.enabled = false,
    this.radioName = '',
    this.address = '',
  });

  final bool available;
  final bool enabled;
  final String radioName;
  final String address;

  factory CloudBluetoothStatus.fromMap(Map<String, dynamic> map) {
    return CloudBluetoothStatus(
      available: map['available'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? false,
      radioName: map['radio_name'] as String? ?? '',
      address: map['address'] as String? ?? '',
    );
  }
}

class CloudStorageDrive {
  const CloudStorageDrive({
    required this.driveLetter,
    required this.volumeName,
    required this.fileSystem,
    required this.driveType,
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.percentUsed,
    required this.isRemovable,
  });

  final String driveLetter;
  final String volumeName;
  final String fileSystem;
  final String driveType;
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double percentUsed;
  final bool isRemovable;

  factory CloudStorageDrive.fromMap(Map<String, dynamic> map) {
    return CloudStorageDrive(
      driveLetter: map['drive_letter'] as String? ?? '',
      volumeName: map['volume_name'] as String? ?? '',
      fileSystem: map['file_system'] as String? ?? '',
      driveType: map['drive_type'] as String? ?? 'Fixed',
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (map['free_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (map['used_bytes'] as num?)?.toInt() ?? 0,
      percentUsed: (map['percent_used'] as num?)?.toDouble() ?? 0.0,
      isRemovable: map['is_removable'] as bool? ?? false,
    );
  }
}

class CloudPersonalizationSettings {
  const CloudPersonalizationSettings({
    this.theme = 'dark',
    this.accentColor = '#2563EB',
    this.transparencyEnabled = true,
    this.animationsEnabled = true,
    this.wallpaperPath = '',
    this.taskbarAlignment = 'center',
  });

  final String theme;
  final String accentColor;
  final bool transparencyEnabled;
  final bool animationsEnabled;
  final String wallpaperPath;
  final String taskbarAlignment;

  factory CloudPersonalizationSettings.fromMap(Map<String, dynamic> map) {
    return CloudPersonalizationSettings(
      theme: map['theme'] as String? ?? 'dark',
      accentColor: map['accent_color'] as String? ?? '#2563EB',
      transparencyEnabled: map['transparency_enabled'] as bool? ?? true,
      animationsEnabled: map['animations_enabled'] as bool? ?? true,
      wallpaperPath: map['wallpaper_path'] as String? ?? '',
      taskbarAlignment: map['taskbar_alignment'] as String? ?? 'center',
    );
  }

  Map<String, dynamic> toMap() => {
    'theme': theme,
    'accent_color': accentColor,
    'transparency_enabled': transparencyEnabled,
    'animations_enabled': animationsEnabled,
    'wallpaper_path': wallpaperPath,
    'taskbar_alignment': taskbarAlignment,
  };
}

class CloudDateTimeLocale {
  const CloudDateTimeLocale({
    required this.localTime,
    required this.timezoneName,
    required this.biasMinutes,
    required this.localeName,
  });

  final String localTime;
  final String timezoneName;
  final int biasMinutes;
  final String localeName;

  factory CloudDateTimeLocale.fromMap(Map<String, dynamic> map) {
    return CloudDateTimeLocale(
      localTime: map['local_time'] as String? ?? '',
      timezoneName: map['timezone_name'] as String? ?? 'UTC',
      biasMinutes: (map['bias_minutes'] as num?)?.toInt() ?? 0,
      localeName: map['locale_name'] as String? ?? 'pt-BR',
    );
  }
}

class CloudQuickSettingsState {
  const CloudQuickSettingsState({
    required this.audio,
    required this.power,
    required this.bluetooth,
    required this.personalization,
    required this.performanceProfile,
  });

  final CloudAudioState audio;
  final CloudPowerStatus power;
  final CloudBluetoothStatus bluetooth;
  final CloudPersonalizationSettings personalization;
  final String performanceProfile;

  factory CloudQuickSettingsState.fromMap(Map<String, dynamic> map) {
    return CloudQuickSettingsState(
      audio: map['audio'] is Map
          ? CloudAudioState.fromMap(Map<String, dynamic>.from(map['audio'] as Map))
          : const CloudAudioState(),
      power: map['power'] is Map
          ? CloudPowerStatus.fromMap(Map<String, dynamic>.from(map['power'] as Map))
          : const CloudPowerStatus(),
      bluetooth: map['bluetooth'] is Map
          ? CloudBluetoothStatus.fromMap(Map<String, dynamic>.from(map['bluetooth'] as Map))
          : const CloudBluetoothStatus(),
      personalization: map['personalization'] is Map
          ? CloudPersonalizationSettings.fromMap(Map<String, dynamic>.from(map['personalization'] as Map))
          : const CloudPersonalizationSettings(),
      performanceProfile: map['performanceProfile'] as String? ?? 'balanced',
    );
  }
}
