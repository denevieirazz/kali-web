class WslDistroInfo {
  const WslDistroInfo({
    required this.id,
    required this.name,
    required this.guid,
    required this.version,
    required this.state,
    required this.basePath,
    required this.defaultUid,
    required this.flags,
    required this.isDefault,
  });

  factory WslDistroInfo.fromMap(Map<Object?, Object?> map) {
    return WslDistroInfo(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      guid: map['guid'] as String? ?? '',
      version: (map['version'] as num?)?.toInt() ?? 2,
      state: map['state'] as String? ?? 'stopped',
      basePath: map['basePath'] as String? ?? '',
      defaultUid: (map['defaultUid'] as num?)?.toInt() ?? 1000,
      flags: (map['flags'] as num?)?.toInt() ?? 0,
      isDefault: map['isDefault'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String guid;
  final int version;
  final String state;
  final String basePath;
  final int defaultUid;
  final int flags;
  final bool isDefault;

  bool get isRunning => state == 'running';
}

class PathTranslation {
  const PathTranslation({
    required this.originalPath,
    required this.translatedPath,
    required this.target,
    required this.distro,
    required this.exists,
  });

  factory PathTranslation.fromMap(Map<Object?, Object?> map) {
    return PathTranslation(
      originalPath: map['originalPath'] as String? ?? '',
      translatedPath: map['translatedPath'] as String? ?? '',
      target: map['target'] as String? ?? 'linux',
      distro: map['distro'] as String? ?? '',
      exists: map['exists'] as bool? ?? false,
    );
  }

  final String originalPath;
  final String translatedPath;
  final String target;
  final String distro;
  final bool exists;
}

class MountPoint {
  const MountPoint({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.filesystem,
    required this.isReady,
  });

  factory MountPoint.fromMap(Map<Object?, Object?> map) {
    return MountPoint(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      path: map['path'] as String? ?? '',
      type: map['type'] as String? ?? 'windows',
      filesystem: map['filesystem'] as String? ?? '',
      isReady: map['isReady'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String path;
  final String type;
  final String filesystem;
  final bool isReady;
}

class AppLaunchStatus {
  const AppLaunchStatus({
    required this.id,
    required this.status,
    required this.launched,
    required this.platform,
    required this.target,
    required this.message,
  });

  factory AppLaunchStatus.fromMap(Map<Object?, Object?> map) {
    return AppLaunchStatus(
      id: map['id'] as String? ?? '',
      status: map['status'] as String? ?? 'failed',
      launched: map['launched'] as bool? ?? false,
      platform: map['platform'] as String? ?? '',
      target: map['target'] as String? ?? '',
      message: map['message'] as String? ?? '',
    );
  }

  final String id;
  final String status;
  final bool launched;
  final String platform;
  final String target;
  final String message;

  bool get isSuccess => launched || status == 'running';
}
