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
    this.onBrowser,
    this.onTerminal,
    this.onSettings,
    this.onCloseFiles,
    this.onCloseBrowser,
    this.onCloseTerminal,
    this.onCloseSettings,
    this.filesRunning = true,
    this.browserRunning = false,
    this.terminalRunning = false,
    this.settingsRunning = false,
    this.filesActive = false,
    this.browserActive = false,
    this.terminalActive = false,
    this.settingsActive = false,
    this.currentWorkspace = 1,
    this.onWorkspaceChanged,
    this.notificationCount = 0,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onFiles;
  final VoidCallback onQuickSettings;
  final VoidCallback onNotifications;
  final VoidCallback? onBrowser;
  final VoidCallback? onTerminal;
  final VoidCallback? onSettings;
  final VoidCallback? onCloseFiles;
  final VoidCallback? onCloseBrowser;
  final VoidCallback? onCloseTerminal;
  final VoidCallback? onCloseSettings;
  final bool startOpen;
  final bool quickSettingsOpen;
  final bool notificationsOpen;
  final bool filesRunning;
  final bool browserRunning;
  final bool terminalRunning;
  final bool settingsRunning;
  final bool filesActive;
  final bool browserActive;
  final bool terminalActive;
  final bool settingsActive;
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
                  tooltip: 'Pesquisa Global (Ctrl+Alt+S)',
                  icon: Icons.search_rounded,
                  active: startOpen,
                  onPressed: onStart,
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
