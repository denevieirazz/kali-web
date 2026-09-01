import 'dart:convert';
import 'dart:io';
import '../models/window_model.dart';
import 'cloudos_logger.dart';

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  File get _sessionFile {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? r'C:\CloudOS';
    final dir = Directory('$localAppData\\CloudOS');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}\\desktop_session.json');
  }

  Future<void> saveSession({
    required List<CloudWindow> windows,
    required int activeWorkspace,
  }) async {
    try {
      final data = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'activeWorkspace': activeWorkspace,
        'windows': windows.map((w) => <String, dynamic>{
          'id': w.id,
          'appId': w.appId,
          'title': w.title,
          'x': w.x,
          'y': w.y,
          'width': w.width,
          'height': w.height,
          'minimized': w.minimized,
          'maximized': w.maximized,
          'workspaceIndex': w.workspaceIndex,
        }).toList(),
      };

      await _sessionFile.writeAsString(jsonEncode(data), flush: true);
    } catch (e, st) {
      CloudOSLogger.error('SessionService', 'saveSession', e, st);
    }
  }

  Future<Map<String, dynamic>?> loadSession() async {
    try {
      final file = _sessionFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e, st) {
      CloudOSLogger.error('SessionService', 'loadSession', e, st);
    }
    return null;
  }
}
