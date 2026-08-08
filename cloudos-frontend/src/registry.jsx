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
import DashboardApp from './apps/DashboardApp';
import MetasploitApp from './apps/MetasploitApp';
import NmapScannerApp from './apps/NmapScannerApp';
import SqlmapScannerApp from './apps/SqlmapScannerApp';
import HashCrackerApp from './apps/HashCrackerApp';
import MsfvenomApp from './apps/MsfvenomApp';
import ScriptLabApp from './apps/ScriptLabApp';
import CyberDecoderApp from './apps/CyberDecoderApp';
import KnowledgeBaseApp from './apps/KnowledgeBaseApp.jsx';
import AttackGraphApp from './apps/AttackGraphApp.jsx';
import ListenerManagerApp from './apps/ListenerManagerApp.jsx';
import PythonRunnerApp from './apps/PythonRunnerApp.jsx';
import ReportGeneratorApp from './apps/ReportGeneratorApp.jsx';
import AutoPilotApp from './apps/AutoPilotApp.jsx';
import AutoScannerApp from './apps/AutoScannerApp.jsx';
import AutoAttackApp from './apps/AutoAttackApp.jsx';
import AKBApp from './apps/AKBApp.jsx';
import PayloadForgeApp from './apps/PayloadForgeApp.jsx';
import PrivescHelperApp from './apps/PrivescHelperApp.jsx';
import TerminalApp from './apps/TerminalApp.jsx';
import OsintTrackerApp from './apps/OsintTrackerApp.jsx';
import { Bug, Stethoscope, Vault, Trophy, Cpu, Network, Zap, LayoutDashboard, Radar, Database, KeyRound, FlaskConical, Globe, TerminalSquare, Binary, BrainCircuit, RadioTower, Code, FileCode, Rocket, Wrench, ShieldAlert, Target, Crosshair } from 'lucide-react';

export const AppRegistry = {
  dashboard: { id: 'dashboard', title: 'Command Center', icon: LayoutDashboard, Component: DashboardApp },
  auto_scanner: { id: 'auto_scanner', title: 'Auto-Scanner', icon: Radar, Component: AutoScannerApp },
  auto_attack: { id: 'auto_attack', title: 'Auto-Attack', icon: Crosshair, Component: AutoAttackApp },
  akb: { id: 'akb', title: 'AKB', icon: Database, Component: AKBApp },
  osint_tracker: { id: 'osint_tracker', title: 'OSINT Tracker', icon: Target, Component: OsintTrackerApp },
  web_terminal: { id: 'web_terminal', title: 'Web Terminal', icon: TerminalSquare, Component: TerminalApp },
  privesc_helper: { id: 'privesc_helper', title: 'Privesc Helper', icon: ShieldAlert, Component: PrivescHelperApp },
  payload_forge: { id: 'payload_forge', title: 'Payload Forge', icon: Wrench, Component: PayloadForgeApp },
  autopilot: { id: 'autopilot', title: 'Recon Autopilot', icon: Rocket, Component: AutoPilotApp },
  python_runner: { id: 'python_runner', title: 'Python Runner', icon: Code, Component: PythonRunnerApp },
  report_gen: { id: 'report_gen', title: 'Report Generator', icon: FileCode, Component: ReportGeneratorApp },
  attack_graph: { id: 'attack_graph', title: 'Attack Graph', icon: Network, Component: AttackGraphApp },
  listeners: { id: 'listeners', title: 'Listeners', icon: RadioTower, Component: ListenerManagerApp },
  knowledge_base: { id: 'knowledge_base', title: 'Knowledge Base', icon: BrainCircuit, Component: KnowledgeBaseApp },
  cyberdecoder: { id: 'cyberdecoder', title: 'CyberDecoder PRO', icon: Binary, Component: CyberDecoderApp },
  scriptlab: { id: 'scriptlab', title: 'Script Lab', icon: TerminalSquare, Component: ScriptLabApp },
  osint: { id: 'osint', title: 'OSINT Hub', icon: Globe, Component: OsintApp },
  msfvenom: { id: 'msfvenom', title: 'Payload Gen', icon: FlaskConical, Component: MsfvenomApp },
  hashcracker: { id: 'hashcracker', title: 'Hash Cracker', icon: KeyRound, Component: HashCrackerApp },
  sqlmap: { id: 'sqlmap', title: 'Web Exploiter', icon: Database, Component: SqlmapScannerApp },
  nmap: { id: 'nmap', title: 'Network Scanner', icon: Radar, Component: NmapScannerApp },
  terminal: { id: 'terminal', title: 'Terminal Pro', icon: TerminalIcon, Component: TerminalProApp },
  taskmanager: { id: 'taskmanager', title: 'Gerenciador de Tarefas', icon: Cpu, Component: TaskManagerApp },
  networkmanager: { id: 'networkmanager', title: 'Rede & Serviços', icon: Network, Component: NetworkApp },
  metasploit: { id: 'metasploit', title: 'Metasploit', icon: Zap, Component: MetasploitApp },
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
export const appsRegistry = AppList;
