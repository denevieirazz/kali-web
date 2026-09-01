import '../../models/cloud_file_item.dart';

CloudFileSource _sourceFromNative(Object? raw) {
  return switch (raw) {
    'linux' => CloudFileSource.linux,
    'cloudDrive' => CloudFileSource.cloudDrive,
    'trash' => CloudFileSource.trash,
    _ => CloudFileSource.windows,
  };
}

CloudFileItem cloudFileFromNative(Map<Object?, Object?> raw) {
  final name = raw['name'] as String? ?? '';
  final path = raw['path'] as String? ?? '';
  final extension = raw['extension'] as String?;

  return CloudFileItem(
    name: name,
    path: path,
    isFolder: raw['isFolder'] as bool? ?? false,
    sizeFormatted: raw['sizeFormatted'] as String? ?? '',
    modifiedFormatted: raw['modifiedFormatted'] as String? ?? '',
    source: _sourceFromNative(raw['source']),
    extension: extension == null || extension.isEmpty ? null : extension,
  );
}
