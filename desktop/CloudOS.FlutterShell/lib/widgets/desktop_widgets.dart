import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/system_metrics_service.dart';

class DesktopClockWidget extends StatefulWidget {
  const DesktopClockWidget({super.key});

  @override
  State<DesktopClockWidget> createState() => _DesktopClockWidgetState();
}

class _DesktopClockWidgetState extends State<DesktopClockWidget> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatWeekday(int weekday) {
    const days = <String>[
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    return days[(weekday - 1) % 7];
  }

  String _formatMonth(int month) {
    const months = <String>[
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return months[(month - 1) % 12];
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    final dateFormatted = '${_formatWeekday(_now.weekday)}, ${_now.day} de ${_formatMonth(_now.month)}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0x730A0E18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '$h:$m',
                      style: const TextStyle(
                        fontFamily: 'Segoe UI',
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ':$s',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: CloudOSColors.neonCyan,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dateFormatted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.schedule_rounded, size: 12, color: CloudOSColors.neonCyan),
                      SizedBox(width: 6),
                      Text(
                        'Hora Local do Sistema',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopMetricsWidget extends StatefulWidget {
  const DesktopMetricsWidget({super.key, required this.bridge});

  final CloudOSBridge bridge;

  @override
  State<DesktopMetricsWidget> createState() => _DesktopMetricsWidgetState();
}

class _DesktopMetricsWidgetState extends State<DesktopMetricsWidget> {
  StreamSubscription<RealSystemMetrics>? _sub;
  RealSystemMetrics _metrics = SystemMetricsService.instance.current;

  @override
  void initState() {
    super.initState();
    SystemMetricsService.instance.start();
    _sub = SystemMetricsService.instance.metricsStream.listen((m) {
      if (mounted) setState(() => _metrics = m);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemMetricsService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cpuFraction = (_metrics.cpuPercent / 100.0).clamp(0.0, 1.0);
    final ramFraction = (_metrics.ramUsagePercent / 100.0).clamp(0.0, 1.0);
    final diskFraction = (_metrics.diskUsagePercent / 100.0).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x730A0E18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.speed_rounded, size: 13, color: _metrics.isLive ? CloudOSColors.neonEmerald : CloudOSColors.neonCyan),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _metrics.isLive ? 'Performance Real do Windows' : 'Performance do Sistema',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _buildGauge(
                    label: 'CPU',
                    percent: cpuFraction,
                    display: '${_metrics.cpuPercent.toStringAsFixed(0)}%',
                    color: CloudOSColors.neonCyan,
                  ),
                  _buildGauge(
                    label: 'RAM',
                    percent: ramFraction,
                    display: '${_metrics.ramUsagePercent.toStringAsFixed(0)}%',
                    color: CloudOSColors.accentPurple,
                  ),
                  _buildGauge(
                    label: 'DISCO',
                    percent: diskFraction,
                    display: '${_metrics.diskUsagePercent.toStringAsFixed(0)}%',
                    color: CloudOSColors.neonEmerald,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGauge({
    required String label,
    required double percent,
    required String display,
    required Color color,
  }) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CircularProgressIndicator(
                value: percent,
                strokeWidth: 3.5,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Center(
                child: Text(
                  display,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Segoe UI',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
