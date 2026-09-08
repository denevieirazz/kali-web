import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/desktop_clock_service.dart';
import '../services/system_metrics_service.dart';

class DesktopClockWidget extends StatefulWidget {
  const DesktopClockWidget({super.key, this.clockService});

  final DesktopClockService? clockService;

  @override
  State<DesktopClockWidget> createState() => _DesktopClockWidgetState();
}

class _DesktopClockWidgetState extends State<DesktopClockWidget> {
  late DesktopClockService _clock;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _bindClock();
  }

  @override
  void didUpdateWidget(covariant DesktopClockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clockService, widget.clockService)) {
      _clock.removeListener(_onClockTick);
      _bindClock();
    }
  }

  void _bindClock() {
    _clock = widget.clockService ?? DesktopClockService.instance;
    _now = _clock.now;
    _clock.addListener(_onClockTick);
  }

  void _onClockTick() {
    if (!mounted) return;
    final next = _clock.now;
    if (next == _now) return;
    setState(() => _now = next);
  }

  @override
  void dispose() {
    _clock.removeListener(_onClockTick);
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
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return months[(month - 1) % 12];
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');
    final dateFormatted =
        '${_formatWeekday(_now.weekday)}, ${_now.day} de ${_formatMonth(_now.month)}';

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
                      '$hour:$minute',
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
                      ':$second',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: CloudOSColors.neonCyan,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Hora Local do Sistema',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
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
  const DesktopMetricsWidget({
    super.key,
    required this.bridge,
    this.enablePeriodicPolling = true,
  });

  final CloudOSBridge bridge;
  final bool enablePeriodicPolling;

  @override
  State<DesktopMetricsWidget> createState() => _DesktopMetricsWidgetState();
}

class _DesktopMetricsWidgetState extends State<DesktopMetricsWidget> {
  StreamSubscription<RealSystemMetrics>? _sub;
  late SystemMetricsService _metricsService;
  RealSystemMetrics _metrics = RealSystemMetrics.initial;

  @override
  void initState() {
    super.initState();
    _bindMetrics();
  }

  @override
  void didUpdateWidget(covariant DesktopMetricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bridge, widget.bridge) ||
        oldWidget.enablePeriodicPolling != widget.enablePeriodicPolling) {
      _unbindMetrics();
      _bindMetrics();
    }
  }

  void _bindMetrics() {
    _metricsService = SystemMetricsService(
      bridge: widget.bridge,
      enablePeriodicPolling: widget.enablePeriodicPolling,
    );
    _metrics = _metricsService.current;
    _metricsService.start();
    _sub = _metricsService.metricsStream.listen((metrics) {
      if (mounted) setState(() => _metrics = metrics);
    });
  }

  void _unbindMetrics() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    _metricsService.dispose();
  }

  @override
  void dispose() {
    _unbindMetrics();
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
                  Icon(
                    Icons.speed_rounded,
                    size: 13,
                    color: _metrics.isLive
                        ? CloudOSColors.neonEmerald
                        : CloudOSColors.neonCyan,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _metrics.isLive
                          ? 'Performance Real do Windows'
                          : 'Performance indisponível',
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
                    display: _metrics.isLive
                        ? '${_metrics.cpuPercent.toStringAsFixed(0)}%'
                        : '--',
                    color: CloudOSColors.neonCyan,
                  ),
                  _buildGauge(
                    label: 'RAM',
                    percent: ramFraction,
                    display: _metrics.isLive
                        ? '${_metrics.ramUsagePercent.toStringAsFixed(0)}%'
                        : '--',
                    color: CloudOSColors.accentPurple,
                  ),
                  _buildGauge(
                    label: 'DISCO',
                    percent: diskFraction,
                    display: _metrics.isLive && _metrics.systemDisk != null
                        ? '${_metrics.diskUsagePercent.toStringAsFixed(0)}%'
                        : '--',
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
