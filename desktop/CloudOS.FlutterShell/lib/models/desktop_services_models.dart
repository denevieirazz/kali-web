class CloudClipboardItem {
  const CloudClipboardItem({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.preview,
    this.fullText = '',
    this.files = const [],
    this.dataBytes = 0,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  final int id;
  final String timestamp;
  final String type; // "text", "image", "files"
  final String preview;
  final String fullText;
  final List<String> files;
  final int dataBytes;
  final int imageWidth;
  final int imageHeight;

  bool get isText => type == 'text';
  bool get isImage => type == 'image';
  bool get isFiles => type == 'files';

  factory CloudClipboardItem.fromMap(Map<String, dynamic> map) {
    final rawFiles = map['files'] as List<dynamic>? ?? const [];
    return CloudClipboardItem(
      id: (map['id'] as num?)?.toInt() ?? 0,
      timestamp: map['timestamp'] as String? ?? '',
      type: map['type'] as String? ?? 'text',
      preview: map['preview'] as String? ?? '',
      fullText: map['full_text'] as String? ?? '',
      files: rawFiles.whereType<String>().toList(),
      dataBytes: (map['data_bytes'] as num?)?.toInt() ?? 0,
      imageWidth: (map['image_width'] as num?)?.toInt() ?? 0,
      imageHeight: (map['image_height'] as num?)?.toInt() ?? 0,
    );
  }
}

class CloudFileAssociation {
  const CloudFileAssociation({
    required this.extension,
    required this.defaultAppId,
    required this.friendlyName,
    this.candidateApps = const [],
  });

  final String extension;
  final String defaultAppId;
  final String friendlyName;
  final List<String> candidateApps;

  factory CloudFileAssociation.fromMap(Map<String, dynamic> map) {
    final rawApps = map['candidate_apps'] as List<dynamic>? ?? const [];
    return CloudFileAssociation(
      extension: map['extension'] as String? ?? '',
      defaultAppId: map['default_app_id'] as String? ?? '',
      friendlyName: map['friendly_name'] as String? ?? '',
      candidateApps: rawApps.whereType<String>().toList(),
    );
  }
}

class CloudDesktopNotification {
  const CloudDesktopNotification({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.message,
    this.severity = 'info',
    this.appId = '',
    this.read = false,
  });

  final int id;
  final String timestamp;
  final String title;
  final String message;
  final String severity; // "info", "warning", "error", "system"
  final String appId;
  final bool read;

  factory CloudDesktopNotification.fromMap(Map<String, dynamic> map) {
    return CloudDesktopNotification(
      id: (map['id'] as num?)?.toInt() ?? 0,
      timestamp: map['timestamp'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      severity: map['severity'] as String? ?? 'info',
      appId: map['app_id'] as String? ?? '',
      read: map['read'] as bool? ?? false,
    );
  }
}
