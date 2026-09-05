import 'dart:convert';
import 'package:flutter/material.dart';

enum CloudWindowType {
  files,
  terminal,
  browser,
  settings,
  notes,
  calculator,
  taskManager,
  externalWin32,
  externalLinux,
}

class CloudWindow {
  CloudWindow({
    required this.id,
    required this.title,
    required this.icon,
    required this.type,
    required this.position,
    required this.size,
    this.minSize = const Size(420, 300),
    this.isMinimized = false,
    this.isMaximized = false,
    this.isSnappedLeft = false,
    this.isSnappedRight = false,
    this.preMaximizedPosition,
    this.preMaximizedSize,
    this.zIndex = 0,
    this.platform = 'cloudos',
    this.hwnd = 0,
    this.pid = 0,
    this.appId = '',
    this.isFullscreen = false,
    this.isVisible = true,
    this.isFocused = false,
    this.workspaceId = 1,
    this.monitorId = '',
    this.ownerHwnd = 0,
    this.capabilities = const <String>[
      'minimize',
      'maximize',
      'close',
      'snap',
      'resize',
      'move',
    ],
  });

  final String id;
  final String title;
  final IconData icon;
  final CloudWindowType type;
  Offset position;
  Size size;
  final Size minSize;
  bool isMinimized;
  bool isMaximized;
  bool isSnappedLeft;
  bool isSnappedRight;
  Offset? preMaximizedPosition;
  Size? preMaximizedSize;
  int zIndex;

  // Window Manager v23 additions
  final String platform; // "cloudos", "windows", "linux"
  final int hwnd;
  final int pid;
  final String appId;
  bool isFullscreen;
  bool isVisible;
  bool isFocused;
  int workspaceId;
  String monitorId;
  int ownerHwnd;
  List<String> capabilities;

  bool get minimized => isMinimized;
  set minimized(bool val) => isMinimized = val;

  bool get maximized => isMaximized;
  set maximized(bool val) => isMaximized = val;

  bool get fullscreen => isFullscreen;
  set fullscreen(bool val) => isFullscreen = val;

  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  CloudWindow copyWith({
    String? id,
    String? title,
    IconData? icon,
    CloudWindowType? type,
    Offset? position,
    Size? size,
    Size? minSize,
    bool? isMinimized,
    bool? isMaximized,
    bool? isSnappedLeft,
    bool? isSnappedRight,
    Offset? preMaximizedPosition,
    Size? preMaximizedSize,
    int? zIndex,
    String? platform,
    int? hwnd,
    int? pid,
    String? appId,
    bool? isFullscreen,
    bool? isVisible,
    bool? isFocused,
    int? workspaceId,
    String? monitorId,
    int? ownerHwnd,
    List<String>? capabilities,
  }) {
    return CloudWindow(
      id: id ?? this.id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      position: position ?? this.position,
      size: size ?? this.size,
      minSize: minSize ?? this.minSize,
      isMinimized: isMinimized ?? this.isMinimized,
      isMaximized: isMaximized ?? this.isMaximized,
      isSnappedLeft: isSnappedLeft ?? this.isSnappedLeft,
      isSnappedRight: isSnappedRight ?? this.isSnappedRight,
      preMaximizedPosition: preMaximizedPosition ?? this.preMaximizedPosition,
      preMaximizedSize: preMaximizedSize ?? this.preMaximizedSize,
      zIndex: zIndex ?? this.zIndex,
      platform: platform ?? this.platform,
      hwnd: hwnd ?? this.hwnd,
      pid: pid ?? this.pid,
      appId: appId ?? this.appId,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      isVisible: isVisible ?? this.isVisible,
      isFocused: isFocused ?? this.isFocused,
      workspaceId: workspaceId ?? this.workspaceId,
      monitorId: monitorId ?? this.monitorId,
      ownerHwnd: ownerHwnd ?? this.ownerHwnd,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  factory CloudWindow.fromJson(Map<String, dynamic> json) {
    final platform = json['platform'] as String? ?? 'windows';
    final appId = json['appId'] as String? ?? '';
    final title = json['title'] as String? ?? 'Janela';
    final bounds = json['bounds'] is Map ? Map<String, dynamic>.from(json['bounds'] as Map) : null;
    final x = (bounds?['x'] as num?)?.toDouble() ?? 100.0;
    final y = (bounds?['y'] as num?)?.toDouble() ?? 100.0;
    final w = (bounds?['width'] as num?)?.toDouble() ?? 800.0;
    final h = (bounds?['height'] as num?)?.toDouble() ?? 600.0;

    final isMin = json['minimized'] as bool? ?? (json['state'] == 'minimized');
    final isMax = json['maximized'] as bool? ?? (json['state'] == 'maximized');
    final isFs = json['fullscreen'] as bool? ?? (json['state'] == 'fullscreen');

    IconData icon;
    CloudWindowType type;
    if (platform == 'linux') {
      type = CloudWindowType.externalLinux;
      icon = Icons.terminal_rounded;
    } else if (platform == 'cloudos') {
      type = CloudWindowType.files;
      icon = Icons.folder_rounded;
    } else {
      type = CloudWindowType.externalWin32;
      final lowerAppId = appId.toLowerCase();
      if (lowerAppId.contains('notepad')) {
        icon = Icons.note_alt_rounded;
      } else if (lowerAppId.contains('calc')) {
        icon = Icons.calculate_rounded;
      } else {
        icon = Icons.window_rounded;
      }
    }

    final rawHwnd = json['hwnd'];
    final int hwndVal = rawHwnd is num ? rawHwnd.toInt() : (int.tryParse(rawHwnd?.toString() ?? '0') ?? 0);
    final rawPid = json['pid'];
    final int pidVal = rawPid is num ? rawPid.toInt() : (int.tryParse(rawPid?.toString() ?? '0') ?? 0);

    return CloudWindow(
      id: json['id'] as String? ?? (hwndVal != 0 ? 'hwnd-$hwndVal' : 'win-${DateTime.now().millisecondsSinceEpoch}'),
      title: title,
      icon: icon,
      type: type,
      position: Offset(x, y),
      size: Size(w, h),
      isMinimized: isMin,
      isMaximized: isMax,
      platform: platform,
      hwnd: hwndVal,
      pid: pidVal,
      appId: appId,
      isFullscreen: isFs,
      isVisible: json['visible'] as bool? ?? true,
      isFocused: json['focused'] as bool? ?? false,
      workspaceId: (json['workspaceId'] as num?)?.toInt() ?? 1,
      monitorId: json['monitorId'] as String? ?? '',
      ownerHwnd: (json['owner'] as num?)?.toInt() ?? 0,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>['minimize', 'maximize', 'close', 'snap', 'resize', 'move'],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'platform': platform,
        'pid': pid,
        'hwnd': hwnd,
        'title': title,
        'appId': appId,
        'state': isFullscreen
            ? 'fullscreen'
            : (isMaximized ? 'maximized' : (isMinimized ? 'minimized' : 'normal')),
        'bounds': <String, dynamic>{
          'x': position.dx.toInt(),
          'y': position.dy.toInt(),
          'width': size.width.toInt(),
          'height': size.height.toInt(),
        },
        'minimized': isMinimized,
        'maximized': isMaximized,
        'fullscreen': isFullscreen,
        'visible': isVisible,
        'focused': isFocused,
        'workspaceId': workspaceId,
        'monitorId': monitorId,
        'owner': ownerHwnd,
        'capabilities': capabilities,
      };
}

class CloudMonitorRecord {
  const CloudMonitorRecord({
    required this.id,
    required this.name,
    required this.bounds,
    required this.workArea,
    required this.isPrimary,
    required this.scaleFactor,
  });

  final String id;
  final String name;
  final Rect bounds;
  final Rect workArea;
  final bool isPrimary;
  final double scaleFactor;

  factory CloudMonitorRecord.fromJson(Map<String, dynamic> json) {
    Rect parseRect(dynamic raw) {
      if (raw is! Map) return Rect.zero;
      final m = Map<String, dynamic>.from(raw);
      return Rect.fromLTWH(
        (m['x'] as num?)?.toDouble() ?? 0,
        (m['y'] as num?)?.toDouble() ?? 0,
        (m['width'] as num?)?.toDouble() ?? 1920,
        (m['height'] as num?)?.toDouble() ?? 1080,
      );
    }

    return CloudMonitorRecord(
      id: json['id'] as String? ?? 'monitor-0',
      name: json['name'] as String? ?? 'Display',
      bounds: parseRect(json['bounds']),
      workArea: parseRect(json['workArea']),
      isPrimary: json['isPrimary'] as bool? ?? false,
      scaleFactor: (json['scaleFactor'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'bounds': <String, dynamic>{
          'x': bounds.left.toInt(),
          'y': bounds.top.toInt(),
          'width': bounds.width.toInt(),
          'height': bounds.height.toInt(),
        },
        'workArea': <String, dynamic>{
          'x': workArea.left.toInt(),
          'y': workArea.top.toInt(),
          'width': workArea.width.toInt(),
          'height': workArea.height.toInt(),
        },
        'isPrimary': isPrimary,
        'scaleFactor': scaleFactor,
      };
}

class CloudWindowSnapshot {
  const CloudWindowSnapshot({
    required this.windows,
    required this.monitors,
    required this.currentWorkspace,
    required this.sequence,
    required this.timestamp,
  });

  final List<CloudWindow> windows;
  final List<CloudMonitorRecord> monitors;
  final int currentWorkspace;
  final int sequence;
  final int timestamp;

  static const empty = CloudWindowSnapshot(
    windows: <CloudWindow>[],
    monitors: <CloudMonitorRecord>[],
    currentWorkspace: 1,
    sequence: 0,
    timestamp: 0,
  );

  factory CloudWindowSnapshot.fromJson(Map<String, dynamic> json) {
    final rawWins = (json['windows'] as List<dynamic>?) ?? const [];
    final rawMons = (json['monitors'] as List<dynamic>?) ?? const [];
    return CloudWindowSnapshot(
      windows: rawWins
          .whereType<Map>()
          .map((m) => CloudWindow.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false),
      monitors: rawMons
          .whereType<Map>()
          .map((m) => CloudMonitorRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false),
      currentWorkspace: (json['currentWorkspace'] as num?)?.toInt() ?? 1,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  factory CloudWindowSnapshot.fromJsonString(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return CloudWindowSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return CloudWindowSnapshot.empty;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'windows': windows.map((w) => w.toJson()).toList(growable: false),
        'monitors': monitors.map((m) => m.toJson()).toList(growable: false),
        'currentWorkspace': currentWorkspace,
        'sequence': sequence,
        'timestamp': timestamp,
      };
}
