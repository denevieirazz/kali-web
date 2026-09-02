import '../models/file_models.dart';
import 'broker_filesystem_service.dart';
import 'cloudos_bridge.dart';

class CloudOSDriveSnapshot {
  const CloudOSDriveSnapshot({
    required this.path,
    required this.items,
  });

  final String path;
  final List<CloudFileItem> items;
}

/// Resolves and enumerates the local CloudOS Drive exclusively through Files
/// V22. It creates only the required directory structure and never fabricates
/// starter documents or claims cloud synchronization.
class CloudOSDriveService {
  CloudOSDriveService(CloudOSBridge bridge)
      : _filesystem = BrokerFilesystemService(bridge);

  final BrokerFilesystemService _filesystem;

  Future<String?> drivePath({bool ensureExists = true}) async {
    final profile = await _filesystem.knownFolderPath('home');
    if (profile == null || profile.trim().isEmpty) return null;

    final target = _filesystem.join(
      _filesystem.join(
        _filesystem.join(profile, 'AppData'),
        'Local',
      ),
      'CloudOS',
    );
    final drive = _filesystem.join(target, 'Drive');
    if (!ensureExists) return drive;

    final resolved = await _filesystem.ensureDirectory(drive);
    if (!resolved.exists || !resolved.isDirectory) return null;
    return resolved.path;
  }

  Future<CloudOSDriveSnapshot?> load() async {
    final path = await drivePath();
    if (path == null) return null;
    final items = await _filesystem.list(path, pageSize: 300);
    return CloudOSDriveSnapshot(
      path: path,
      items: List<CloudFileItem>.unmodifiable(items),
    );
  }
}
