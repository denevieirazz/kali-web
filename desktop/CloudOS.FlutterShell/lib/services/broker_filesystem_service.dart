import '../models/file_models.dart';
import 'cloudos_bridge.dart';
import 'cloudos_logger.dart';

class BrokerPathResolution {
  const BrokerPathResolution({
    required this.input,
    required this.path,
    required this.exists,
    this.metadata,
  });

  final String input;
  final String path;
  final bool exists;
  final CloudFileItem? metadata;

  bool get isDirectory => metadata?.isDirectory == true;
}

/// Small typed facade over Files V22 for widgets/services that need filesystem
/// truth without touching dart:io. All user-filesystem inspection/mutation is
/// delegated to the System Broker.
class BrokerFilesystemService {
  BrokerFilesystemService(this.bridge);

  final CloudOSBridge bridge;

  Future<BrokerPathResolution> resolve(
    String rawPath, {
    bool includeMetadata = true,
  }) async {
    final input = rawPath.trim();
    if (input.isEmpty) {
      return const BrokerPathResolution(input: '', path: '', exists: false);
    }

    try {
      final payload = await bridge.invokeBrokerRpc(
        'files.resolve',
        <String, Object?>{'path': input},
      );
      final resolved = (payload['resolvedPath'] as String? ?? input).trim();
      final exists = payload['exists'] == true;
      CloudFileItem? metadata;
      if (exists && includeMetadata && resolved.isNotEmpty) {
        try {
          metadata = await bridge.getFileMetadata(resolved);
        } catch (error, stackTrace) {
          CloudOSLogger.error(
            'BrokerFilesystemService',
            'resolve.metadata',
            error,
            stackTrace,
          );
        }
      }
      return BrokerPathResolution(
        input: input,
        path: resolved.isEmpty ? input : resolved,
        exists: exists,
        metadata: metadata,
      );
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'BrokerFilesystemService',
        'resolve',
        error,
        stackTrace,
      );
      return BrokerPathResolution(input: input, path: input, exists: false);
    }
  }

  Future<String?> knownFolderPath(String id) async {
    final wanted = id.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    try {
      final folders = await bridge.getKnownFolders();
      for (final folder in folders) {
        if (folder.id.trim().toLowerCase() == wanted) {
          final path = folder.path.trim();
          return path.isEmpty ? null : path;
        }
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'BrokerFilesystemService',
        'knownFolderPath:$wanted',
        error,
        stackTrace,
      );
    }
    return null;
  }

  Future<List<CloudFileItem>> list(
    String path, {
    bool showHidden = false,
    int pageSize = 300,
  }) async {
    return bridge.listFiles(
      path,
      pageSize: pageSize.clamp(20, 300).toInt(),
      showHidden: showHidden,
    );
  }

  /// Ensures a Windows/UNC directory path using only typed Files V22 calls.
  /// POSIX-only paths are rejected because they require an explicit WSL distro
  /// context and must not be guessed.
  Future<BrokerPathResolution> ensureDirectory(String rawPath) async {
    final initial = await resolve(rawPath);
    if (initial.exists) return initial;

    final plan = _buildCreationPlan(initial.path);
    if (plan == null) return initial;

    var parent = plan.root;
    final rootState = await resolve(parent);
    if (!rootState.exists ||
        (rootState.metadata != null && !rootState.metadata!.isDirectory)) {
      return initial;
    }

    for (final segment in plan.segments) {
      final candidate = join(parent, segment);
      final state = await resolve(candidate);
      if (state.exists) {
        if (state.metadata != null && !state.metadata!.isDirectory) {
          return initial;
        }
        parent = state.path;
        continue;
      }

      try {
        final created = await bridge.createFolder(parent, segment);
        if (!created) return initial;
      } catch (error, stackTrace) {
        CloudOSLogger.error(
          'BrokerFilesystemService',
          'ensureDirectory.create:$candidate',
          error,
          stackTrace,
        );
        return initial;
      }
      final createdState = await resolve(candidate);
      if (!createdState.exists) return initial;
      parent = createdState.path;
    }

    return resolve(parent);
  }

  String join(String parent, String child) {
    final cleanParent = parent.trim();
    final cleanChild = child.trim().replaceAll(RegExp(r'^[\\/]+'), '');
    if (cleanParent.isEmpty) return cleanChild;
    if (cleanChild.isEmpty) return cleanParent;
    if (cleanParent.endsWith(r'\') || cleanParent.endsWith('/')) {
      return '$cleanParent$cleanChild';
    }
    return '$cleanParent\\$cleanChild';
  }

  _DirectoryCreationPlan? _buildCreationPlan(String rawPath) {
    final normalized = rawPath.trim().replaceAll('/', r'\');
    if (normalized.isEmpty || normalized.startsWith('/')) return null;

    final drive = RegExp(r'^([A-Za-z]:)\\?(.*)$').firstMatch(normalized);
    if (drive != null) {
      final root = '${drive.group(1)}\\';
      final rest = drive.group(2) ?? '';
      final segments = rest
          .split(r'\')
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
      return _DirectoryCreationPlan(root: root, segments: segments);
    }

    if (normalized.startsWith(r'\\')) {
      final parts = normalized
          .substring(2)
          .split(r'\')
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
      if (parts.length < 2) return null;
      final root = '\\\\${parts[0]}\\${parts[1]}';
      return _DirectoryCreationPlan(
        root: root,
        segments: parts.skip(2).toList(growable: false),
      );
    }

    return null;
  }
}

class _DirectoryCreationPlan {
  const _DirectoryCreationPlan({required this.root, required this.segments});

  final String root;
  final List<String> segments;
}
