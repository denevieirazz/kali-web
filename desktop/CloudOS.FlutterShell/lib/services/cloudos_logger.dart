import 'dart:io';

enum LogLevel {
  info,
  warning,
  error,
}

class CloudOSLogger {
  CloudOSLogger._();

  static File? _logFile;
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? r'C:\Users\Default\AppData\Local';
      final logDir = Directory('$localAppData\\CloudOS\\Logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      _logFile = File('${logDir.path}\\cloudos_desktop.log');

      // Simple rotation if log file is larger than 5MB
      if (_logFile!.existsSync() && _logFile!.lengthSync() > 5 * 1024 * 1024) {
        final backup = File('${logDir.path}\\cloudos_desktop.old.log');
        if (backup.existsSync()) backup.deleteSync();
        _logFile!.renameSync(backup.path);
        _logFile = File('${logDir.path}\\cloudos_desktop.log');
      }
    } catch (_) {
      // Non-blocking fallback
    }
  }

  static void info(String subsystem, String operation, [String? details]) {
    _write(LogLevel.info, subsystem, operation, details);
  }

  static void warn(String subsystem, String operation, [String? details]) {
    _write(LogLevel.warning, subsystem, operation, details);
  }

  static void error(String subsystem, String operation, [dynamic error, StackTrace? stack]) {
    final details = error != null ? '$error${stack != null ? '\n$stack' : ''}' : null;
    _write(LogLevel.error, subsystem, operation, details);
  }

  static void _write(LogLevel level, String subsystem, String operation, String? details) {
    _ensureInitialized();
    final now = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase();
    final message = details != null && details.isNotEmpty
        ? '[$now] [$levelStr] [$subsystem] [$operation]: $details\n'
        : '[$now] [$levelStr] [$subsystem] [$operation]\n';

    // Avoid logging sensitive keywords
    if (message.contains('password') || message.contains('token') || message.contains('secret')) {
      return;
    }

    try {
      _logFile?.writeAsStringSync(message, mode: FileMode.append, flush: false);
    } catch (_) {}
  }
}
