import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../start/domain/start_running_app.dart';

class TaskManagerWindow extends StatelessWidget {
  const TaskManagerWindow({
    required this.snapshot,
    required this.runningApps,
    required this.onSwitchToApp,
    required this.onCloseApp,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final List<StartRunningApp> runningApps;
  final ValueChanged<String> onSwitchToApp;
  final ValueChanged<String> onCloseApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CloudOSColors.background,
      child: Column(
        children: <Widget>[
          // System Overview Metrics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF101624),
              border: Border(bottom: BorderSide(color: CloudOSColors.border)),
            ),
            child: Row(
              children: <Widget>[
                _buildMetricCard(
                  title: 'Bateria / Energia',
                  value: '${snapshot.batteryPercent}%',
                  progress: snapshot.batteryPercent / 100.0,
                  icon: Icons.battery_charging_full_rounded,
                  color: snapshot.batteryPercent < 20 ? Colors.redAccent : const Color(0xFF10B981),
                ),
                const SizedBox(width: 14),
                _buildMetricCard(
                  title: 'Subsistema Linux (WSL)',
                  value: snapshot.wslAvailable ? 'Ativo (${snapshot.distros.length} distros)' : 'Indisponível',
                  progress: snapshot.wslAvailable ? 1.0 : 0.2,
                  icon: Icons.terminal_rounded,
                  color: snapshot.wslAvailable ? const Color(0xFF2DD4BF) : Colors.orangeAccent,
                ),
                const SizedBox(width: 14),
                _buildMetricCard(
                  title: 'Área de Trabalho',
                  value: 'Área ${snapshot.currentWorkspace}',
                  progress: (snapshot.currentWorkspace / 4.0).clamp(0.0, 1.0),
                  icon: Icons.desktop_windows_rounded,
                  color: const Color(0xFFA78BFA),
                ),
              ],
            ),
          ),
          // Task List Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF0C111C),
            child: const Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Text(
                    'Aplicativo / Processo',
                    style: TextStyle(color: CloudOSColors.caption, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(color: CloudOSColors.caption, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'Ações',
                  style: TextStyle(color: CloudOSColors.caption, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: CloudOSColors.border),
          // Tasks List
          Expanded(
            child: runningApps.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum processo em execução.',
                      style: TextStyle(color: CloudOSColors.caption),
                    ),
                  )
                : ListView.separated(
                    itemCount: runningApps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF161E2E)),
                    itemBuilder: (context, index) {
                      final app = runningApps[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: app.isActive ? CloudOSColors.accent.withValues(alpha: 0.1) : Colors.transparent,
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
                              flex: 3,
                              child: Text(
                                app.title,
                                style: TextStyle(
                                  color: app.isActive ? Colors.white : CloudOSColors.text,
                                  fontWeight: app.isActive ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 13,
                                ),
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
                                      color: app.isMinimized ? Colors.orangeAccent : const Color(0xFF10B981),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      app.isMinimized ? 'Segundo Plano' : 'Em Execução',
                                      style: TextStyle(
                                        color: app.isMinimized ? Colors.orangeAccent : const Color(0xFF10B981),
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
                                  onPressed: () => onSwitchToApp(app.id),
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
                                  onPressed: () => onCloseApp(app.id),
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
    required double progress,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
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
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF202C40),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
