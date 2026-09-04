import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/taskbar_system_tray.dart';
import 'widgets/taskbar_task_button.dart';
import 'widgets/taskbar_workspace_switcher.dart';

class CloudTaskbar extends StatelessWidget {
  const CloudTaskbar({
    required this.onStart,
    required this.onFiles,
    required this.onQuickSettings,
    required this.onNotifications,
    required this.startOpen,
    required this.quickSettingsOpen,
    required this.notificationsOpen,
    this.spotlightOpen = false,
    this.onSpotlight,
    this.onBrowser,
    this.onTerminal,
    this.onSettings,
    this.onNotes,
    this.onCalculator,
    this.onTaskManager,
    this.onCloseFiles,
    this.onCloseBrowser,
    this.onCloseTerminal,
    this.onCloseSettings,
    this.onCloseNotes,
    this.onCloseCalculator,
    this.onCloseTaskManager,
    this.filesRunning = true,
    this.browserRunning = false,
    this.terminalRunning = false,
    this.settingsRunning = false,
    this.notesRunning = false,
    this.calculatorRunning = false,
    this.taskManagerRunning = false,
    this.filesActive = false,
    this.browserActive = false,
    this.terminalActive = false,
    this.settingsActive = false,
    this.notesActive = false,
    this.calculatorActive = false,
    this.taskManagerActive = false,
    this.currentWorkspace = 1,
    this.onWorkspaceChanged,
    this.notificationCount = 0,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onFiles;
  final VoidCallback onQuickSettings;
  final VoidCallback onNotifications;
  final VoidCallback? onSpotlight;
  final VoidCallback? onBrowser;
  final VoidCallback? onTerminal;
  final VoidCallback? onSettings;
  final VoidCallback? onNotes;
  final VoidCallback? onCalculator;
  final VoidCallback? onTaskManager;
  final VoidCallback? onCloseFiles;
  final VoidCallback? onCloseBrowser;
  final VoidCallback? onCloseTerminal;
  final VoidCallback? onCloseSettings;
  final VoidCallback? onCloseNotes;
  final VoidCallback? onCloseCalculator;
  final VoidCallback? onCloseTaskManager;
  final bool startOpen;
  final bool quickSettingsOpen;
  final bool notificationsOpen;
  final bool spotlightOpen;
  final bool filesRunning;
  final bool browserRunning;
  final bool terminalRunning;
  final bool settingsRunning;
  final bool notesRunning;
  final bool calculatorRunning;
  final bool taskManagerRunning;
  final bool filesActive;
  final bool browserActive;
  final bool terminalActive;
  final bool settingsActive;
  final bool notesActive;
  final bool calculatorActive;
  final bool taskManagerActive;
  final int currentWorkspace;
  final ValueChanged<int>? onWorkspaceChanged;
  final int notificationCount;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassSurface(
          borderRadius: 14,
          blur: 24,
          color: const Color(0xF2131C27),
          borderColor: CloudOSColors.border,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                TaskbarTaskButton(
                  tooltip: 'Iniciar (Ctrl+Alt+A)',
                  icon: Icons.cloud_rounded,
                  active: startOpen,
                  onPressed: onStart,
                  accent: true,
                ),
                const SizedBox(width: 4),
                TaskbarTaskButton(
                  tooltip: onSpotlight != null
                      ? 'Central de Comando / Busca (Alt+Espaço)'
                      : 'Pesquisa Global (Ctrl+Alt+S)',
                  icon: Icons.search_rounded,
                  active: onSpotlight != null ? spotlightOpen : startOpen,
                  onPressed: onSpotlight ?? onStart,
                ),
                const SizedBox(width: 4),
                TaskbarTaskButton(
                  tooltip: 'Arquivos (Ctrl+Alt+E)',
                  icon: Icons.folder_rounded,
                  label: 'Arquivos',
                  active: filesActive,
                  isRunning: filesRunning,
                  onPressed: onFiles,
                  onClose: onCloseFiles,
                ),
                const SizedBox(width: 4),
                TaskbarTaskButton(
                  tooltip: 'Navegador Web',
                  icon: Icons.language_rounded,
                  label: 'Navegador',
                  active: browserActive,
                  isRunning: browserRunning,
                  onPressed: onBrowser,
                  onClose: onCloseBrowser,
                ),
                const SizedBox(width: 4),
                TaskbarTaskButton(
                  tooltip: 'Terminal ConPTY (Ctrl+Alt+Enter)',
                  icon: Icons.terminal_rounded,
                  label: 'Terminal',
                  active: terminalActive,
                  isRunning: terminalRunning,
                  onPressed: onTerminal,
                  onClose: onCloseTerminal,
                ),
                if (settingsRunning) ...<Widget>[
                  const SizedBox(width: 4),
                  TaskbarTaskButton(
                    tooltip: 'Configurações',
                    icon: Icons.settings_rounded,
                    label: 'Configurações',
                    active: settingsActive,
                    isRunning: true,
                    onPressed: onSettings,
                    onClose: onCloseSettings,
                  ),
                ],
                if (notesRunning) ...<Widget>[
                  const SizedBox(width: 4),
                  TaskbarTaskButton(
                    tooltip: 'CloudOS Notes',
                    icon: Icons.description_rounded,
                    label: 'Notas',
                    active: notesActive,
                    isRunning: true,
                    onPressed: onNotes,
                    onClose: onCloseNotes,
                  ),
                ],
                if (calculatorRunning) ...<Widget>[
                  const SizedBox(width: 4),
                  TaskbarTaskButton(
                    tooltip: 'Calculadora',
                    icon: Icons.calculate_rounded,
                    label: 'Calculadora',
                    active: calculatorActive,
                    isRunning: true,
                    onPressed: onCalculator,
                    onClose: onCloseCalculator,
                  ),
                ],
                if (taskManagerRunning) ...<Widget>[
                  const SizedBox(width: 4),
                  TaskbarTaskButton(
                    tooltip: 'Monitor de Sistema',
                    icon: Icons.monitor_heart_rounded,
                    label: 'Monitor',
                    active: taskManagerActive,
                    isRunning: true,
                    onPressed: onTaskManager,
                    onClose: onCloseTaskManager,
                  ),
                ],
                const SizedBox(width: 10),
                Container(width: 1, height: 22, color: CloudOSColors.border),
                const SizedBox(width: 10),
                TaskbarWorkspaceSwitcher(
                  currentWorkspace: currentWorkspace,
                  onWorkspaceChanged: onWorkspaceChanged,
                ),
                const Spacer(),
                TaskbarSystemTray(
                  quickSettingsOpen: quickSettingsOpen,
                  notificationsOpen: notificationsOpen,
                  notificationCount: notificationCount,
                  onQuickSettings: onQuickSettings,
                  onNotifications: onNotifications,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
