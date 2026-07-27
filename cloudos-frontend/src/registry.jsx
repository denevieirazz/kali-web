import { Terminal as TerminalIcon, FolderOpen, Code2, Activity, ShieldCheck, Settings as SettingsIcon } from 'lucide-react';
import { TerminalApp, FileManagerApp, CodeEditorApp, SettingsApp } from './apps';
import { SystemMonitorApp } from './apps/SystemMonitorApp';

export const AppRegistry = {
  terminal: { id: 'terminal', title: 'Terminal', icon: TerminalIcon, Component: TerminalApp },
  files: { id: 'files', title: 'File Manager', icon: FolderOpen, Component: FileManagerApp },
  editor: { id: 'editor', title: 'Code Editor', icon: Code2, Component: CodeEditorApp },
  monitor: { id: 'monitor', title: 'System Monitor', icon: Activity, Component: SystemMonitorApp },
  settings: { id: 'settings', title: 'Settings', icon: SettingsIcon, Component: SettingsApp }
};

export const AppList = Object.values(AppRegistry);
