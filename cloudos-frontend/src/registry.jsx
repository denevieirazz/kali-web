import { Terminal as TerminalIcon, FolderOpen, Code2, Activity, ShieldCheck, Settings as SettingsIcon } from 'lucide-react';
import { TerminalApp } from './apps/TerminalApp';
import { FileManagerApp } from './apps/FileManagerApp';
import { CodeEditorApp } from './apps/CodeEditorApp';
import { SystemMonitorApp } from './apps/SystemMonitorApp';
import { OpSecCenterApp } from './apps/OpSecCenterApp';
import { SettingsApp } from './apps/SettingsApp';

export const AppRegistry = {
  terminal: { id: 'terminal', title: 'Terminal', icon: TerminalIcon, Component: TerminalApp },
  files: { id: 'files', title: 'File Manager', icon: FolderOpen, Component: FileManagerApp },
  editor: { id: 'editor', title: 'Code Editor', icon: Code2, Component: CodeEditorApp },
  monitor: { id: 'monitor', title: 'System Monitor', icon: Activity, Component: SystemMonitorApp },
  opsec: { id: 'opsec', title: 'OpSec Center', icon: ShieldCheck, Component: OpSecCenterApp },
  settings: { id: 'settings', title: 'Settings', icon: SettingsIcon, Component: SettingsApp }
};

export const AppList = Object.values(AppRegistry);
