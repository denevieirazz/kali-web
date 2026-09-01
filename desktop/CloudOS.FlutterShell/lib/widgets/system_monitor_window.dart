import 'dart:async';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/system_metrics_service.dart';

class SystemMonitorWindow extends StatefulWidget {
  const SystemMonitorWindow({
    super.key,
    required this.bridge,
  });

  final CloudOSBridge bridge;

  @override
  State<SystemMonitorWindow> createState() => _SystemMonitorWindowState();
}

class _SystemMonitorWindowState extends State<SystemMonitorWindow> {
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
    final ramUsedGb = (_metrics.usedRamMb / 1024.0).toStringAsFixed(1);
    final ramTotalGb = (_metrics.totalRamMb / 1024.0).toStringAsFixed(1);

    return Column(
      children: <Widget>[
        // Cards de Métricas Reais do Sistema
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF080B14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _buildMetricCard(
                  title: 'CPU',
                  value: '${_metrics.cpuPercent.toStringAsFixed(0)}%',
                  sub: _metrics.isLive ? 'Carga Total' : 'Aguardando sensor...',
                  icon: Icons.speed_rounded,
                  color: CloudOSColors.neonCyan,
                  progress: (_metrics.cpuPercent / 100.0).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'Memória RAM',
                  value: '${_metrics.ramUsagePercent.toStringAsFixed(0)}%',
                  sub: _metrics.totalRamMb > 0 ? '$ramUsedGb / $ramTotalGb GB' : 'Lendo...',
                  icon: Icons.memory_rounded,
                  color: CloudOSColors.accentPurple,
                  progress: (_metrics.ramUsagePercent / 100.0).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: _metrics.systemDrive.isEmpty
                      ? 'Armazenamento'
                      : 'Armazenamento (${_metrics.systemDrive})',
                  value: '${_metrics.diskUsagePercent.toStringAsFixed(0)}%',
                  sub: _metrics.totalDiskGb > 0 ? '${_metrics.usedDiskGb} / ${_metrics.totalDiskGb} GB' : 'Lendo...',
                  icon: Icons.storage_rounded,
                  color: CloudOSColors.neonEmerald,
                  progress: (_metrics.diskUsagePercent / 100.0).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'Uptime',
                  value: _metrics.uptimeFormatted,
                  sub: 'Tempo de Atividade',
                  icon: Icons.timer_outlined,
                  color: CloudOSColors.neonAmber,
                  progress: 1.0,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0x1AFFFFFF)),

        // Tabela de Processos Reais do Sistema
        Expanded(
          child: Container(
            color: const Color(0xFF060910),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'Processos Ativos do Windows & CloudOS (Tempo Real)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _metrics.isLive ? CloudOSColors.neonEmerald : Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _metrics.isLive ? 'Win32 Native API (2s)' : 'Conectando sensor...',
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Cabeçalho da Tabela
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1220),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Expanded(flex: 4, child: Text('NOME DO PROCESSO', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70))),
                      Expanded(flex: 2, child: Text('PID', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70))),
                      Expanded(flex: 2, child: Text('MEMÓRIA RAM', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70))),
                      Expanded(flex: 2, child: Text('TEMPO CPU (s)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Lista de Processos Reais
                Expanded(
                  child: _metrics.activeProcesses.isEmpty
                      ? const Center(child: Text('Lendo processos do sistema...', style: TextStyle(color: Colors.white54, fontSize: 12)))
                      : ListView.separated(
                          itemCount: _metrics.activeProcesses.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0x0AFFFFFF)),
                          itemBuilder: (context, index) {
                            final proc = _metrics.activeProcesses[index];
                            final isCloudOS = proc.name.toLowerCase().contains('cloudos');
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isCloudOS ? CloudOSColors.accent.withValues(alpha: 0.08) : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    flex: 4,
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          isCloudOS ? Icons.cloud_circle_rounded : Icons.terminal_rounded,
                                          size: 14,
                                          color: isCloudOS ? CloudOSColors.neonCyan : Colors.white60,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            proc.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isCloudOS ? FontWeight.bold : FontWeight.normal,
                                              color: isCloudOS ? CloudOSColors.neonCyan : Colors.white,
                                              fontFamily: 'Consolas',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${proc.pid}',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontFamily: 'Consolas'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${proc.ramMb.toStringAsFixed(1)} MB',
                                      style: const TextStyle(fontSize: 11.5, color: CloudOSColors.neonEmerald, fontFamily: 'Consolas'),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${proc.cpuTimeSeconds.toStringAsFixed(1)} s',
                                      style: const TextStyle(fontSize: 11.5, color: CloudOSColors.neonAmber, fontFamily: 'Consolas'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w600)),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Segoe UI')),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: color, fontFamily: 'Consolas')),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
