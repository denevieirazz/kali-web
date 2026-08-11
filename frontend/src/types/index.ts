// ============================================
// ObsidianOS Type Definitions
// ============================================

// ── CPU Scheduler ────────────────────────────────────────────────────────────

export type ProcessState =
  | 'NEW'        // just created, not yet scheduled
  | 'READY'      // in run queue, waiting for CPU
  | 'RUNNING'    // currently executing on CPU
  | 'BLOCKED'    // waiting for I/O or event
  | 'SLEEPING'   // waiting for timer (OS.wait)
  | 'ZOMBIE'     // finished but parent hasn't reaped
  | 'TERMINATED' // fully cleaned up
  | 'suspended'; // legacy compat alias for BLOCKED

export type ProcessPriority =
  | 'REALTIME'   // 0  — highest, reserved for kernel
  | 'HIGH'       // 1
  | 'ABOVE_NORMAL' // 2
  | 'NORMAL'     // 3  — default for user processes
  | 'BELOW_NORMAL' // 4
  | 'IDLE';      // 5  — only runs when CPU is free

// ── Signals ──────────────────────────────────────────────────────────────────

export type Signal =
  | 'SIGTERM'   // graceful termination request
  | 'SIGKILL'   // immediate kill (cannot be caught)
  | 'SIGINT'    // interrupt (Ctrl+C)
  | 'SIGSEGV'   // segmentation fault (invalid memory access)
  | 'SIGFPE'    // floating point / arithmetic exception
  | 'SIGILL'    // illegal instruction
  | 'SIGABRT'   // abort (process called abort())
  | 'SIGALRM'   // alarm timer expired
  | 'SIGCHLD'   // child process state changed
  | 'SIGUSR1'   // user-defined signal 1
  | 'SIGUSR2';  // user-defined signal 2

export interface SignalHandler {
  signal: Signal;
  handler: 'DEFAULT' | 'IGNORE' | 'CUSTOM';
  customFn?: string; // serialized function name in process context
}

// ── Process ───────────────────────────────────────────────────────────────────

export interface Process {
  pid: number;
  ppid: number;          // parent PID (0 = kernel)
  name: string;
  title: string;
  icon: string;
  state: ProcessState;
  priority: ProcessPriority;
  // Scheduler fields
  quantum: number;       // CPU time slice in ms (default 50ms)
  quantumUsed: number;   // ms used in current quantum
  totalCpuTime: number;  // total ms on CPU since start
  lastScheduled: number; // timestamp of last CPU grant
  // Resource usage
  memoryUsage: number;   // MB
  cpuUsage: number;      // 0-100 % (rolling average)
  // Signals
  pendingSignals: Signal[];
  signalHandlers: Partial<Record<Signal, SignalHandler>>;
  // Metadata
  startTime: number;
  exitCode?: number;
  windowId?: string;
  currentDirectory: string;
  // I/O
  stdin: string[];       // Input queue
  // Legacy compat
  status: 'running' | 'suspended' | 'terminated';
}

// ── Partition Table (MBR/GPT) ─────────────────────────────────────────────────

export type PartitionType =
  | 'NTFS'
  | 'FAT32'
  | 'EXT4'
  | 'SWAP'
  | 'EFI'
  | 'RECOVERY'
  | 'UNKNOWN';

export interface PartitionEntry {
  index: number;          // 0-3 for MBR primary, 0-127 for GPT
  label: string;          // e.g. "ObsidianOS"
  driveLetter: string;    // e.g. "C"
  type: PartitionType;
  bootable: boolean;
  startLBA: number;       // logical block address
  sizeMB: number;
  usedMB: number;
  filesystem: string;     // mount path in VFS
  guid?: string;          // GPT only
}

export interface PartitionTable {
  scheme: 'MBR' | 'GPT';
  diskSizeMB: number;
  diskLabel: string;
  guid?: string;           // GPT disk GUID
  partitions: PartitionEntry[];
  // MBR boot sector info
  bootSignature?: string;  // '55AA'
  mbr?: {
    bootstrapCode: string;
    diskTimestamp: number;
  };
  // GPT header
  gpt?: {
    headerLBA: number;
    backupLBA: number;
    firstUsableLBA: number;
    lastUsableLBA: number;
  };
}

// ── Boot Manager ─────────────────────────────────────────────────────────────

export interface BootEntry {
  id: string;
  label: string;
  partition: string;      // drive letter
  kernelPath: string;
  initrdPath?: string;
  cmdline: string;
  isDefault: boolean;
  timeout?: number;
}

export interface BootConfig {
  entries: BootEntry[];
  defaultEntry: string;
  timeout: number;        // seconds before auto-boot
  scheme: 'LEGACY' | 'UEFI';
}

// ── Rest of types (unchanged) ─────────────────────────────────────────────────

export interface WindowState {
  id: string;
  title: string;
  icon: string;
  appId: string;
  x: number;
  y: number;
  width: number;
  height: number;
  minWidth: number;
  minHeight: number;
  isMinimized: boolean;
  isMaximized: boolean;
  isActive: boolean;
  zIndex: number;
  opacity: number;
  isResizable: boolean;
  isDraggable: boolean;
  isClosable: boolean;
  isMinimizable: boolean;
  isMaximizable: boolean;
  processId: number;
  params?: any;
  hasFrame: boolean;
  isSystem: boolean;
  prevBounds?: { x: number; y: number; width: number; height: number };
}

export interface FileSystemNode {
  id: string;
  name: string;
  type: 'file' | 'directory' | 'shortcut';
  path: string;
  parentPath: string;
  size: number;
  icon?: string;
  extension?: string;
  content?: string;
  children?: string[]; // paths
  createdAt: number;
  modifiedAt: number;
  accessedAt: number;
  permissions: FilePermissions;
  attributes: FileAttributes;
  metadata?: Record<string, string>;
}

export interface FilePermissions {
  read: boolean;
  write: boolean;
  execute: boolean;
  hidden: boolean;
  system: boolean;
}

export interface FileAttributes {
  isReadOnly: boolean;
  isHidden: boolean;
  isSystem: boolean;
  isArchive: boolean;
}

export interface RegistryKey {
  path: string;
  name: string;
  type: 'REG_SZ' | 'REG_DWORD' | 'REG_BINARY' | 'REG_MULTI_SZ' | 'REG_EXPAND_SZ' | 'REG_QWORD';
  value: string | number | boolean | string[];
  children?: Record<string, RegistryKey>;
}

export interface RegistryHive {
  HKEY_CURRENT_USER: Record<string, RegistryKey>;
  HKEY_LOCAL_MACHINE: Record<string, RegistryKey>;
  HKEY_CLASSES_ROOT: Record<string, RegistryKey>;
  HKEY_USERS: Record<string, RegistryKey>;
  HKEY_CURRENT_CONFIG: Record<string, RegistryKey>;
}

export interface DesktopIcon {
  id: string;
  name: string;
  icon: string;
  appId: string;
  position: { x: number; y: number };
  isSelected: boolean;
}

export interface NotificationData {
  id: string;
  title: string;
  message: string;
  icon?: string;
  timestamp: number;
  type: 'info' | 'warning' | 'error' | 'success';
  duration?: number;
  actions?: { label: string; onClick: () => void }[];
  read: boolean;
}

export interface SystemTheme {
  mode: 'dark' | 'light';
  accentColor: string;
  wallpaper: string;
  transparency: boolean;
  animationSpeed: 'slow' | 'normal' | 'fast' | 'none';
  fontSize: 'small' | 'medium' | 'large';
}

export interface UserProfile {
  username: string;
  displayName: string;
  avatar: string;
  password: string;
  isAdmin: boolean;
  lastLogin: number;
}

export interface ContextMenuItem {
  id: string;
  label: string;
  icon?: string;
  shortcut?: string;
  disabled?: boolean;
  separator?: boolean;
  children?: ContextMenuItem[];
  onClick?: () => void;
}

export interface AppDefinition {
  id: string;
  name: string;
  icon: string;
  component?: React.ComponentType<{ windowId: string }>;
  defaultWidth: number;
  defaultHeight: number;
  minWidth: number;
  minHeight: number;
  isResizable: boolean;
  isSingleInstance: boolean;
  hasFrame?: boolean;
  category: 'system' | 'productivity' | 'utilities' | 'entertainment';
  binaryPath?: string;
}
