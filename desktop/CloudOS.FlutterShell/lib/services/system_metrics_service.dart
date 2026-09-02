import 'dart:async';
import 'dart:io';

import 'cloudos_bridge.dart';
import 'cloudos_logger.dart';

class DiskMetricItem {
  const DiskMetricItem({
    required this.name,
    required this.totalGb,
    required this.usedGb,
    required this.freeGb,
    required this.percentUsed,
  });

  final String name;
  final double totalGb;
  final double usedGb;
  final double freeGb;
  final double percentUsed;
}

class ProcessMetricItem {
  const ProcessMetricItem({
    required this.name,
    required this.pid,
    required this.ramMb,
    required this.cpuTimeSeconds,
  });

  final String name;
  final int pid;
  final double ramMb;
  final double cpuTimeSeconds;
}

class RealSystemMetrics {
  const RealSystemMetrics({
    required this.cpuPercent,
    required this.totalRamMb,
    required this.usedRamMb,
    required this.freeRamMb,
    required this.systemDrive,
    required this.disks,
    required this.activeProcesses,
    required this.uptimeSeconds,
    required this.uptimeFormatted,
    required this.isLive,
  });

  final double cpuPercent;
  final double totalRamMb;
  final double usedRamMb;
  final double freeRamMb;
  final String systemDrive;
  final List<DiskMetricItem> disks;
  final List<ProcessMetricItem> activeProcesses;
  final int uptimeSeconds;
  final String uptimeFormatted;
  final bool isLive;

  double get ramUsagePercent =>
      totalRamMb > 0 ? (usedRamMb / totalRamMb) * 100.0 : 0.0;

  DiskMetricItem? get systemDisk {
    if (disks.isEmpty) return null;
    final target = systemDrive.trim().toLowerCase();
    if (target.isNotEmpty) {
      for (final disk in disks) {
        if (disk.name.trim().toLowerCase() == target) return disk;
      }
    }
    return disks.first;
  }

  double get totalDiskGb => systemDisk?.totalGb ?? 0.0;
  double get freeDiskGb => systemDisk?.freeGb ?? 0.0;
  double get usedDiskGb => systemDisk?.usedGb ?? 0.0;
  double get diskUsagePercent => systemDisk?.percentUsed ?? 0.0;

  static const RealSystemMetrics initial = RealSystemMetrics(
    cpuPercent: 0,
    totalRamMb: 0,
    usedRamMb: 0,
    freeRamMb: 0,
    systemDrive: '',
    disks: <DiskMetricItem>[],
    activeProcesses: <ProcessMetricItem>[],
    uptimeSeconds: 0,
    uptimeFormatted: '--:--',
    isLive: false,
  );
}

class SystemMetricsService {
  SystemMetricsService._();
  static final SystemMetricsService instance = SystemMetricsService._();

  final CloudOSBridge _bridge = const CloudOSBridge();
  RealSystemMetrics _current = RealSystemMetrics.initial;
  RealSystemMetrics get current => _current;

  final StreamController<RealSystemMetrics> _controller =
      StreamController<RealSystemMetrics>.broadcast();
  Stream<RealSystemMetrics> get metricsStream => _controller.stream;

  Timer? _poller;
  bool _isPolling = false;
  int _activeListeners = 0;

  void start() {
    _activeListeners++;
    if (_poller != null && _poller!.isActive) return;
    unawaited(_pollOnce());
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _poller = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_pollOnce()),
      );
    }
  }

  void stop() {
    if (_activeListeners > 0) _activeListeners--;
    if (_activeListeners <= 0) {
      _poller?.cancel();
      _poller = null;
      _activeListeners = 0;
    }
  }

  void forceStop() {
    _poller?.cancel();
    _poller = null;
    _activeListeners = 0;
  }

  Future<void> _pollOnce() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;

      final raw = await _bridge.getSystemMetrics();
      if (raw.isEmpty) return;

      final cpuPercent =
          ((raw['cpuLoadPercent'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, 100.0)
              .toDouble();
      final totalRam =
          ((raw['ramTotalMb'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity).toDouble();
      final usedRam =
          ((raw['ramUsedMb'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity).toDouble();
      final freeRam =
          ((raw['ramFreeMb'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity).toDouble();
      final uptimeSec = ((raw['uptimeSeconds'] as num?)?.toInt() ?? 0).clamp(0, 1 << 62);
      final sysDrive = ((raw['systemDrive'] as String?) ?? '').trim();

      final diskItems = <DiskMetricItem>[];
      final rawDisks = raw['disks'];
      if (rawDisks is List) {
        for (final item in rawDisks) {
          if (item is! Map) continue;
          final name = (item['name'] as String? ?? '').trim();
          final total = ((item['totalGb'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, double.infinity)
              .toDouble();
          final used = ((item['usedGb'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, total > 0 ? total : double.infinity)
              .toDouble();
          final free = ((item['freeGb'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, total > 0 ? total : double.infinity)
              .toDouble();
          final percent = ((item['percentUsed'] as num?)?.toDouble() ??
                  (total > 0 ? (used / total) * 100.0 : 0.0))
              .clamp(0.0, 100.0)
              .toDouble();
          if (name.isEmpty || total <= 0) continue;
          diskItems.add(
            DiskMetricItem(
              name: name,
              totalGb: total,
              usedGb: used,
              freeGb: free,
              percentUsed: percent,
            ),
          );
        }
      }

      final procItems = <ProcessMetricItem>[];
      final rawProcs = raw['processes'];
      if (rawProcs is List) {
        for (final item in rawProcs) {
          if (item is! Map) continue;
          final pid = (item['pid'] as num?)?.toInt() ?? 0;
          final name = (item['name'] as String? ?? '').trim();
          if (pid <= 0 || name.isEmpty) continue;
          procItems.add(
            ProcessMetricItem(
              pid: pid,
              name: name,
              ramMb: ((item['memoryMb'] as num?)?.toDouble() ?? 0.0)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
              cpuTimeSeconds:
                  ((item['cpuTimeSeconds'] as num?)?.toDouble() ?? 0.0)
                      .clamp(0.0, double.infinity)
                      .toDouble(),
            ),
          );
        }
      }

      final hours = uptimeSec ~/ 3600;
      final mins = (uptimeSec % 3600) ~/ 60;
      final formattedUptime = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

      _current = RealSystemMetrics(
        cpuPercent: cpuPercent,
        totalRamMb: totalRam,
        usedRamMb: usedRam,
        freeRamMb: freeRam,
        systemDrive: sysDrive,
        disks: List<DiskMetricItem>.unmodifiable(diskItems),
        activeProcesses: List<ProcessMetricItem>.unmodifiable(procItems),
        uptimeSeconds: uptimeSec,
        uptimeFormatted: formattedUptime,
        isLive: true,
      );

      _controller.add(_current);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SystemMetricsService',
        'pollOnce',
        error,
        stackTrace,
      );
    } finally {
      _isPolling = false;
    }
  }
}
