import 'package:flutter/material.dart';

enum LocationKind { windows, wsl, network, cloudos, virtual }

enum FileKind {
  folder,
  text,
  image,
  audio,
  video,
  document,
  archive,
  executable,
  code,
  unknown
}

enum FileSortField { name, size, modified, type }

class CloudFileItem {
  const CloudFileItem({
    required this.id,
    required this.name,
    required this.displayName,
    required this.path,
    required this.canonicalPath,
    required this.locationKind,
    required this.fileKind,
    required this.extension,
    required this.size,
    required this.sizeFormatted,
    required this.modifiedFormatted,
    required this.createdFormatted,
    required this.isDirectory,
    required this.isHidden,
    required this.isReadOnly,
    required this.isSystem,
    required this.isSymlink,
    required this.distro,
    required this.iconKey,
    this.canRename = true,
    this.canDelete = true,
    this.canOpen = true,
    this.canOpenWith = true,
    this.canCopy = true,
    this.canMove = true,
  });

  final String id;
  final String name;
  final String displayName;
  final String path;
  final String canonicalPath;
  final LocationKind locationKind;
  final FileKind fileKind;
  final String extension;
  final double size;
  final String sizeFormatted;
  final String modifiedFormatted;
  final String createdFormatted;
  final bool isDirectory;
  final bool isHidden;
  final bool isReadOnly;
  final bool isSystem;
  final bool isSymlink;
  final String distro;
  final String iconKey;
  final bool canRename;
  final bool canDelete;
  final bool canOpen;
  final bool canOpenWith;
  final bool canCopy;
  final bool canMove;

  IconData get icon {
    if (isDirectory) return Icons.folder_rounded;
    switch (fileKind) {
      case FileKind.text:
        return Icons.description_rounded;
      case FileKind.image:
        return Icons.image_rounded;
      case FileKind.audio:
        return Icons.audiotrack_rounded;
      case FileKind.video:
        return Icons.movie_rounded;
      case FileKind.document:
        return Icons.article_rounded;
      case FileKind.archive:
        return Icons.folder_zip_rounded;
      case FileKind.executable:
        return Icons.terminal_rounded;
      case FileKind.code:
        return Icons.code_rounded;
      case FileKind.folder:
        return Icons.folder_rounded;
      case FileKind.unknown:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color get iconColor {
    if (isDirectory) return const Color(0xFFF59E0B);
    switch (fileKind) {
      case FileKind.text:
        return const Color(0xFF38BDF8);
      case FileKind.image:
        return const Color(0xFFA78BFA);
      case FileKind.audio:
        return const Color(0xFFEC4899);
      case FileKind.video:
        return const Color(0xFFF43F5E);
      case FileKind.document:
        return const Color(0xFF60A5FA);
      case FileKind.archive:
        return const Color(0xFFFBBF24);
      case FileKind.executable:
        return const Color(0xFF34D399);
      case FileKind.code:
        return const Color(0xFF10B981);
      case FileKind.folder:
        return const Color(0xFFF59E0B);
      case FileKind.unknown:
        return const Color(0xFF94A3B8);
    }
  }

  factory CloudFileItem.fromJson(Map<String, Object?> json) {
    final lkStr = json['locationKind'] as String? ?? 'windows';
    final lk = lkStr == 'wsl'
        ? LocationKind.wsl
        : (lkStr == 'network' ? LocationKind.network : LocationKind.windows);

    final fkStr = json['fileKind'] as String? ?? 'unknown';
    FileKind fk = FileKind.unknown;
    if (fkStr == 'folder') fk = FileKind.folder;
    else if (fkStr == 'text') fk = FileKind.text;
    else if (fkStr == 'image') fk = FileKind.image;
    else if (fkStr == 'audio') fk = FileKind.audio;
    else if (fkStr == 'video') fk = FileKind.video;
    else if (fkStr == 'document') fk = FileKind.document;
    else if (fkStr == 'archive') fk = FileKind.archive;
    else if (fkStr == 'executable') fk = FileKind.executable;
    else if (fkStr == 'code') fk = FileKind.code;

    return CloudFileItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      canonicalPath: json['canonicalPath'] as String? ?? json['path'] as String? ?? '',
      locationKind: lk,
      fileKind: fk,
      extension: json['extension'] as String? ?? '',
      size: (json['size'] as num?)?.toDouble() ?? 0.0,
      sizeFormatted: json['sizeFormatted'] as String? ?? '',
      modifiedFormatted: json['modifiedTime'] as String? ?? '',
      createdFormatted: json['createdTime'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isReadOnly: json['isReadOnly'] as bool? ?? false,
      isSystem: json['isSystem'] as bool? ?? false,
      isSymlink: json['isSymlink'] as bool? ?? false,
      distro: json['distro'] as String? ?? '',
      iconKey: json['iconKey'] as String? ?? '',
      canRename: json['canRename'] as bool? ?? true,
      canDelete: json['canDelete'] as bool? ?? true,
      canOpen: json['canOpen'] as bool? ?? true,
      canOpenWith: json['canOpenWith'] as bool? ?? true,
      canCopy: json['canCopy'] as bool? ?? true,
      canMove: json['canMove'] as bool? ?? true,
    );
  }
}

class DriveInfoModel {
  const DriveInfoModel({
    required this.letter,
    required this.path,
    required this.label,
    required this.filesystem,
    required this.totalBytes,
    required this.freeBytes,
    required this.totalFormatted,
    required this.freeFormatted,
    required this.isRemovable,
    required this.isReady,
    required this.driveType,
  });

  final String letter;
  final String path;
  final String label;
  final String filesystem;
  final double totalBytes;
  final double freeBytes;
  final String totalFormatted;
  final String freeFormatted;
  final bool isRemovable;
  final bool isReady;
  final String driveType;

  factory DriveInfoModel.fromJson(Map<String, Object?> json) {
    return DriveInfoModel(
      letter: json['letter'] as String? ?? 'C:',
      path: json['path'] as String? ?? 'C:\\',
      label: json['label'] as String? ?? 'Disco Local',
      filesystem: json['filesystem'] as String? ?? 'NTFS',
      totalBytes: (json['totalBytes'] as num?)?.toDouble() ?? 0.0,
      freeBytes: (json['freeBytes'] as num?)?.toDouble() ?? 0.0,
      totalFormatted: json['totalFormatted'] as String? ?? '',
      freeFormatted: json['freeFormatted'] as String? ?? '',
      isRemovable: json['isRemovable'] as bool? ?? false,
      isReady: json['isReady'] as bool? ?? true,
      driveType: json['driveType'] as String? ?? 'fixed',
    );
  }
}

class KnownFolderModel {
  const KnownFolderModel({
    required this.id,
    required this.name,
    required this.path,
    required this.iconKey,
  });

  final String id;
  final String name;
  final String path;
  final String iconKey;

  IconData get icon {
    switch (iconKey) {
      case 'home': return Icons.home_rounded;
      case 'desktop': return Icons.desktop_windows_rounded;
      case 'documents': return Icons.description_rounded;
      case 'downloads': return Icons.download_rounded;
      case 'pictures': return Icons.image_rounded;
      case 'videos': return Icons.movie_rounded;
      case 'music': return Icons.audiotrack_rounded;
      case 'linux': return Icons.terminal_rounded;
      default: return Icons.folder_rounded;
    }
  }

  factory KnownFolderModel.fromJson(Map<String, Object?> json) {
    return KnownFolderModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      iconKey: json['iconKey'] as String? ?? 'folder',
    );
  }
}

class OpenWithAppModel {
  const OpenWithAppModel({
    required this.appId,
    required this.name,
    required this.platform,
    required this.distro,
    required this.iconKey,
    required this.isRecommended,
    required this.isDefault,
  });

  final String appId;
  final String name;
  final String platform;
  final String distro;
  final String iconKey;
  final bool isRecommended;
  final bool isDefault;

  IconData get icon {
    if (platform == 'linux') return Icons.terminal_rounded;
    if (iconKey == 'code') return Icons.code_rounded;
    if (iconKey == 'file_text') return Icons.description_rounded;
    if (iconKey == 'brush') return Icons.brush_rounded;
    return Icons.window_rounded;
  }

  factory OpenWithAppModel.fromJson(Map<String, Object?> json) {
    return OpenWithAppModel(
      appId: json['appId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? 'windows',
      distro: json['distro'] as String? ?? '',
      iconKey: json['iconKey'] as String? ?? 'window',
      isRecommended: json['isRecommended'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
