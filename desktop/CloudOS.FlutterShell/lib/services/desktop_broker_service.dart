import '../models/file_models.dart';
import 'cloudos_bridge.dart';
import 'cloudos_logger.dart';

/// Broker-backed desktop filesystem operations used by the shell.
///
/// The presentation layer must not derive USERPROFILE/Desktop or mutate the
/// filesystem directly. Known-folder discovery and folder creation stay on the
/// existing typed Files V22 RPC path.
class DesktopBrokerService {
  DesktopBrokerService(this._bridge);

  final CloudOSBridge _bridge;
  String? _cachedDesktopPath;

  Future<String?> desktopPath({bool refresh = false}) async {
    if (!refresh && _cachedDesktopPath?.isNotEmpty == true) {
      return _cachedDesktopPath;
    }
    try {
      final folders = await _bridge.getKnownFolders();
      KnownFolderModel? desktop;
      for (final folder in folders) {
        if (folder.id.toLowerCase() == 'desktop') {
          desktop = folder;
          break;
        }
      }
      final path = desktop?.path.trim() ?? '';
      _cachedDesktopPath = path.isEmpty ? null : path;
      return _cachedDesktopPath;
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'DesktopBrokerService',
        'desktopPath',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<String?> createUniqueFolder({
    String baseName = 'Nova Pasta',
  }) async {
    final desktop = await desktopPath();
    if (desktop == null) return null;

    try {
      final items = await _bridge.listFiles(
        desktop,
        pageSize: 300,
        showHidden: true,
      );
      final existing = items.map((item) => item.name.toLowerCase()).toSet();
      var suffix = 1;
      var candidate = baseName;
      while (existing.contains(candidate.toLowerCase()) && suffix < 10000) {
        suffix++;
        candidate = '$baseName ($suffix)';
      }
      if (suffix >= 10000) return null;
      final created = await _bridge.createFolder(desktop, candidate);
      if (!created) return null;
      return _joinWindows(desktop, candidate);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'DesktopBrokerService',
        'createUniqueFolder',
        error,
        stackTrace,
      );
      return null;
    }
  }

  String _joinWindows(String parent, String child) {
    if (parent.endsWith(r'\')) return '$parent$child';
    return '$parent\\$child';
  }
}
