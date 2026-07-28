import { Terminal as TerminalIcon, FolderOpen, Code2, Activity, ShieldCheck, Settings as SettingsIcon, AlertTriangle, Download } from 'lucide-react';
import { TerminalApp } from './apps/TerminalApp';
import { FileManagerApp } from './apps/FileManagerApp';
import { CodeEditorApp } from './apps/CodeEditorApp';
import { SystemMonitorApp } from './apps/SystemMonitorApp';
import { OpSecCenterApp } from './apps/OpSecCenterApp';
import { SettingsApp } from './apps/SettingsApp';
import { EventCenterApp } from './apps/EventCenterApp';
import { AppStoreApp } from './apps/AppStoreApp';

export const AppRegistry = {
  terminal: { id: 'terminal', title: 'Terminal', icon: TerminalIcon, Component: TerminalApp },
  files: { id: 'files', title: 'File Manager', icon: FolderOpen, Component: FileManagerApp },
  editor: { id: 'editor', title: 'Code Editor', icon: Code2, Component: CodeEditorApp },
  monitor: { id: 'monitor', title: 'System Monitor', icon: Activity, Component: SystemMonitorApp },
  opsec: { id: 'opsec', title: 'OpSec Center', icon: ShieldCheck, Component: OpSecCenterApp },
  events: { id: 'events', title: 'Event Center', icon: AlertTriangle, Component: EventCenterApp },
  appstore: { id: 'appstore', title: 'App Store', icon: Download, Component: AppStoreApp },
  settings: { id: 'settings', title: 'Control Center', icon: SettingsIcon, Component: SettingsApp }
};

export const AppList = Object.values(AppRegistry);
