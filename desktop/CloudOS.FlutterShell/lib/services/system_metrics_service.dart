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

  double get ramUsagePercent => totalRamMb > 0 ? (usedRamMb / totalRamMb) * 100.0 : 0.0;
  
  double get totalDiskGb => disks.isNotEmpty ? disks.first.totalGb : 0.0;
  double get freeDiskGb => disks.isNotEmpty ? disks.first.freeGb : 0.0;
  double get usedDiskGb => disks.isNotEmpty ? disks.first.usedGb : 0.0;
  double get diskUsagePercent => totalDiskGb > 0 ? (usedDiskGb / totalDiskGb) * 100.0 : 0.0;

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
    _pollOnce();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _poller = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
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
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _isPolling = false;
        return;
      }

      final raw = await _bridge.getSystemMetrics();
      if (raw.isEmpty) {
        _isPolling = false;
        return;
      }

      final cpuPercent = (raw['cpuLoadPercent'] as num?)?.toDouble() ?? 0.0;
      final totalRam = (raw['ramTotalMb'] as num?)?.toDouble() ?? 0.0;
      final usedRam = (raw['ramUsedMb'] as num?)?.toDouble() ?? 0.0;
      final freeRam = (raw['ramFreeMb'] as num?)?.toDouble() ?? 0.0;
      final uptimeSec = (raw['uptimeSeconds'] as num?)?.toInt() ?? 0;
      final sysDrive = (raw['systemDrive'] as String?) ?? '';

      final List<DiskMetricItem> diskItems = <DiskMetricItem>[];
      final rawDisks = raw['disks'];
      if (rawDisks is List) {
        for (final item in rawDisks) {
          if (item is Map) {
            diskItems.add(DiskMetricItem(
              name: item['name'] as String? ?? '',
              totalGb: (item['totalGb'] as num?)?.toDouble() ?? 0.0,
              usedGb: (item['usedGb'] as num?)?.toDouble() ?? 0.0,
              freeGb: (item['freeGb'] as num?)?.toDouble() ?? 0.0,
              percentUsed: (item['percentUsed'] as num?)?.toDouble() ?? 0.0,
            ));
          }
        }
      }

      final List<ProcessMetricItem> procItems = <ProcessMetricItem>[];
      final rawProcs = raw['processes'];
      if (rawProcs is List) {
        for (final item in rawProcs) {
          if (item is Map) {
            procItems.add(ProcessMetricItem(
              pid: (item['pid'] as num?)?.toInt() ?? 0,
              name: item['name'] as String? ?? 'Process',
              ramMb: (item['memoryMb'] as num?)?.toDouble() ?? 0.0,
              cpuTimeSeconds: (item['cpuTimeSeconds'] as num?)?.toDouble() ?? 0.0,
            ));
          }
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
        disks: diskItems,
        activeProcesses: procItems,
        uptimeSeconds: uptimeSec,
        uptimeFormatted: formattedUptime,
        isLive: true,
      );

      _controller.add(_current);
    } catch (e, st) {
      CloudOSLogger.error('SystemMetricsService', 'pollOnce', e, st);
    } finally {
      _isPolling = false;
    }
  }
}
