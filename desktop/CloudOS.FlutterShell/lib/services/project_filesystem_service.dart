import '../models/file_models.dart';
import 'broker_filesystem_service.dart';
import 'cloudos_bridge.dart';
import 'cloudos_logger.dart';

class ProjectFilesystemSnapshot {
  const ProjectFilesystemSnapshot({
    required this.requestedPath,
    required this.path,
    required this.exists,
    required this.isDirectory,
    required this.type,
    required this.modifiedAt,
  });

  final String requestedPath;
  final String path;
  final bool exists;
  final bool isDirectory;
  final String type;
  final DateTime? modifiedAt;

  bool get available => exists && isDirectory;
}

/// Broker-backed inspection and preparation of user workspaces.
/// ProjectStore persists only CloudOS-owned metadata; this service is the sole
/// Projects-layer reader/mutator of user filesystem paths.
class ProjectFilesystemService {
  ProjectFilesystemService(CloudOSBridge bridge)
      : _filesystem = BrokerFilesystemService(bridge);

  final BrokerFilesystemService _filesystem;

  Future<String?> defaultWorkspaceRoot() {
    return _filesystem.knownFolderPath('home');
  }

  Future<ProjectFilesystemSnapshot> inspect(String rawPath) async {
    final resolved = await _filesystem.resolve(rawPath);
    if (!resolved.exists || resolved.metadata?.isDirectory != true) {
      return ProjectFilesystemSnapshot(
        requestedPath: rawPath,
        path: resolved.path,
        exists: resolved.exists,
        isDirectory: resolved.metadata?.isDirectory == true,
        type: resolved.exists ? 'Caminho inválido' : 'Pasta indisponível',
        modifiedAt: _parseDate(resolved.metadata?.modifiedFormatted),
      );
    }

    List<CloudFileItem> items = const <CloudFileItem>[];
    try {
      items = await _filesystem.list(
        resolved.path,
        showHidden: true,
        pageSize: 300,
      );
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'ProjectFilesystemService',
        'inspect.list:${resolved.path}',
        error,
        stackTrace,
      );
    }

    return ProjectFilesystemSnapshot(
      requestedPath: rawPath,
      path: resolved.path,
      exists: true,
      isDirectory: true,
      type: detectTypeFromItems(items),
      modifiedAt: _parseDate(resolved.metadata?.modifiedFormatted),
    );
  }

  Future<ProjectFilesystemSnapshot> prepare(
    String rawPath, {
    required bool createIfMissing,
  }) async {
    var resolved = await _filesystem.resolve(rawPath);
    if (!resolved.exists && createIfMissing) {
      resolved = await _filesystem.ensureDirectory(rawPath);
    }
    return inspect(resolved.path);
  }

  String detectTypeFromItems(Iterable<CloudFileItem> items) {
    final names = <String>{
      for (final item in items) item.name.trim().toLowerCase(),
    };

    if (names.contains('pubspec.yaml')) return 'Flutter / Dart';
    if (names.contains('package.json')) return 'Node.js / Web';
    if (names.contains('cargo.toml')) return 'Rust';
    if (names.contains('go.mod')) return 'Go';
    if (names.contains('cmakelists.txt')) return 'CMake / C++';
    if (names.contains('pyproject.toml') || names.contains('requirements.txt')) {
      return 'Python';
    }
    if (names.contains('.git')) return 'Git Repository';
    return 'Workspace';
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toLocal();
  }
}
