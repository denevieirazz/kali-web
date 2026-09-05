import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';
import '../../start/domain/start_running_app.dart';

class TaskManagerWindow extends StatefulWidget {
  const TaskManagerWindow({
    required this.snapshot,
    required this.runningApps,
    required this.onSwitchToApp,
    required this.onCloseApp,
    this.bridge,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final List<StartRunningApp> runningApps;
  final ValueChanged<String> onSwitchToApp;
  final ValueChanged<String> onCloseApp;
  final CloudOSBridge? bridge;

  @override
  State<TaskManagerWindow> createState() => _TaskManagerWindowState();
}

class _TaskManagerWindowState extends State<TaskManagerWindow> {
  CloudHardwareMetrics? _metrics;
  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
    _metricsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _fetchMetrics();
    });
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMetrics() async {
    if (widget.bridge == null) return;
    try {
      final m = await widget.bridge!.getHardwareMetrics();
      if (mounted && m != null) {
        setState(() => _metrics = m);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ramPercent = _metrics?.memoryLoadPercent ?? 0;
    final totalGb = ((_metrics?.totalRamMb ?? 0) / 1024.0).toStringAsFixed(1);
    final usedGb = (((_metrics?.totalRamMb ?? 0) - (_metrics?.freeRamMb ?? 0)) / 1024.0).toStringAsFixed(1);

    return Container(
      color: CloudOSColors.background,
      child: Column(
        children: <Widget>[
          // System Overview Metrics Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF101624),
              border: Border(bottom: BorderSide(color: CloudOSColors.border)),
            ),
            child: Row(
              children: <Widget>[
                _buildMetricCard(
                  title: 'Bateria / Energia',
                  value: '${widget.snapshot.batteryPercent}%',
                  subtitle: widget.snapshot.batteryAvailable
                      ? (_metrics?.onBattery == true
                          ? 'Na Bateria'
                          : 'Conectado')
                      : 'Rede Elétrica (AC)',
                  progress: (widget.snapshot.batteryPercent / 100.0).clamp(0.0, 1.0),
                  icon: Icons.battery_charging_full_rounded,
                  color: widget.snapshot.batteryPercent < 20 ? Colors.redAccent : const Color(0xFF10B981),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  title: 'Subsistema Linux (WSL)',
                  value: widget.snapshot.wslAvailable
                      ? 'Ativo (${widget.snapshot.distros.length} distros)'
                      : 'Indisponível',
                  subtitle: widget.snapshot.wslAvailable ? 'Distros prontas' : 'Desativado',
                  progress: widget.snapshot.wslAvailable ? 1.0 : 0.2,
                  icon: Icons.terminal_rounded,
                  color: widget.snapshot.wslAvailable ? const Color(0xFF2DD4BF) : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  title: 'Área de Trabalho',
                  value: 'Área ${widget.snapshot.currentWorkspace}',
                  subtitle: 'Workspace Ativo',
                  progress: (widget.snapshot.currentWorkspace / 4.0).clamp(0.0, 1.0),
                  icon: Icons.desktop_windows_rounded,
                  color: const Color(0xFFA78BFA),
                ),
                if (_metrics != null) ...[
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    title: 'Memória RAM',
                    value: '$ramPercent%',
                    subtitle: '$usedGb / $totalGb GB',
                    progress: (ramPercent / 100.0).clamp(0.0, 1.0),
                    icon: Icons.developer_board_rounded,
                    color: ramPercent > 85 ? Colors.redAccent : const Color(0xFF10B981),
                  ),
                ],
              ],
            ),
          ),

          // Task List Column Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0C111C),
            child: const Row(
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: Text(
                    'Aplicativo / Janela Win32 / WSL',
                    style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'Ações de Gerenciamento',
                  style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: CloudOSColors.border),

          // Tasks List
          Expanded(
            child: widget.runningApps.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum processo em execução.',
                      style: TextStyle(color: CloudOSColors.caption),
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.runningApps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF161E2E)),
                    itemBuilder: (context, index) {
                      final app = widget.runningApps[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: app.isActive ? CloudOSColors.accent.withValues(alpha: 0.08) : Colors.transparent,
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2336),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(app.icon, size: 18, color: CloudOSColors.accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    app.title,
                                    style: TextStyle(
                                      color: app.isActive ? Colors.white : CloudOSColors.text,
                                      fontWeight: app.isActive ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'ID: ${app.id}',
                                    style: const TextStyle(
                                      color: CloudOSColors.caption,
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: app.isMinimized
                                          ? Colors.orangeAccent
                                          : (app.isActive ? const Color(0xFF10B981) : const Color(0xFF38BDF8)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      app.isMinimized ? 'Segundo Plano' : 'Em Execução',
                                      style: TextStyle(
                                        color: app.isMinimized
                                            ? Colors.orangeAccent
                                            : const Color(0xFF10B981),
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                TextButton.icon(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                  label: const Text('Alternar'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: CloudOSColors.accent,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  ),
                                  onPressed: () => widget.onSwitchToApp(app.id),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.close_rounded, size: 14),
                                  label: const Text('Finalizar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(color: Colors.redAccent, width: 0.8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                  onPressed: () => widget.onCloseApp(app.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required double progress,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF141C2B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CloudOSColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF202C40),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 3.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
