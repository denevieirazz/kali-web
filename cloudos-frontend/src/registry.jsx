import { Terminal as TerminalIcon, FolderOpen, Code2, Activity, ShieldCheck, Settings as SettingsIcon, AlertTriangle, Download, Boxes, LayoutGrid, ArrowRightLeft, FolderArchive, Workflow, FileText, Camera } from 'lucide-react';
import { TerminalApp } from './apps/TerminalApp';
import { TerminalProApp } from './apps/terminal/TerminalProApp';
import { FileManagerApp } from './apps/FileManagerApp';
import { CodeEditorApp } from './apps/CodeEditorApp';
import { SystemMonitorApp } from './apps/SystemMonitorApp';
import { OpSecCenterApp } from './apps/OpSecCenterApp';
import { SettingsApp } from './apps/SettingsApp';
import { EventCenterApp } from './apps/EventCenterApp';
import { AppStoreApp } from './apps/AppStoreApp';
import { KaliHubApp } from './apps/KaliHubApp';
import { ToolRunnerApp } from './apps/ToolRunnerApp';
import { RepeaterApp } from './apps/RepeaterApp';
import { ProjectsApp } from './apps/ProjectsApp';
import { PipelineApp } from './apps/PipelineApp';
import { ReportBuilderApp } from './apps/ReportBuilderApp';
import { SnapshotManagerApp } from './apps/SnapshotManagerApp';
import { FindingsManagerApp } from './apps/FindingsManagerApp';
import { PipelineBuilderApp } from './apps/PipelineBuilderApp';
import { EnvironmentDoctorApp } from './apps/EnvironmentDoctorApp';
import { EvidenceVaultApp } from './apps/EvidenceVaultApp';
import { LabMissionsApp } from './apps/LabMissionsApp';
import TaskManagerApp from './apps/TaskManagerApp';
import NetworkApp from './apps/NetworkApp';
import { Bug, Stethoscope, Vault, Trophy, Cpu, Network } from 'lucide-react';

export const AppRegistry = {
  terminal: { id: 'terminal', title: 'Terminal Pro', icon: TerminalIcon, Component: TerminalProApp },
  taskmanager: { id: 'taskmanager', title: 'Gerenciador de Tarefas', icon: Cpu, Component: TaskManagerApp },
  networkmanager: { id: 'networkmanager', title: 'Rede & Serviços', icon: Network, Component: NetworkApp },
  kalihub: { id: 'kalihub', title: 'Kali Hub', icon: Boxes, Component: KaliHubApp },
  toolrunner: { id: 'toolrunner', title: 'Tool Runner', icon: LayoutGrid, Component: ToolRunnerApp },
  pipeline: { id: 'pipeline', title: 'Automação', icon: Workflow, Component: PipelineApp },
  visualpipeline: { id: 'visualpipeline', title: 'Visual Pipeline', icon: Workflow, Component: PipelineBuilderApp },
  missions: { id: 'missions', title: 'Lab Missions', icon: Trophy, Component: LabMissionsApp },
  findings: { id: 'findings', title: 'Findings', icon: Bug, Component: FindingsManagerApp },
  evidence: { id: 'evidence', title: 'Evidence Vault', icon: Vault, Component: EvidenceVaultApp },
  doctor: { id: 'doctor', title: 'Doctor', icon: Stethoscope, Component: EnvironmentDoctorApp },
  projects: { id: 'projects', title: 'Projetos', icon: FolderArchive, Component: ProjectsApp },
  report: { id: 'report', title: 'Report Builder', icon: FileText, Component: ReportBuilderApp },
  repeater: { id: 'repeater', title: 'HTTP Repeater', icon: ArrowRightLeft, Component: RepeaterApp },
  snapshots: { id: 'snapshots', title: 'Snapshots', icon: Camera, Component: SnapshotManagerApp },
  files: { id: 'files', title: 'File Manager', icon: FolderOpen, Component: FileManagerApp },
  editor: { id: 'editor', title: 'Code Editor', icon: Code2, Component: CodeEditorApp },
  monitor: { id: 'monitor', title: 'System Monitor', icon: Activity, Component: SystemMonitorApp },
  opsec: { id: 'opsec', title: 'OpSec Center', icon: ShieldCheck, Component: OpSecCenterApp },
  events: { id: 'events', title: 'Event Center', icon: AlertTriangle, Component: EventCenterApp },
  appstore: { id: 'appstore', title: 'App Store', icon: Download, Component: AppStoreApp },
  settings: { id: 'settings', title: 'Control Center', icon: SettingsIcon, Component: SettingsApp }
};

export const AppList = Object.values(AppRegistry);
