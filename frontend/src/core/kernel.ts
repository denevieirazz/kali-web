// ============================================
// ObsidianOS Kernel - The Heart of Everything
// ============================================
// Every single component in the OS depends on this.
// The kernel manages: processes, memory, drivers, services,
// system calls, event logging, and inter-process communication.

import { v4 as uuidv4 } from 'uuid';
import type { Process, ProcessPriority, Signal, WindowState, FileSystemNode, SystemTheme, UserProfile, PartitionTable, PartitionEntry, BootConfig, BootEntry } from '../types';
import { defaultNodes, makeFile, makeDir } from './defaultFileSystem';
import { defaultRegistry, type RegistryEntry, type RegistryValue } from './defaultRegistry';
import { opfsDriver, type OPFSDriver } from './opfsDriver';

import { Lexer } from './osl/lexer';
import { Parser } from './osl/parser';
import { Interpreter } from './osl/interpreter';

export type KernelLogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'CRITICAL' | 'FATAL';


export interface KernelLogEntry {
  timestamp: number;
  level: KernelLogLevel;
  source: string;
  message: string;
  code?: string;
}

export interface DriverEntry {
  name: string;
  path: string;       // Path in virtual FS
  status: 'loaded' | 'failed' | 'not_found' | 'disabled';
  type: 'kernel' | 'filesystem' | 'network' | 'display' | 'input' | 'audio' | 'storage';
  loadOrder: number;
  dependencies: string[];
  errorMessage?: string;
}

export interface ServiceEntry {
  name: string;
  displayName: string;
  description: string;
  executablePath: string;   // Must exist in FS
  registryPath: string;     // Registry key that defines this
  status: 'running' | 'stopped' | 'failed' | 'starting' | 'stopping';
  startType: 'auto' | 'manual' | 'disabled' | 'boot' | 'system';
  pid?: number;
  dependencies: string[];
  errorMessage?: string;
  restartCount: number;
}

export interface SystemResource {
  totalMemory: number;      // MB
  usedMemory: number;
  totalDisk: number;        // MB
  usedDisk: number;
  cpuCores: number;
  cpuUsage: number;         // 0-100
  uptime: number;           // seconds
  networkUp: boolean;
}

export interface KernelInterrupt {
  irq: number;
  handler: string;
  description: string;
}

export type BootPhase =
  | 'OFF'
  | 'BIOS_POST'         // Power-On Self Test
  | 'BIOS_HARDWARE'     // Hardware detection
  | 'BOOTLOADER'        // Loading bootloader from boot.ini
  | 'KERNEL_INIT'       // Loading ntoskrnl.exe
  | 'HAL_INIT'          // Hardware Abstraction Layer
  | 'DRIVER_LOAD'       // Loading drivers
  | 'REGISTRY_LOAD'     // Loading registry hives
  | 'SERVICE_INIT'      // Starting services
  | 'SUBSYSTEM_INIT'    // Win32 subsystem (csrss.exe)
  | 'SESSION_MANAGER'   // Session Manager (smss.exe)
  | 'WINLOGON'          // Login subsystem
  | 'SHELL_INIT'        // Loading explorer.exe (shell)
  | 'OOBE'              // Out-Of-Box Experience (Initial Setup)
  | 'DESKTOP_READY'     // Desktop environment ready
  | 'BOOT_FAILURE'      // Critical failure during boot
  | 'BSOD';             // Blue Screen of Death

export interface BSODInfo {
  stopCode: string;
  technicalInfo: string;
  failedComponent: string;
  bugCheckCode: string;
  parameters: string[];
}

class Kernel {
  private static instance: Kernel;
  
  // State
  private _bootPhase: BootPhase = 'OFF';
  private _logs: KernelLogEntry[] = [];
  private _drivers: Map<string, DriverEntry> = new Map();
  private _services: Map<string, ServiceEntry> = new Map();
  private _resources: SystemResource;
  private _bsodInfo: BSODInfo | null = null;
  private _bootLog: string[] = [];
  private _listeners: Map<string, Set<(...args: any[]) => void>> = new Map();
  private _uptimeInterval: ReturnType<typeof setInterval> | null = null;
  private _initTime: number = 0;
  private _isInitialized: boolean = false;
  private _isBooting: boolean = false;
  private _isBootFinished: boolean = false;
  private _shellLoaded: boolean = false;

  // ── Process Table ──────────────────────────────────────────────────────────
  private _processes: Map<number, Process> = new Map();
  private _nextPid: number = 100;

  // ── Scheduler ─────────────────────────────────────────────────────────────
  // Round-Robin with priority queues (5 levels, REALTIME→IDLE)
  private _runQueues: Map<ProcessPriority, number[]> = new Map([
    ['REALTIME',     []],
    ['HIGH',         []],
    ['ABOVE_NORMAL', []],
    ['NORMAL',       []],
    ['BELOW_NORMAL', []],
    ['IDLE',         []],
  ]);
  private _schedulerInterval: ReturnType<typeof setInterval> | null = null;
  private static readonly QUANTUM_MS: Record<ProcessPriority, number> = {
    REALTIME:     10,
    HIGH:         20,
    ABOVE_NORMAL: 30,
    NORMAL:       50,
    BELOW_NORMAL: 80,
    IDLE:         120,
  };
  private static readonly PRIORITY_ORDER: ProcessPriority[] = [
    'REALTIME', 'HIGH', 'ABOVE_NORMAL', 'NORMAL', 'BELOW_NORMAL', 'IDLE',
  ];

  // ── Window Table ──────────────────────────────────────────────────────────
  private _windows: Map<string, WindowState> = new Map();
  private _topZIndex: number = 100;
  private _activeWindowId: string | null = null;

  // ── Partition Table ────────────────────────────────────────────────────────
  private _partitionTable: PartitionTable | null = null;
  private _bootConfig: BootConfig | null = null;

  // ── File System ────────────────────────────────────────────────────────────
  private _filesystem: Map<string, FileSystemNode> = new Map();
  private _diskDriver: OPFSDriver | null = null;

  // Exposed so driver binaries (ntfs.sys, volmgr.sys) can access it
  readonly opfsDriver: OPFSDriver = opfsDriver;

  // ── Registry ───────────────────────────────────────────────────────────────
  private _registry: Record<string, Record<string, RegistryEntry>> = {};

  // ── System State ───────────────────────────────────────────────────────────
  private _user: UserProfile = {
    username: 'user', displayName: 'User', avatar: '', password: '',
    isAdmin: true, lastLogin: Date.now(),
  };
  private _isLocked: boolean = false;
  private _theme: SystemTheme = {
    mode: 'dark', accentColor: '#6366f1', wallpaper: 'default',
    transparency: true, animationSpeed: 'normal', fontSize: 'medium',
  };
  private _hardware = {
    volume: 75, isMuted: false, brightness: 100,
    isWifiConnected: true, isBluetooth: false, batteryLevel: 85,
  };

  private constructor() {
    this._resources = {
      totalMemory: 8192,
      usedMemory: 0,
      totalDisk: 256000,
      usedDisk: 42000,
      cpuCores: navigator.hardwareConcurrency || 8,
      cpuUsage: 0,
      uptime: 0,
      networkUp: false,
    };
    this._initSystemState();
    this._initFileSystem();
    this._initRegistry();
    this._initSystemProcesses();
    this._initPartitionTable();
  }

  // ========== THE BIOS (NATIVE BOOT) ==========
  async powerOn() {
    if (this._isBooting) return;
    this._isBooting = true;
    try {
      this.reset();

      // If OPFS is available, hydrate the filesystem from disk BEFORE anything else.
      // This ensures deleted files stay deleted — the disk is the source of truth.
      // Only fall back to fsRepairSystemFiles when OPFS is not available.
      if (opfsDriver.isAvailable() && await opfsDriver.diskExists()) {
        this.addBootLog('BIOS: Loading filesystem from disk...');
        this._diskDriver = opfsDriver;
        await this.hydrateFromDisk();
      } else {
        // No OPFS disk yet — use defaultNodes and repair system files
        // (first boot, or browser without OPFS support)
        this.fsDeepReformat();
      }

      this._isBootFinished = false; // Fresh start
      this.bootPhase = 'BIOS_POST';
      this.addBootLog('ObsidianOS BIOS v2.4.0');
      this.addBootLog('Checking Hardware... OK');
      
      this.bootPhase = 'BIOS_HARDWARE';
      this.addBootLog('Scanning for drives... Done [C: FIXED]');
      
      let bootmgr = this.fsGetNode('C:\\ObsidianOS\\System32\\bootmgr.obx');
      if (!bootmgr) {
        if (this._diskDriver) {
          // OPFS is active — the file was genuinely deleted. No auto-repair.
          this.addBootLog('BOOTMGR not found. Boot failure.');
          this.triggerBSOD({
            stopCode: 'BOOT_LOADER_FAILURE',
            technicalInfo: 'bootmgr.obx is missing from C:\\ObsidianOS\\System32. The system cannot boot.',
            failedComponent: 'bootmgr.obx',
            bugCheckCode: '0x000000F4',
            parameters: ['bootmgr.obx', 'C:\\ObsidianOS\\System32', '0x0', '0x0'],
          });
          return;
        }
        // No OPFS — safe to auto-repair from defaultNodes
        this.addBootLog('BOOTMGR not found. Starting Auto-Repair...');
        this.fsDeepReformat();
        bootmgr = this.fsGetNode('C:\\ObsidianOS\\System32\\bootmgr.obx');
        if (!bootmgr) throw new Error('SYSTEM_REPAIR_FAILED');
        this.addBootLog('Auto-Repair Success. BOOTMGR Restored.');
      }

      this.addBootLog('Locating Bootloader... Found [C:\\ObsidianOS\\System32\\bootmgr.obx]');
      this.bootPhase = 'BOOTLOADER';

      // Pre-flight: restore critical boot config files if missing
      // (boot.ini, win.ini — these are system files but can be safely restored without wiping user data)
      const criticalBootFiles = [
        'C:\\ObsidianOS\\System32\\boot.ini',
        'C:\\ObsidianOS\\System32\\win.ini',
      ];
      for (const filePath of criticalBootFiles) {
        if (!this.fsGetNode(filePath)) {
          const def = defaultNodes[filePath];
          if (def) {
            this._filesystem.set(filePath, { ...def });
            if (this._diskDriver) {
              await this._diskDriver.writeContent(filePath, def.content || '');
              await this._diskDriver.writeMeta({ ...def });
            }
            this.addBootLog(`BIOS: Restored missing ${filePath.split('\\').pop()}`);
          }
        }
      }

      this.addBootLog('Handing over control to Boot Manager...');
      
      const pid = this.createProcess('bootmgr.obx', 'Boot Manager', '⚙️');
      this.executeBinary(pid, 'C:\\ObsidianOS\\System32\\bootmgr.obx');
    } catch (e: any) {
      this.log('ERROR', 'BIOS', `Hardware Failure: ${e.message}`);
      this.addBootLog('!!! BIOS HARDWARE FAILURE !!!');
      this.addBootLog('Reason: ' + e.message);
      this.bootPhase = 'BOOT_FAILURE';
    }
  }

  finalizeBoot() {
    this.addBootLog('Native Boot Handoff... OK');
    this.log('INFO', 'Kernel', 'Boot Manager handoff successful.');
    setTimeout(() => {
      this._isBooting = false;
      this._isBootFinished = true;
      this._isInitialized = true;
      this.startUptimeCounter();
      this.startScheduler();
      this.emit('boot:finished');
    }, 150);
  }

  async loadShell(): Promise<boolean> {
    // Guard against double execution (React StrictMode / concurrent calls)
    if (this._shellLoaded) return true;
    this._shellLoaded = true;

    const explorer = this.fsGetNode('C:\\ObsidianOS\\System32\\explorer.obx');
    if (!explorer) {
      this.triggerBSOD({
        stopCode: 'SHELL_INITIALIZATION_FAILED',
        technicalInfo: 'explorer.obx not found. Cannot load desktop shell.',
        failedComponent: 'explorer.obx',
        bugCheckCode: '0x000000F4',
        parameters: ['explorer.obx', 'C:\\ObsidianOS\\System32'],
      });
      return false;
    }

    this.bootPhase = 'SHELL_INIT';
    this.addBootLog('Starting Desktop Shell...');

    // App Discovery — scan System32 for app manifests and register them
    const fsProxy = {
      getChildren: (path: string) => this.fsGetChildren(path),
    };
    const { useAppRegistry } = await import('./appRegistry');
    const registryProxy = useAppRegistry.getState();
    await this.scanSystemApps(fsProxy, registryProxy);
    
    // Create processes
    this.createProcess('explorer.obx', 'ObsidianOS Explorer', '📁');
    this._resources.usedMemory += 96;

    const dwm = this.fsGetNode('C:\\ObsidianOS\\System32\\dwm.obx');
    if (dwm) {
      this.createProcess('dwm.obx', 'Desktop Window Manager', '🖥️');
      this._resources.usedMemory += 72;
    }

    const searchHost = this.fsGetNode('C:\\ObsidianOS\\System32\\SearchHost.obx');
    if (searchHost) {
      this.createProcess('SearchHost.obx', 'Search Host', '🔍');
      this._resources.usedMemory += 48;
    }

    // Check OOBE flag — if SetupInProgress is set, go to setup wizard first
    const setupInProgress = this.regGetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress');
    if (setupInProgress === 1) {
      this.log('INFO', 'Kernel', 'OOBE detected — launching Setup Wizard');
      this.bootPhase = 'OOBE';
    } else {
      // Normal boot — hand off to Winlogon (LockScreen handles auth in React)
      this.bootPhase = 'WINLOGON';
    }

    this.log('INFO', 'Kernel', 'Session manager handoff complete');
    return true;
  }


  // ========== System Init ==========
  private _initSystemState() {
    if (typeof window === 'undefined') return;
    const saved = localStorage.getItem('obsidianos-system-v2');
    if (saved) {
      try {
        const parsed = JSON.parse(saved);
        this._user = { ...this._user, ...parsed.user };
        this._theme = { ...this._theme, ...parsed.theme };
        this._hardware = { ...this._hardware, ...parsed.hardware };
      } catch (e) {
        console.error('Failed to parse obsidianos-system-v2', e);
      }
    } else {
      const legacy = localStorage.getItem('webos-system-v2') || localStorage.getItem('webos-system');
      if (legacy) {
        try {
          const parsed = JSON.parse(legacy);
          const state = parsed.state || parsed; // Handle different structures
          if (state) {
            this._user = { ...this._user, ...(state.user || state.currentUser) };
            this._theme = { ...this._theme, ...state.theme };
            this._hardware = {
              volume: state.volume ?? state.hardware?.volume ?? 75,
              isMuted: state.isMuted ?? state.hardware?.isMuted ?? false,
              brightness: state.brightness ?? state.hardware?.brightness ?? 100,
              isWifiConnected: state.isWifiConnected ?? state.hardware?.isWifiConnected ?? true,
              isBluetooth: state.isBluetooth ?? state.hardware?.isBluetooth ?? false,
              batteryLevel: state.batteryLevel ?? state.hardware?.batteryLevel ?? 85,
            };
          }
          this._persistSystemState();
        } catch (e) {
          console.error('Failed to parse legacy system state', e);
        }
      }
    }
  }

  // ========== File System Init ==========
  private _initFileSystem() {
    if (typeof window === 'undefined') {
      this._filesystem = new Map(Object.entries(defaultNodes));
      return;
    }

    // Migrate or load
    const savedFsV2 = localStorage.getItem('obsidianos-filesystem-v2');
    if (savedFsV2) {
      try {
        const parsed: Record<string, FileSystemNode> = JSON.parse(savedFsV2);

        // ── .exe → .obx migration ──────────────────────────────────────────
        // If the saved FS still has .exe executables, it's stale — wipe and
        // rebuild from defaultNodes so the new .obx paths take effect.
        const hasLegacyExe = Object.values(parsed).some(
          n => n.extension === 'exe' && (n.metadata?.type === 'binary_executable' || n.metadata?.type === 'app_executable')
        );
        if (hasLegacyExe) {
          console.info('[Kernel] Detected legacy .exe filesystem — migrating to .obx');
          localStorage.removeItem('obsidianos-filesystem-v2');
          this._filesystem = new Map(Object.entries(defaultNodes));
          this._persistFileSystem();
          return;
        }
        // ──────────────────────────────────────────────────────────────────

        this._filesystem = new Map(Object.entries(parsed));
        return;
      } catch (e) {
        console.error('Failed to parse obsidianos-filesystem-v2', e);
      }
    }

    const legacyFs = localStorage.getItem('webos-filesystem-v2') || localStorage.getItem('webos-filesystem');
    if (legacyFs) {
      try {
        const parsed = JSON.parse(legacyFs);
        const nodes = parsed?.state?.nodes || parsed;
        this._filesystem = new Map(Object.entries(nodes));
        this._persistFileSystem(); // Save as ObsidianOS V2
        return;
      } catch (e) {
        console.error('Failed to parse legacy filesystem', e);
      }
    }

    this._filesystem = new Map(Object.entries(defaultNodes));
    this._persistFileSystem();
  }

  // ========== Registry Init ==========
  private _initRegistry() {
    if (typeof window === 'undefined') {
      this._registry = JSON.parse(JSON.stringify(defaultRegistry));
      return;
    }

    let loaded = false;

    // Try to load ObsidianOS V2 registry first
    const savedRegV2 = localStorage.getItem('obsidianos-registry-v2');
    if (savedRegV2) {
      try {
        this._registry = JSON.parse(savedRegV2);
        loaded = true;
      } catch (e) {
        console.error('Failed to parse obsidianos-registry-v2, attempting legacy migration.', e);
      }
    }

    // If not loaded from V2, try to migrate from legacy
    if (!loaded) {
      const legacyReg = localStorage.getItem('webos-registry-v2') || localStorage.getItem('webos-registry');
      if (legacyReg) {
        try {
          const parsed = JSON.parse(legacyReg);
          this._registry = parsed?.state?.hives || parsed;
          this._persistRegistry();
          loaded = true;
        } catch (e) {
          console.error('Failed to parse legacy registry, falling back to default.', e);
        }
      }
    }

    // If still not loaded, use default registry
    if (!loaded) {
      this._registry = JSON.parse(JSON.stringify(defaultRegistry));
      this._persistRegistry();
    }

    // ── Setup flag correction ──────────────────────────────────────────────
    // If setup was already completed (localStorage flag), ensure the registry
    // reflects that — even if the saved registry still has SetupInProgress = 1
    // (e.g. from a previous session before this fix was applied).
    if (localStorage.getItem('obsidianos-setup-completed') === 'true') {
      const setupKey = 'HKEY_LOCAL_MACHINE\\SYSTEM\\Setup';
      if (!this._registry[setupKey]) this._registry[setupKey] = {};
      this._registry[setupKey]['SetupInProgress'] = { type: 'REG_DWORD', value: 0 };
      this._registry[setupKey]['OOBEInProgress']  = { type: 'REG_DWORD', value: 0 };
    }
    // ──────────────────────────────────────────────────────────────────────
  }

  // ========== System Process Init ==========
  // Popula a tabela de processos com os processos base do SO.
  // NÃO emite eventos — a inicialização é silenciosa.
  private _initSystemProcesses() {
    type InitProc = Pick<Process, 'pid' | 'name' | 'title' | 'icon' | 'memoryUsage' | 'cpuUsage'>;
    // NOTE: 'System' (PID 0) is intentionally absent — it is created by bootmgr.obx
    // during the boot sequence so it appears as a real boot-time process.
    // explorer.obx, dwm.obx, SearchHost.obx are created by loadShell().
    const INITIAL: InitProc[] = [
      { pid: 1, name: 'smss.obx',    title: 'Session Manager Subsystem',        icon: '⚙️', memoryUsage: 12.1,  cpuUsage: 0 },
      { pid: 2, name: 'csrss.obx',   title: 'Client Server Runtime Process',    icon: '⚙️', memoryUsage: 45.8,  cpuUsage: 0.2 },
      { pid: 3, name: 'wininit.obx', title: 'ObsidianOS Start-Up Application',  icon: '⚙️', memoryUsage: 18.5,  cpuUsage: 0 },
      { pid: 4, name: 'services.obx',title: 'Services and Controller App',      icon: '⚙️', memoryUsage: 82.2,  cpuUsage: 0.3 },
      { pid: 5, name: 'lsass.obx',   title: 'Local Security Authority Process', icon: '🔒', memoryUsage: 124.4, cpuUsage: 0.1 },
      { pid: 6, name: 'svchost.obx', title: 'Service Host: Local System',       icon: '⚙️', memoryUsage: 428.6, cpuUsage: 0.5 },
    ];
    const startTime = Date.now();
    let totalRam = 0;
    INITIAL.forEach(p => {
      const proc = this._makeProcess(p.pid, p.name, p.title, p.icon, 0, 'NORMAL');
      proc.memoryUsage = p.memoryUsage;
      proc.cpuUsage    = p.cpuUsage;
      proc.startTime   = startTime;
      this._processes.set(p.pid, proc);
      this._addToRunQueue(proc);
      totalRam += p.memoryUsage;
    });
    this._resources.usedMemory = totalRam;
  }

  static getInstance(): Kernel {
    if (!Kernel.instance) {
      Kernel.instance = new Kernel();
    }
    return Kernel.instance;
  }

  // ========== Event System ==========
  on(event: string, callback: (...args: any[]) => void) {
    if (!this._listeners.has(event)) {
      this._listeners.set(event, new Set());
    }
    this._listeners.get(event)?.add(callback);
    return () => this.off(event, callback);
  }

  once(event: string, callback: (...args: any[]) => void) {
    const wrapper = (...args: any[]) => {
      this.off(event, wrapper);
      callback(...args);
    };
    return this.on(event, wrapper);
  }

  off(event: string, callback: (...args: any[]) => void) {
    this._listeners.get(event)?.delete(callback);
  }

  emit(event: string, ...args: any[]) {
    this._listeners.get(event)?.forEach(cb => {
      try { cb(...args); } catch (e) { 
        this.log('ERROR', 'Kernel', `Event handler error: ${event}: ${e}`);
      }
    });
  }

  // ========== Logging ==========
  log(level: KernelLogLevel, source: string, message: string, code?: string) {
    const entry: KernelLogEntry = {
      timestamp: Date.now(),
      level,
      source,
      message,
      code,
    };
    this._logs.push(entry);
    this.emit('log', entry);

    // On FATAL, trigger BSOD
    if (level === 'FATAL') {
      this.triggerBSOD({
        stopCode: code || 'CRITICAL_PROCESS_DIED',
        technicalInfo: message,
        failedComponent: source,
        bugCheckCode: '0x000000EF',
        parameters: [source, message],
      });
    }
  }

  addBootLog(message: string) {
    this._bootLog.push(message);
    this.emit('bootLog', message);
  }

  // ========== Boot Phase ==========
  get isBooting() { return this._isBooting; }
  get isBootFinished() { return this._isBootFinished; }
  get bootPhase() { return this._bootPhase; }
  set bootPhase(phase: BootPhase) {
    const prevPhase = this._bootPhase;
    this._bootPhase = phase;
    this.log('INFO', 'Kernel', `Boot phase: ${prevPhase} -> ${phase}`);
    this.emit('bootPhaseChange', phase, prevPhase);
    
    // Sync with React Store
    const storePhaseMap: Record<string, any> = {
      'OFF': 'off',
      'BIOS_POST': 'bios',
      'BIOS_HARDWARE': 'bios',
      'BOOTLOADER': 'bios',
      'KERNEL_INIT': 'loading',
      'HAL_INIT': 'loading',
      'DRIVER_LOAD': 'loading',
      'SERVICE_INIT': 'loading',
      'SHELL_INIT': 'loading',
      'OOBE': 'setup',
      'WINLOGON': 'login',
      'BOOT_FAILURE': 'bios'
      // NOTE: DESKTOP_READY is intentionally omitted — the transition to 'desktop'
      // is handled by LockScreen after the user logs in via kernel.sysLogin()
    };
    try {
      this.emit('system:bootPhase', storePhaseMap[phase] || 'loading');
    } catch(e) {
      console.error("Kernel Store Sync Failed", e);
    }
  }
  
  // ========== System State Management ==========
  private _emitSystemSnapshot() {
    this.emit('system:snapshot', {
      user: this._user,
      isLocked: this._isLocked,
      theme: this._theme,
      hardware: this._hardware,
    });
  }

  private _persistSystemState() {
    if (typeof window === 'undefined') return;
    const state = { user: this._user, theme: this._theme, hardware: this._hardware };
    localStorage.setItem('obsidianos-system-v2', JSON.stringify(state));
    this._emitSystemSnapshot();
  }

  sysGetSnapshot() {
    return {
      user: this._user,
      isLocked: this._isLocked,
      theme: this._theme,
      hardware: this._hardware,
    };
  }

  sysLogin(password: string): boolean {
    if (this._user.password === '' || password === this._user.password) {
      this._isLocked = false;
      this._user.lastLogin = Date.now();
      this._persistSystemState();
      this.emit('system:bootPhase', 'desktop');
      return true;
    }
    return false;
  }

  sysLock() {
    this._isLocked = true;
    this._persistSystemState();
    this.emit('system:bootPhase', 'login');
  }

  sysUnlock() {
    this._isLocked = false;
    this._persistSystemState();
    this.emit('system:bootPhase', 'desktop');
  }

  sysSetTheme(updates: Partial<SystemTheme>) {
    this._theme = { ...this._theme, ...updates };
    this._persistSystemState();
  }

  sysSetVolume(volume: number) {
    this._hardware.volume = Math.max(0, Math.min(100, volume));
    this._persistSystemState();
  }

  sysToggleMute() {
    this._hardware.isMuted = !this._hardware.isMuted;
    this._persistSystemState();
  }

  sysSetBrightness(brightness: number) {
    this._hardware.brightness = Math.max(0, Math.min(100, brightness));
    this._persistSystemState();
  }

  sysToggleWifi() {
    this._hardware.isWifiConnected = !this._hardware.isWifiConnected;
    this._persistSystemState();
  }

  sysToggleBluetooth() {
    this._hardware.isBluetooth = !this._hardware.isBluetooth;
    this._persistSystemState();
  }

  // ========== Resources ==========
  get resources() { return { ...this._resources }; }
  
  allocateMemory(amount: number, processName: string): boolean {
    if (this._resources.usedMemory + amount > this._resources.totalMemory) {
      this.log('ERROR', 'MemoryManager', 
        `Out of memory: ${processName} requested ${amount}MB, available: ${this._resources.totalMemory - this._resources.usedMemory}MB`,
        'OUT_OF_MEMORY');
      return false;
    }
    this._resources.usedMemory += amount;
    this.emit('memoryChange', this._resources);
    return true;
  }

  freeMemory(amount: number) {
    this._resources.usedMemory = Math.max(0, this._resources.usedMemory - amount);
    this.emit('memoryChange', this._resources);
  }

  updateCpuUsage(usage: number) {
    this._resources.cpuUsage = Math.min(100, Math.max(0, usage));
    this.emit('cpuChange', this._resources);
  }

  // ========== Drivers ==========
  registerDriver(driver: DriverEntry) {
    this._drivers.set(driver.name, driver);
    this.emit('driverChange', driver);
  }

  getDriver(name: string) { return this._drivers.get(name); }
  getAllDrivers() { return Array.from(this._drivers.values()); }

  // ========== Services ==========
  registerService(service: ServiceEntry) {
    this._services.set(service.name, service);
    this.emit('serviceChange', service);
  }

  getService(name: string) { return this._services.get(name); }
  getAllServices() { return Array.from(this._services.values()); }

  updateServiceStatus(name: string, status: ServiceEntry['status'], error?: string) {
    const service = this._services.get(name);
    if (service) {
      service.status = status;
      if (error) service.errorMessage = error;
      if (status === 'failed') service.restartCount++;
      this.emit('serviceChange', service);
    }
  }

  // ========== BSOD ==========
  get bsodInfo() { return this._bsodInfo; }

  triggerBSOD(info: BSODInfo) {
    this._bsodInfo = {
      stopCode: info.stopCode || 'CRITICAL_PROCESS_DIED',
      technicalInfo: info.technicalInfo || 'No extra info',
      failedComponent: info.failedComponent || 'Unknown',
      bugCheckCode: info.bugCheckCode || '0x00000000',
      parameters: info.parameters || ['0x0', '0x0', '0x0', '0x0'],
    };
    this._bootPhase = 'BSOD';
    this.log('CRITICAL', 'Kernel', 
      `BSOD: ${info.stopCode} - ${info.technicalInfo}`);
    this.emit('bsod', info);
    this.emit('bootPhaseChange', 'BSOD', this._bootPhase);
    
    // Stop uptime counter and scheduler
    if (this._uptimeInterval) clearInterval(this._uptimeInterval);
    this.stopScheduler();
  }

  // ========== Uptime & Resource Loop ==========
  startUptimeCounter() {
    this._initTime = Date.now();
    this._uptimeInterval = setInterval(() => {
      this._resources.uptime = Math.floor((Date.now() - this._initTime) / 1000);
    }, 1000);
    this.startResourceLoop();
  }

  private _resourceInterval: ReturnType<typeof setInterval> | null = null;

  startResourceLoop() {
    if (this._resourceInterval) clearInterval(this._resourceInterval);
    
    this._resourceInterval = setInterval(() => {
      // In a real OS, the scheduler/kernel calculates this. 
      // We will pull from the processManager store directly to sync.
      // Note: We'll use a dynamic import or access the store via global if needed, 
      // but here we can just emit an event and let the stores respond or vice versa.
      // Better: The kernel is the source of truth, but since processManager 
      // is a store, we'll let it push updates or the kernel can pull if it has access.
      
      this.emit('resourceTick');
      
      // Check for Memory Overload
      if (this._resources.usedMemory > this._resources.totalMemory) {
         this.triggerBSOD({
            stopCode: 'MEMORY_MANAGEMENT',
            technicalInfo: `Physical memory exhausted. Used: ${this._resources.usedMemory}MB / Total: ${this._resources.totalMemory}MB`,
            failedComponent: 'ntoskrnl.exe',
            bugCheckCode: '0x0000001A',
            parameters: ['0x00000417', '0x00000000', '0x00000000', '0x00000000']
         });
      }
    }, 2000);
  }

  // ========== App Discovery ==========
  // Scans designated directories for .exe files and registers them as apps
  async scanSystemApps(fs: any, registry: any) {
    this.log('INFO', 'Discovery', 'Scanning system directories for executables...');
    
    try {
      const system32 = fs.getChildren('C:\\ObsidianOS\\System32');
      const progFiles = fs.getChildren('C:\\Program Files\\ObsidianOS Apps');
      const sdkExamples = fs.getChildren('C:\\ObsidianOS\\SDK\\examples');
      const executables = [...system32, ...progFiles].filter((node: any) => node.extension === 'obx');
      
      this.log('INFO', 'Discovery', `Found ${executables.length} potential executables.`);
      
      for (const node of executables) {
        try {
          // Some .exe are binary blobs (system files), others are JSON manifests (web shortcuts)
          const content = node.content;
          if (content && content.startsWith('{')) {
            const manifest = JSON.parse(content);
            if (manifest.type === 'executable' && manifest.appId) {
              this.log('DEBUG', 'Discovery', `Registering app: ${manifest.name} (${manifest.appId})`);
              
              registry.registerApp({
                id: manifest.appId,
                name: manifest.name,
                icon: manifest.icon,
                category: manifest.category || 'system',
                defaultWidth: manifest.width || 800,
                defaultHeight: manifest.height || 600,
                minWidth: manifest.minWidth || 300,
                minHeight: manifest.minHeight || 200,
                isResizable: manifest.isResizable !== false,
                isSingleInstance: manifest.isSingleInstance === true,
              });
            }
          }
        } catch (e) {
          this.log('WARN', 'Discovery', `Skipped ${node.name}: Not a valid manifest. (${e})`);
        }
      }

      // Register SDK example .exe files as runnable SDK apps
      const sdkExes = sdkExamples.filter((node: any) => node.extension === 'obx');
      this.log('INFO', 'Discovery', `Found ${sdkExes.length} SDK example(s).`);
      for (const node of sdkExes) {
        const appId = `sdk:${node.name}`;
        this.log('DEBUG', 'Discovery', `Registering SDK app: ${node.name} (${appId})`);
        registry.registerApp({
          id: appId,
          name: node.name,
          icon: '⚡',
          category: 'utilities',
          defaultWidth: 600,
          defaultHeight: 400,
          minWidth: 300,
          minHeight: 200,
          isResizable: true,
          isSingleInstance: false,
          binaryPath: node.path,
        });
      }
      
      registry.setReady(true);
      this.log('INFO', 'Discovery', 'App discovery complete.');
    } catch (e) {
      this.log('ERROR', 'Discovery', `Discovery failed: ${e}`);
    }
  }

  // ========== OPFS / Disk Driver ==========

  // Called by volmgr.sys/ntfs.sys binaries to register the real disk driver
  async registerFsDriver(driver: OPFSDriver): Promise<void> {
    this._diskDriver = driver;
    this.log('INFO', 'Kernel', 'Filesystem driver registered (OPFS)');
  }

  // Called by ntfs.sys after volmgr mounts the disk
  async hydrateFromDisk(): Promise<number> {
    if (!this._diskDriver) return 0;
    try {
      const nodes = await this._diskDriver.hydrateCache();
      this._filesystem = new Map(Object.entries(nodes));
      this.log('INFO', 'Kernel', `Hydrated ${this._filesystem.size} nodes from OPFS`);
      this.emit('fs:snapshot', Object.fromEntries(this._filesystem));
      return this._filesystem.size;
    } catch (e) {
      this.log('ERROR', 'Kernel', `Hydration failed: ${e}`);
      return 0;
    }
  }

  // Returns the default node map — used by volmgr.sys on first format
  getDefaultNodes(): Record<string, FileSystemNode> {
    return { ...defaultNodes };
  }

  // Helpers exposed to driver binaries
  getFsNodeCount(): number { return this._filesystem.size; }
  isDiskDriverActive(): boolean { return this._diskDriver !== null; }

  // Startup Repair — restores missing/corrupted system files.
  // Prefers VSS snapshot (C:\System Volume Information\VSS\snapshot.json) over hardcoded defaults.
  async fsStartupRepair(): Promise<{ fixed: number; files: string[] }> {
    this.log('WARN', 'StartupRepair', 'Startup Repair initiated.');
    const fixed: string[] = [];

    // Try to load VSS snapshot first
    let vssSnapshot: Record<string, string> | null = null;
    const snapshotPath = 'C:\\System Volume Information\\VSS\\snapshot.json';
    const snapshotNode = this._filesystem.get(snapshotPath);
    if (snapshotNode?.content) {
      try {
        const parsed = JSON.parse(snapshotNode.content);
        if (parsed?.files && typeof parsed.files === 'object') {
          vssSnapshot = parsed.files;
          this.log('INFO', 'StartupRepair', `VSS snapshot loaded (${Object.keys(vssSnapshot!).length} files, ts=${parsed.timestamp})`);
        }
      } catch {
        this.log('WARN', 'StartupRepair', 'VSS snapshot parse failed — falling back to defaults');
      }
    } else {
      this.log('WARN', 'StartupRepair', 'No VSS snapshot found — using hardcoded defaults');
    }

    for (const [key, defaultNode] of Object.entries(defaultNodes)) {
      if (!defaultNode.attributes.isSystem) continue;
      const current = this._filesystem.get(key);
      const isMissing = !current;
      const isCorrupted = current && defaultNode.type === 'file' &&
        defaultNode.content && current.content !== defaultNode.content &&
        defaultNode.attributes.isSystem;

      if (isMissing || isCorrupted) {
        const restored = { ...defaultNode };

        // Use VSS snapshot content if available for this file
        if (vssSnapshot && defaultNode.type === 'file' && vssSnapshot[key] !== undefined) {
          restored.content = vssSnapshot[key];
          restored.size = vssSnapshot[key].length;
        }

        this._filesystem.set(key, restored);
        if (this._diskDriver) {
          if (defaultNode.type === 'directory') {
            await this._diskDriver.createDirectory(key);
          } else {
            await this._diskDriver.writeContent(key, restored.content || '');
          }
          await this._diskDriver.writeMeta(restored);
        }
        fixed.push(key);
        this.log('INFO', 'StartupRepair', `Restored: ${key}${vssSnapshot ? ' (VSS)' : ' (default)'}`);
      }
    }

    this.log('INFO', 'StartupRepair', `Repair complete. ${fixed.length} file(s) restored.`);
    return { fixed: fixed.length, files: fixed };
  }

  // Async driver loader — executes a .sys binary and awaits its completion
  // Used by bootmgr.exe for volmgr.sys and ntfs.sys
  async loadDriverAsync(path: string): Promise<boolean> {
    const node = this.fsGetNode(path);
    if (!node || !node.content) {
      this.log('ERROR', 'Kernel', `loadDriverAsync: ${path} not found`);
      return false;
    }
    return new Promise<boolean>((resolve) => {
      const pid = this.createProcess(node.name, node.name, '⚙️');
      let settled = false;

      const offTerminated = this.on('process:terminated', (terminatedPid: number) => {
        if (terminatedPid === pid && !settled) {
          settled = true;
          offTerminated();
          resolve(true);
        }
      });

      // Execute — the binary calls OS.terminate(0) when done
      this.executeBinary(pid, path).catch((e) => {
        this.log('ERROR', 'Kernel', `loadDriverAsync execution error: ${e}`);
        if (!settled) { settled = true; offTerminated(); resolve(false); }
      });

      // Safety timeout — 10s
      setTimeout(() => {
        if (!settled) {
          settled = true;
          offTerminated();
          this.log('WARN', 'Kernel', `loadDriverAsync timeout: ${path}`);
          resolve(false);
        }
      }, 10000);
    });
  }

  // ========== Process Management ==========
  createProcess(name: string, title: string, icon: string, windowId?: string, binaryPath?: string, args: string[] = [], priority: ProcessPriority = 'NORMAL'): number {
    const pid = this._nextPid++;
    const proc = this._makeProcess(pid, name, title, icon, 0, priority);
    proc.windowId = windowId;
    this.allocateMemory(proc.memoryUsage, name);
    this._processes.set(pid, proc);
    this._addToRunQueue(proc);
    this.log('DEBUG', 'ProcessManager', `Created: ${name} [PID:${pid}] priority=${priority}`);
    this.emit('process:created', proc);

    if (binaryPath) {
      this.executeBinary(pid, binaryPath, args);
    }

    return pid;
  }

  // ── Scheduler helpers ──────────────────────────────────────────────────────

  private _makeProcess(pid: number, name: string, title: string, icon: string, ppid: number, priority: ProcessPriority): Process {
    const quantum = Kernel.QUANTUM_MS[priority];
    return {
      pid, ppid, name, title, icon,
      state: 'READY',
      priority,
      quantum,
      quantumUsed: 0,
      totalCpuTime: 0,
      lastScheduled: Date.now(),
      memoryUsage: Math.random() * 80 + 30,
      cpuUsage: 0,
      pendingSignals: [],
      signalHandlers: {},
      startTime: Date.now(),
      windowId: undefined,
      currentDirectory: 'C:\\Users\\User',
      stdin: [],
      // legacy compat
      status: 'running',
    };
  }

  private _addToRunQueue(proc: Process) {
    const q = this._runQueues.get(proc.priority)!;
    if (!q.includes(proc.pid)) q.push(proc.pid);
  }

  private _removeFromRunQueues(pid: number) {
    for (const q of this._runQueues.values()) {
      const i = q.indexOf(pid);
      if (i !== -1) q.splice(i, 1);
    }
  }

  // ── I/O ────────────────────────────────────────────────────────────────────
  writeStdin(pid: number, data: string) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    
    proc.stdin.push(data);
    this.log('DEBUG', 'Kernel', `Stdin [PID:${pid}]: ${data}`);
    this.emit(`process:stdin:${pid}`, data);
  }

  readStdin(pid: number): Promise<string> {
    return new Promise((resolve) => {
      const proc = this._processes.get(pid);
      if (!proc) { resolve(''); return; }

      if (proc.stdin.length > 0) {
        resolve(proc.stdin.shift()!);
        return;
      }

      // Wait for input
      const handler = (data: string) => {
        this.off(`process:stdin:${pid}`, handler);
        proc.stdin.shift(); // Remove it as we just read it
        resolve(data);
      };
      this.on(`process:stdin:${pid}`, handler);
    });
  }

  // ========== Binary Execution Engine ==========
  async executeBinary(pid: number, path: string, args: string[] = []) {
    let rawNode = this.fsGetNode(path);
    if (!rawNode || rawNode.type !== 'file' || !rawNode.content) {
      // Auto-repair missing default system files
      if (typeof window !== 'undefined' && (window as any).__obsidian_defaultNodes && (window as any).__obsidian_defaultNodes[path]) {
         rawNode = (window as any).__obsidian_defaultNodes[path];
         this._filesystem.set(path, rawNode!);
         this._persistFileSystem();
      } else {
        this.log('ERROR', 'ExecutionEngine', `Binary not found or corrupted: ${path}`);
        this.emit('process:stdout', { pid, message: `ERROR: Binary not found: ${path}` });
        // Don't terminate — let the window stay open showing the error
        return;
      }
    }
    const node = rawNode!;

    const proc = this.getProcess(pid);
    if (!proc) return;

    this.log('INFO', 'ExecutionEngine', `Executing binary: ${path} [PID:${pid}]`);

    // System Calls Definition
    const OS: Record<string, any> = {
      pid,
      args,
      // ── I/O ──────────────────────────────────────────────────────────────
      print:     (msg: string) => { this.emit('process:stdout', { pid, message: String(msg) }); this.log('DEBUG', `Proc:${pid}`, String(msg)); },
      error:     (msg: string) => { this.emit('process:stderr', { pid, message: String(msg) }); this.log('ERROR', `Proc:${pid}`, String(msg)); },
      // ── File System ───────────────────────────────────────────────────────
      readFile:  (p: string) => this.fsGetNode(p)?.content ?? undefined,
      writeFile: (p: string, c: string) => {
        const parts = p.split('\\'); const name = parts.pop()!; const parent = parts.join('\\');
        this.fsCreateFile(parent, name, c, name.split('.').pop() || 'txt');
      },
      listFiles: (p: string) => this.fsGetChildren(p).map((n: FileSystemNode) => n.name),
      // ── Process ───────────────────────────────────────────────────────────
      terminate:       (exitCode: number = 0) => { this.log('INFO', `Proc:${pid}`, `Exit(${exitCode})`); this.terminateProcess(pid); },
      createProcess:   (n: string, t: string, i: string) => this.createProcess(n, t, i),
      allocateMemory:  (mb: number, name: string) => this.allocateMemory(mb, name),
      // ── Signals ───────────────────────────────────────────────────────────
      signal:          (targetPid: number, sig: Signal) => this.sendSignal(targetPid, sig),
      onSignal:        (sig: Signal, fn: string) => this.installSignalHandler(pid, sig, 'CUSTOM', fn),
      ignoreSignal:    (sig: Signal) => this.installSignalHandler(pid, sig, 'IGNORE'),
      setPriority:     (p: ProcessPriority) => this.setPriority(pid, p),
      // ── Boot ──────────────────────────────────────────────────────────────
      addBootLog:   (m: string) => this.addBootLog(m),
      setBootPhase: (p: any)   => { this.bootPhase = p; },
      finalizeBoot: ()         => this.finalizeBoot(),
      triggerBSOD:  (i: any)   => this.triggerBSOD(i),
      // ── Drivers ───────────────────────────────────────────────────────────
      loadDriverAsync: (driverPath: string): Promise<boolean> => this.loadDriverAsync(driverPath),
      registerDriver:  (entry: any) => this.registerDriver({ loadOrder: 0, dependencies: [], ...entry }),
      registerService: (entry: any) => this.registerService({ dependencies: [], restartCount: 0, ...entry }),
      // ── Libraries ─────────────────────────────────────────────────────────
      loadLibrary: (dllPath: string): boolean => {
        const dllNode = this.fsGetNode(dllPath);
        if (!dllNode || !dllNode.content) return false;
        try {
          const dllFn = new Function('OS', 'kernel', `"use strict";\n${dllNode.content}`);
          dllFn(OS, this);
          return true;
        } catch (e: any) {
          this.log('ERROR', 'ExecutionEngine', `loadLibrary failed for ${dllPath}: ${e.message}`);
          return false;
        }
      },
      // ── Resources ─────────────────────────────────────────────────────────
      getResources:  () => ({ ...this._resources }),
      getEnv:        (key: string) => key === 'OS' ? 'ObsidianOS_NT' : key === 'USER' ? this._user.username : '',
      getTimestamp:  () => Date.now(),
      ping:          () => ({ status: 'ok', latency: Math.floor(Math.random() * 20) + 1 }),
      wait:          (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms)),
      stdin: {
        read: () => this.readStdin(pid),
      },
      // ── Namespaced aliases (for obslogon.exe and other system binaries) ───
      Registry: {
        GetValue: (key: string, val: string) => this.regGetValue(`${key}\\${val}`),
        SetValue: (key: string, val: string, type: any, value: any) => this.regSetValue(`${key}\\${val}`, type, value),
      },
      User: {
        IsAuthenticated: () => !this._isLocked && this._isInitialized,
      },
      Process: {
        Create: (n: string, t: string, i: string) => this.createProcess(n, t, i),
        Terminate: (p: number) => this.terminateProcess(p),
      },
      Kernel: {
        AddBootLog:   (m: string) => this.addBootLog(m),
        SetBootPhase: (p: any)   => { this.bootPhase = p; },
        TriggerBSOD:  (i: any)   => this.triggerBSOD(i),
        FinalizeBoot: ()         => this.finalizeBoot(),
      },
      Utils: {
        Sleep: (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms)),
      },
      fs: {
        getcwd: () => proc.currentDirectory,
        chdir: (p: string) => {
          const node = this.fsGetNode(p);
          if (node && node.type === 'directory') {
            proc.currentDirectory = p;
            return true;
          }
          return false;
        }
      }
    };

    const systemFolder  = path.startsWith('C:\\ObsidianOS\\System32');
    const sdkFolder     = path.startsWith('C:\\ObsidianOS\\SDK');
    const progFiles     = path.startsWith('C:\\Program Files');
    const userDocs      = path.startsWith('C:\\Users');
    const ring0Binaries = ['bootmgr.obx', 'obslogon.obx', 'services.obx', 'lsass.obx'];

    // Run on main thread (with full kernel/DOM access) for:
    //  • ring-0 system binaries (bootmgr, lsass…)
    //  • SDK examples & user scripts (need OS.User32 / OS.GDI32 / kernel.emit)
    //  • anything in Program Files or user Documents
    const isSystemProcess =
      (systemFolder && ring0Binaries.some(bin => path.endsWith(bin))) ||
      sdkFolder || progFiles || userDocs;

    if (isSystemProcess) {
      try {
         const sdkNode = this.fsGetNode('C:\\ObsidianOS\\SDK\\lib\\obsidian.js');
         const sdkCode = sdkNode?.content || '';
         const isBootMgr = path.endsWith('bootmgr.obx');
         const isSdkApp  = sdkFolder || progFiles || userDocs;

         // bootmgr gets no SDK; SDK/user apps get SDK + UI DLLs pre-loaded
         let codeToRun = isBootMgr ? node.content : sdkCode + '\n' + node.content;

         // For SDK/user apps, auto-load user32.dll and gdi32.dll so OS.User32 / OS.GDI32 are available
         if (isSdkApp) {
           const user32 = this.fsGetNode('C:\\ObsidianOS\\System32\\user32.dll');
           const gdi32  = this.fsGetNode('C:\\ObsidianOS\\System32\\gdi32.dll');
           const prelude = [user32?.content, gdi32?.content].filter(Boolean).join('\n');
           codeToRun = sdkCode + '\n' + prelude + '\n' + node.content;
         }

         // Wrap in async IIFE so top-level await works inside the binary
         const asyncWrapper = new Function('OS', 'kernel', `
            "use strict";
            return (async () => {
              try {
                ${codeToRun}
              } catch(e) {
                kernel.log("ERROR", "ExecutionEngine", "Runtime Error in [${node.name}]: " + e.message);
              }
            })();
         `);

         // Fire-and-forget — the binary calls OS.terminate() or OS.finalizeBoot() when done
         asyncWrapper(OS, this).catch((e: any) => {
           this.log('ERROR', 'ExecutionEngine', `Unhandled rejection in [${node.name}]: ${e.message}`);
           // Deliver SIGABRT for unhandled promise rejections
           this.sendSignal(pid, 'SIGABRT');
         });
         return;
      } catch (e: any) {
         this.log('ERROR', 'ExecutionEngine', `System Process Load Failed: ${e.message}`);
         this.terminateProcess(pid);
         return;
      }
    }

    // --- OSL SCRIPT EXECUTION ---
    if (path.endsWith('.osl') || path.endsWith('.obx') && node.content && node.content.startsWith('system::')) {
      try {
        const source = node.content as string;
        const lexer = new Lexer(source);
        const tokens = lexer.tokenize();
        const parser = new Parser(tokens);
        const ast = parser.parse();
        const interpreter = new Interpreter(pid);
        
        // Execute asynchronously
        interpreter.interpret(ast).then(() => {
          this.log('INFO', 'OSL', `Script ${node.name} finished execution.`);
          this.terminateProcess(pid);
        }).catch(err => {
          this.log('ERROR', 'OSL', `Runtime Error in ${node.name}: ${err.message}`);
          this.emit('process:stderr', { pid, message: `Runtime Error: ${err.message}` });
          this.terminateProcess(pid);
        });
        return;
      } catch (err: any) {
        this.log('ERROR', 'OSL', `Compile Error in ${node.name}: ${err.message}`);
        this.emit('process:stderr', { pid, message: `Compile Error: ${err.message}` });
        this.terminateProcess(pid);
        return;
      }
    }

    try {
      const workerBlob = new Blob([`
        "use strict";
        let OS = {};
        let __callHandlers = new Map();
        function syscall(name, ...args) {
           return new Promise((resolve) => {
              const callId = Math.random().toString(36).substring(7);
              __callHandlers.set(callId, resolve);
              self.postMessage({ type: 'SYSCALL', name, args, callId });
           });
        }
        self.onmessage = async (e) => {
           const { type, data, callId } = e.data;
           if (type === 'BOOT') {
              const { pid, name, code, sdkCode, dlls } = data;
              self.pid = pid;
              OS = {
                 pid,
                 print: (m) => syscall('print', m),
                 error: (m) => syscall('error', m),
                 terminate: (c) => syscall('terminate', c),
                 readFile: (p) => syscall('readFile', p),
                 writeFile: (p,c) => syscall('writeFile', p, c),
                 listFiles: (p) => syscall('listFiles', p),
                 wait: (m) => new Promise(r => setTimeout(r, m)),
                 loadLibrary: async (p) => {
                    const content = await syscall('readFile', p);
                    if (!content) return false;
                    new Function('OS', 'kernel', content)(OS, { emit: (name, data) => self.postMessage({ type: 'EMIT', name, data }) });
                    return true;
                 }
              };
              if(sdkCode) new Function('OS', 'kernel', sdkCode)(OS, { emit: (n,d) => self.postMessage({ type: 'EMIT', name: n, data: d }) });
              for(const dll of dlls) await OS.loadLibrary(dll);
              try {
                 await new Function('OS', 'kernel', 'return (async () => { ' + code + ' })();')(OS, {});
              } catch(err) { OS.error("Worker Error: " + err.message); OS.terminate(pid); }
           }
           if (type === 'SYSCALL_RES') {
              const h = __callHandlers.get(callId);
              if (h) { h(data); __callHandlers.delete(callId); }
           }
        };
      `], { type: 'application/javascript' });

      const worker = new Worker(URL.createObjectURL(workerBlob));
      (proc as any).worker = worker;

      worker.onmessage = (e) => {
         const { type, name, args, callId, data } = e.data;
         if (type === 'SYSCALL') {
            let res = null;
            if (name === 'print') this.log('INFO', `Proc:${pid}`, args[0]);
            if (name === 'error') this.log('ERROR', `Proc:${pid}`, args[0]);
            if (name === 'terminate') this.terminateProcess(pid);
            if (name === 'readFile') res = this.fsGetNode(args[0])?.content;
            if (name === 'writeFile') this.fsUpdateFileContent(args[0], args[1]);
            if (name === 'listFiles') res = this.fsGetChildren(args[0]).map(n => n.name);
            worker.postMessage({ type: 'SYSCALL_RES', callId, data: res });
         }
         if (type === 'EMIT') this.emit(name, data);
      };

      worker.onerror = (err) => { this.log('ERROR', 'ExecutionEngine', `Worker Error: ${err.message}`); this.terminateProcess(pid); };

      const sdkNode = this.fsGetNode('C:\\ObsidianOS\\SDK\\lib\\obsidian.js');
      worker.postMessage({ type: 'BOOT', data: { pid, name: node.name, code: node.content, sdkCode: sdkNode?.content, dlls: ['C:\\ObsidianOS\\System32\\kernel32.dll'] } });

    } catch (err: any) {
      this.log('ERROR', 'ExecutionEngine', `Spawn failed: ${err.message}`);
      this.terminateProcess(pid);
    }
  }

  // Processes that must never be terminated — killing them triggers BSOD
  private static readonly CRITICAL_PROCESSES: Record<string, { stopCode: string; component: string; technical: string; bugCheck: string }> = {
    'System':        { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'ntoskrnl.obx', technical: 'The System kernel process was terminated.',                                           bugCheck: '0x000000EF' },
    'smss.obx':     { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'smss.obx',     technical: 'Session Manager Subsystem process died.',                                             bugCheck: '0x000000EF' },
    'csrss.obx':    { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'csrss.obx',    technical: 'Client Server Runtime Process died.',                                                 bugCheck: '0x000000EF' },
    'wininit.obx':  { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'wininit.obx',  technical: 'Windows Start-Up Application stopped.',                                              bugCheck: '0x000000EF' },
    'lsass.obx':    { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'lsass.obx',    technical: 'Local Security Authority Process encountered a critical error.',                     bugCheck: '0x000000EF' },
    'services.obx': { stopCode: 'CRITICAL_PROCESS_DIED',       component: 'services.obx', technical: 'Services and Controller App stopped.',                                               bugCheck: '0x000000EF' },
    'dwm.obx':      { stopCode: 'DESKTOP_WINDOW_MANAGER_DIED', component: 'dwm.obx',      technical: 'Desktop Window Manager (DWM) encountered a fatal error and could not be restarted.', bugCheck: '0x000000EF' },
  };

  terminateProcess(pid: number) {
    const proc = this._processes.get(pid);
    if (!proc) return;

    // Remove from scheduler run queues
    this._removeFromRunQueues(pid);

    // Cleanup Worker if it exists
    if ((proc as any).worker) {
       (proc as any).worker.terminate();
       this.log('INFO', 'ExecutionEngine', `Worker for PID:${pid} terminated.`);
    }

    // Cleanup event forwards
    if ((proc as any)._unbinds) {
       (proc as any)._unbinds.forEach((u: any) => u());
    }

    this.freeMemory(proc.memoryUsage);
    this._processes.delete(pid);
    
    // Close associated windows
    for (const win of Array.from(this._windows.values())) {
      if (win.processId === pid) {
        this._windows.delete(win.id);
      }
    }

    // Re-evaluate active window
    const remaining = Array.from(this._windows.values()).filter(w => !w.isMinimized);
    remaining.sort((a, b) => b.zIndex - a.zIndex);
    if (remaining.length > 0) {
      const top = remaining[0];
      this._windows.set(top.id, { ...top, isActive: true });
      this._activeWindowId = top.id;
    } else {
      this._activeWindowId = null;
    }

    // Always emit snapshot so window store stays in sync
    this._emitWindowSnapshot();

    this.log('DEBUG', 'ProcessManager', `Terminated: ${proc.name} [PID:${pid}]`);
    this.emit('process:terminated', pid);

    // Trigger BSOD if a critical process was killed (only when desktop is running)
    if (this._isInitialized && this._bootPhase !== 'BSOD') {
      const critical = Kernel.CRITICAL_PROCESSES[proc.name];
      if (critical) {
        setTimeout(() => this.triggerBSOD({
          stopCode: critical.stopCode,
          technicalInfo: critical.technical,
          failedComponent: critical.component,
          bugCheckCode: critical.bugCheck,
          parameters: ['0x00000000', '0x00000000', '0x00000000', '0x00000000'],
        }), 100);
      }
    }
  }

  suspendProcess(pid: number) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    this._removeFromRunQueues(pid);
    const updated: Process = { ...proc, state: 'BLOCKED', status: 'suspended' };
    this._processes.set(pid, updated);
    this.emit('process:updated', updated);
  }

  resumeProcess(pid: number) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    const updated: Process = { ...proc, state: 'READY', status: 'running' };
    this._processes.set(pid, updated);
    this._addToRunQueue(updated);
    this.emit('process:updated', updated);
  }

  updateProcessCpu(pid: number, cpu: number) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    const updated: Process = { ...proc, cpuUsage: cpu };
    this._processes.set(pid, updated);
    this.emit('process:updated', updated);
  }

  updateProcessMemory(pid: number, memory: number) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    const updated: Process = { ...proc, memoryUsage: memory };
    this._processes.set(pid, updated);
    this.emit('process:updated', updated);
  }

  // ========== Scheduler ==========
  startScheduler() {
    if (this._schedulerInterval) return;
    this._schedulerInterval = setInterval(() => this._schedulerTick(), 100);
    this.log('INFO', 'Scheduler', 'Round-Robin scheduler started');
  }

  stopScheduler() {
    if (this._schedulerInterval) {
      clearInterval(this._schedulerInterval);
      this._schedulerInterval = null;
    }
  }

  private _schedulerTick() {
    const now = Date.now();
    const weights: Record<ProcessPriority, number> = {
      REALTIME: 32, HIGH: 16, ABOVE_NORMAL: 8, NORMAL: 4, BELOW_NORMAL: 2, IDLE: 1,
    };

    const active: Process[] = [];
    let totalWeight = 0;

    for (const priority of Kernel.PRIORITY_ORDER) {
      const q = this._runQueues.get(priority)!;
      for (const pid of q) {
        const proc = this._processes.get(pid);
        if (!proc || proc.state === 'BLOCKED' || proc.state === 'SLEEPING' || proc.state === 'ZOMBIE') continue;
        active.push(proc);
        totalWeight += weights[priority];
      }
    }

    if (active.length === 0) {
      this._resources.cpuUsage = 0;
      this.emit('cpuChange', this._resources);
      return;
    }

    // Base system load: idle system sits around 3-8%, busy system scales up
    // Each process gets a slice of the total system load, not additive CPU
    const baseLoad = Math.min(15, 2 + active.length * 0.4);
    const organicNoise = (Math.random() - 0.5) * 2; // ±1%
    const systemLoad = Math.max(0, Math.min(100, baseLoad + organicNoise));

    for (const proc of active) {
      const share = weights[proc.priority] / totalWeight;
      // Per-process CPU = its share of system load + tiny individual noise
      const procNoise = proc.pid < 10
        ? Math.random() * 0.1   // system processes: very stable
        : Math.random() * 0.5;  // user processes: slight variation
      const rawCpu = systemLoad * share + procNoise;

      // Exponential moving average — smooths out spikes
      const alpha = 0.25;
      const newCpu = parseFloat((alpha * rawCpu + (1 - alpha) * proc.cpuUsage).toFixed(2));

      const quantum = Kernel.QUANTUM_MS[proc.priority];
      const newQuantumUsed = (proc.quantumUsed + 100) % quantum;

      const updated: Process = {
        ...proc,
        state: 'RUNNING',
        status: 'running',
        cpuUsage: newCpu,
        quantumUsed: newQuantumUsed,
        totalCpuTime: proc.totalCpuTime + 100 * share,
        lastScheduled: now,
      };
      this._processes.set(proc.pid, updated);

      // Rotate queue after quantum expires
      if (newQuantumUsed === 0) {
        const q = this._runQueues.get(proc.priority)!;
        const i = q.indexOf(proc.pid);
        if (i !== -1) { q.splice(i, 1); q.push(proc.pid); }
      }

      if (updated.pendingSignals.length > 0) this._deliverSignals(updated.pid);
    }

    // System CPU = weighted average of all process CPUs (not sum)
    let weightedSum = 0;
    for (const proc of active) {
      const p = this._processes.get(proc.pid)!;
      weightedSum += p.cpuUsage * (weights[p.priority] / totalWeight);
    }
    this._resources.cpuUsage = Math.min(100, parseFloat(weightedSum.toFixed(1)));
    this.emit('cpuChange', this._resources);
    this.emit('scheduler:tick', { processes: this.getProcesses(), cpuUsage: this._resources.cpuUsage });
  }

  setPriority(pid: number, priority: ProcessPriority) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    this._removeFromRunQueues(pid);
    const updated: Process = { ...proc, priority, quantum: Kernel.QUANTUM_MS[priority] };
    this._processes.set(pid, updated);
    this._addToRunQueue(updated);
    this.log('INFO', 'Scheduler', `PID:${pid} priority → ${priority}`);
    this.emit('process:updated', updated);
  }

  getProcessPriority(pid: number): ProcessPriority | null {
    return this._processes.get(pid)?.priority ?? null;
  }

  // ========== Signal System ==========

  sendSignal(pid: number, signal: Signal): boolean {
    const proc = this._processes.get(pid);
    if (!proc) return false;
    if (signal === 'SIGKILL') {
      this.log('INFO', 'Signal', `SIGKILL → PID:${pid} (${proc.name})`);
      this._handleSignalDefault(pid, signal);
      return true;
    }
    const updated: Process = { ...proc, pendingSignals: [...proc.pendingSignals, signal] };
    this._processes.set(pid, updated);
    this.log('DEBUG', 'Signal', `${signal} queued for PID:${pid}`);
    this.emit('process:signal', { pid, signal });
    return true;
  }

  installSignalHandler(pid: number, signal: Signal, handler: 'DEFAULT' | 'IGNORE' | 'CUSTOM', customFn?: string) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    this._processes.set(pid, {
      ...proc,
      signalHandlers: { ...proc.signalHandlers, [signal]: { signal, handler, customFn } },
    });
  }

  private _deliverSignals(pid: number) {
    const proc = this._processes.get(pid);
    if (!proc || proc.pendingSignals.length === 0) return;
    const [signal, ...rest] = proc.pendingSignals;
    const handlerDef = proc.signalHandlers[signal];
    this._processes.set(pid, { ...proc, pendingSignals: rest });

    if (handlerDef?.handler === 'IGNORE') return;
    if (handlerDef?.handler === 'CUSTOM') {
      this.emit('process:signal:deliver', { pid, signal, fn: handlerDef.customFn });
      return;
    }
    this._handleSignalDefault(pid, signal);
  }

  private _handleSignalDefault(pid: number, signal: Signal) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    switch (signal) {
      case 'SIGTERM': case 'SIGINT': case 'SIGKILL': case 'SIGABRT':
        this.log('INFO', 'Signal', `PID:${pid} (${proc.name}) terminated by ${signal}`);
        this.terminateProcess(pid);
        break;
      case 'SIGSEGV':
        this.log('ERROR', 'Signal', `PID:${pid} (${proc.name}) — Segmentation Fault`);
        this.emit('process:crash', { pid, signal, message: 'Segmentation fault (core dumped)' });
        this._writeCoreFile(pid, signal);
        this.terminateProcess(pid);
        break;
      case 'SIGFPE':
        this.log('ERROR', 'Signal', `PID:${pid} (${proc.name}) — Arithmetic Exception`);
        this.emit('process:crash', { pid, signal, message: 'Floating point exception' });
        this._writeCoreFile(pid, signal);
        this.terminateProcess(pid);
        break;
      case 'SIGILL':
        this.log('ERROR', 'Signal', `PID:${pid} (${proc.name}) — Illegal Instruction`);
        this.emit('process:crash', { pid, signal, message: 'Illegal instruction' });
        this._writeCoreFile(pid, signal);
        this.terminateProcess(pid);
        break;
      case 'SIGALRM':
        this.emit('process:signal:deliver', { pid, signal });
        break;
      default: break; // SIGCHLD, SIGUSR1, SIGUSR2 — default ignore
    }
  }

  private _writeCoreFile(pid: number, signal: Signal) {
    const proc = this._processes.get(pid);
    if (!proc) return;
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const content = JSON.stringify({ pid, signal, name: proc.name, cpuUsage: proc.cpuUsage, memoryUsage: proc.memoryUsage, totalCpuTime: proc.totalCpuTime, timestamp: Date.now() }, null, 2);
    this.fsCreateFile('C:\\ObsidianOS\\System32\\Minidump', `core_${proc.name}_${pid}_${ts}.dmp`, content, 'dmp');
  }

  // ========== Partition Table ==========

  private _initPartitionTable() {
    const saved = this.regGetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Disk\\PartitionTable');
    if (saved && typeof saved === 'string') {
      try {
        this._partitionTable = JSON.parse(saved);
        const bc = this.regGetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Disk\\BootConfig');
        if (bc && typeof bc === 'string') this._bootConfig = JSON.parse(bc);
        return;
      } catch { /* fall through */ }
    }
    this._partitionTable = this._buildDefaultPartitionTable();
    this._bootConfig     = this._buildDefaultBootConfig();
    this._persistPartitionTable();
  }

  private _buildDefaultPartitionTable(): PartitionTable {
    return {
      scheme: 'GPT',
      diskSizeMB: 256000,
      diskLabel: 'ObsidianOS Disk 0',
      guid: uuidv4(),
      partitions: [
        { index: 0, label: 'EFI System Partition', driveLetter: '', type: 'EFI',      bootable: true,  startLBA: 2048,      sizeMB: 512,    usedMB: 4,     filesystem: '',             guid: uuidv4() },
        { index: 1, label: 'ObsidianOS',           driveLetter: 'C', type: 'NTFS',    bootable: false, startLBA: 1050624,   sizeMB: 204800, usedMB: 42000, filesystem: 'C:',           guid: uuidv4() },
        { index: 2, label: 'Recovery',             driveLetter: '',  type: 'RECOVERY',bootable: false, startLBA: 419432448, sizeMB: 1024,   usedMB: 512,   filesystem: 'C:\\Recovery', guid: uuidv4() },
      ],
      gpt: { headerLBA: 1, backupLBA: 499999999, firstUsableLBA: 34, lastUsableLBA: 499999966 },
    };
  }

  private _buildDefaultBootConfig(): BootConfig {
    return {
      scheme: 'UEFI',
      timeout: 5,
      defaultEntry: 'obsidianos',
      entries: [
        { id: 'obsidianos', label: 'ObsidianOS Professional 24H2',      partition: 'C', kernelPath: 'C:\\ObsidianOS\\System32\\ntoskrnl.obx', cmdline: '/fastdetect /noexecute=OptIn', isDefault: true,  timeout: 5 },
        { id: 'recovery',   label: 'ObsidianOS Recovery Environment',   partition: 'C', kernelPath: 'C:\\Recovery\\winre.obx',                cmdline: '/recovery',                   isDefault: false },
      ],
    };
  }

  private _persistPartitionTable() {
    if (!this._partitionTable) return;
    this.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Disk\\PartitionTable', 'REG_SZ', JSON.stringify(this._partitionTable));
    if (this._bootConfig) this.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Disk\\BootConfig', 'REG_SZ', JSON.stringify(this._bootConfig));
  }

  getPartitionTable(): PartitionTable | null { return this._partitionTable; }
  getBootConfig(): BootConfig | null { return this._bootConfig; }

  getPartition(driveLetter: string): PartitionEntry | null {
    return this._partitionTable?.partitions.find(p => p.driveLetter === driveLetter) ?? null;
  }

  updatePartitionUsage(driveLetter: string, usedMB: number) {
    if (!this._partitionTable) return;
    const p = this._partitionTable.partitions.find(p => p.driveLetter === driveLetter);
    if (p) { p.usedMB = usedMB; this._persistPartitionTable(); this.emit('disk:partitionUpdate', this._partitionTable); }
  }

  addBootEntry(entry: BootEntry) {
    if (!this._bootConfig) return;
    this._bootConfig.entries.push(entry);
    this._persistPartitionTable();
  }

  setDefaultBootEntry(id: string) {
    if (!this._bootConfig) return;
    this._bootConfig.defaultEntry = id;
    this._bootConfig.entries.forEach(e => { e.isDefault = e.id === id; });
    this._persistPartitionTable();
  }

  getProcess(pid: number): Process | undefined {
    return this._processes.get(pid);
  }

  getProcessByWindowId(windowId: string): Process | undefined {
    return Array.from(this._processes.values()).find(p => p.windowId === windowId);
  }

  getProcesses(): Process[] {
    return Array.from(this._processes.values());
  }

  getRunningProcesses(): Process[] {
    return this.getProcesses().filter(p => p.status === 'running');
  }

  // ========== File System Management ==========

  private _persistFileSystem() {
    // When OPFS driver is active, writes go directly to disk (write-through above).
    // localStorage is only used as fallback when OPFS is not available.
    if (this._diskDriver) {
      this.emit('fs:snapshot', Object.fromEntries(this._filesystem));
      return;
    }
    if (typeof window === 'undefined') return;
    const obj = Object.fromEntries(this._filesystem);
    localStorage.setItem('obsidianos-filesystem-v2', JSON.stringify(obj));
    this.emit('fs:snapshot', obj);
  }

  fsGetNode(path: string): FileSystemNode | undefined {
    return this._filesystem.get(path);
  }

  // Async version — loads content from OPFS if not in cache
  async fsGetNodeAsync(path: string): Promise<FileSystemNode | undefined> {
    const cached = this._filesystem.get(path);
    if (!cached) return undefined;
    // If content is missing and we have a disk driver, load it
    if (cached.type === 'file' && cached.content === undefined && this._diskDriver) {
      const content = await this._diskDriver.readContent(path);
      if (content !== null) {
        cached.content = content;
        this._filesystem.set(path, cached);
      }
    }
    return cached;
  }

  fsGetChildren(path: string): FileSystemNode[] {
    return Array.from(this._filesystem.values()).filter(n => n.parentPath === path);
  }

  fsCreateFile(parentPath: string, name: string, content: string = '', extension: string = 'txt') {
    const path = `${parentPath}\\${name}`;
    const node = makeFile(path, name, parentPath, extension, content);
    this._filesystem.set(path, node);
    // Write-through to OPFS
    if (this._diskDriver) {
      this._diskDriver.writeContent(path, content).then(() => this._diskDriver!.writeMeta(node));
    }
    this._persistFileSystem();
  }

  fsCreateDirectory(parentPath: string, name: string) {
    const path = `${parentPath}\\${name}`;
    if (this._filesystem.has(path)) return; // Já existe
    const node = makeDir(path, name, parentPath);
    this._filesystem.set(path, node);
    if (this._diskDriver) {
      this._diskDriver.createDirectory(path).then(() => this._diskDriver!.writeMeta(node));
    }
    this._persistFileSystem();
  }

  // Cria a estrutura de pastas para um novo usuário
  sysCreateUserHome(username: string) {
    const root = `C:\\Users\\${username}`;
    this.fsCreateDirectory('C:\\Users', username);
    this.fsCreateDirectory(root, 'Desktop');
    this.fsCreateDirectory(root, 'Documents');
    this.fsCreateDirectory(root, 'Downloads');
    this.fsCreateDirectory(root, 'Pictures');
    this.fsCreateDirectory(root, 'Music');
    this.fsCreateDirectory(root, 'Videos');
    this.fsCreateDirectory(root, 'AppData');
    this.fsCreateDirectory(`${root}\\AppData`, 'Local');
    this.fsCreateDirectory(`${root}\\AppData`, 'Roaming');
    
    this.log('INFO', 'Kernel', `Estrutura de diretórios criada para o usuário: ${username}`);
  }

  fsDeleteNode(path: string) {
    for (const key of Array.from(this._filesystem.keys())) {
      if (key === path || key.startsWith(path + '\\')) {
        this._filesystem.delete(key);
      }
    }
    if (this._diskDriver) {
      this._diskDriver.deleteNode(path);
    }
    this._persistFileSystem();
  }

  fsRenameNode(path: string, newName: string) {
    const node = this._filesystem.get(path);
    if (!node) return;
    
    const parentPath = node.parentPath;
    const newPath = `${parentPath}\\${newName}`;
    
    for (const [key, n] of Array.from(this._filesystem.entries())) {
      if (key === path) {
        n.id = newPath;
        n.name = newName;
        n.path = newPath;
        n.modifiedAt = Date.now();
        this._filesystem.set(newPath, n);
        this._filesystem.delete(path);
      } else if (key.startsWith(path + '\\')) {
        const suffix = key.substring(path.length);
        const updatedPath = newPath + suffix;
        n.id = updatedPath;
        n.path = updatedPath;
        n.parentPath = n.parentPath === path ? newPath : n.parentPath.replace(path, newPath);
        this._filesystem.set(updatedPath, n);
        this._filesystem.delete(key);
      }
    }
    if (this._diskDriver) {
      this._diskDriver.renameNode(path, newName);
    }
    this._persistFileSystem();
  }

  fsMoveNode(fromPath: string, toPath: string) {
    const node = this._filesystem.get(fromPath);
    if (!node) return;
    const newPath = `${toPath}\\${node.name}`;
    
    node.id = newPath;
    node.path = newPath;
    node.parentPath = toPath;
    node.modifiedAt = Date.now();
    
    this._filesystem.set(newPath, node);
    this._filesystem.delete(fromPath);
    if (this._diskDriver) {
      this._diskDriver.deleteNode(fromPath).then(() => {
        this._diskDriver!.writeContent(newPath, node.content || '');
        this._diskDriver!.writeMeta(node);
      });
    }
    this._persistFileSystem();
  }

  fsUpdateFileContent(path: string, content: string) {
    const node = this._filesystem.get(path);
    if (!node || node.type !== 'file') return;
    
    node.content = content;
    node.size = content.length;
    node.modifiedAt = Date.now();
    
    this._filesystem.set(path, node);
    if (this._diskDriver) {
      this._diskDriver.writeContent(path, content).then(() => this._diskDriver!.writeMeta(node));
    }
    this._persistFileSystem();
  }

  fsRepairSystemFiles() {
    let repaired = false;
    for (const [key, defaultNode] of Object.entries(defaultNodes)) {
      const currentNode = this._filesystem.get(key);
      if (!currentNode || (defaultNode.attributes.isSystem && defaultNode.content !== currentNode.content)) {
        this._filesystem.set(key, { ...defaultNode });
        if (this._diskDriver) {
          this._diskDriver.writeMeta({ ...defaultNode });
          if (defaultNode.type === 'file') this._diskDriver.writeContent(key, defaultNode.content || '');
        }
        repaired = true;
      }
    }
    if (repaired) this._persistFileSystem();
  }

  fsDeepReformat() {
    this.log('WARN', 'FileSystem', 'CRITICAL: Initiating Deep Reformat. All files will be reset.');
    this._filesystem.clear();
    for (const [key, defaultNode] of Object.entries(defaultNodes)) {
      this._filesystem.set(key, { ...defaultNode });
    }
    // Re-format OPFS disk too
    if (this._diskDriver) {
      this._diskDriver.formatDisk({ ...defaultNodes }).then(() => {
        this.log('INFO', 'FileSystem', 'OPFS disk reformatted.');
      });
    }
    this._persistFileSystem();
    this.emit('filesystem:snapshot', this.fsGetSnapshot());
    this.log('INFO', 'FileSystem', 'Deep Reformat complete.');
  }

  fsGetSnapshot(): Record<string, FileSystemNode> {
    return Object.fromEntries(this._filesystem);
  }

  fsExists(path: string): boolean {
    return this._filesystem.has(path);
  }

  // ========== Registry Management ==========

  private _persistRegistry() {
    if (typeof window === 'undefined') return;
    localStorage.setItem('obsidianos-registry-v2', JSON.stringify(this._registry));
    this.emit('registry:snapshot', this._registry);
  }

  regGetValue(path: string): RegistryValue | undefined {
    const parts = path.split('\\');
    const valueName = parts.pop();
    if (!valueName) return undefined;
    const keyPath = parts.join('\\');
    return this._registry[keyPath]?.[valueName]?.value;
  }

  regSetValue(path: string, type: RegistryEntry['type'], value: RegistryValue) {
    const parts = path.split('\\');
    const valueName = parts.pop();
    if (!valueName) return;
    const keyPath = parts.join('\\');
    
    if (!this._registry[keyPath]) {
      this._registry[keyPath] = {};
    }
    
    this._registry[keyPath][valueName] = { type, value };
    this._persistRegistry();
  }

  regDeleteValue(path: string) {
    const parts = path.split('\\');
    const valueName = parts.pop();
    if (!valueName) return;
    const keyPath = parts.join('\\');
    
    if (this._registry[keyPath] && this._registry[keyPath][valueName]) {
      delete this._registry[keyPath][valueName];
      this._persistRegistry();
    }
  }

  regGetSubKeys(path: string): string[] {
    return Object.keys(this._registry).filter(k => k.startsWith(path + '\\') && k !== path);
  }

  regKeyExists(path: string): boolean {
    return path in this._registry;
  }

  regGetSnapshot(): Record<string, Record<string, RegistryEntry>> {
    return this._registry; // Pass by ref is fine for React read-only state here or clone
  }

  // ========== Window Management ==========

  private _emitWindowSnapshot() {
    this.emit('window:snapshot', {
      windows: this.getWindows(),
      activeWindowId: this._activeWindowId,
      topZIndex: this._topZIndex,
    });
  }

  openWindow(config: {
    title: string; icon: string; appId: string;
    width?: number; height?: number; minWidth?: number; minHeight?: number;
    isResizable?: boolean; processId: number;
    params?: any;
    hasFrame?: boolean;
    isSystem?: boolean;
    zIndex?: number;
  }): string {
    const id = uuidv4();
    const sw = typeof window !== 'undefined' ? window.innerWidth : 1920;
    const sh = typeof window !== 'undefined' ? window.innerHeight - 48 : 1032;
    const w = config.width || 800;
    const h = config.height || 600;
    
    const hasFrame = config.hasFrame !== false;
    const isSystem = config.isSystem === true;

    // Deactivate current active window only if new window is NOT a system window
    if (!isSystem) {
      for (const [wid, win] of this._windows.entries()) {
        if (win.isActive) this._windows.set(wid, { ...win, isActive: false });
      }
    }

    const nw: WindowState = {
      id, title: config.title, icon: config.icon, appId: config.appId,
      x: isSystem ? (config.params?.x ?? 0) : Math.max(40, (sw - w) / 2 + Math.random() * 60 - 30),
      y: isSystem ? (config.params?.y ?? 0) : Math.max(20, (sh - h) / 2 + Math.random() * 60 - 30),
      width: w, height: h,
      minWidth: config.minWidth ?? (isSystem ? 0 : 400), minHeight: config.minHeight ?? (isSystem ? 0 : 300),
      isMinimized: false, isMaximized: false, isActive: !isSystem,
      zIndex: config.zIndex ?? (isSystem ? 1000 : ++this._topZIndex), opacity: 1,
      isResizable: !isSystem && config.isResizable !== false, 
      isDraggable: !isSystem,
      isClosable: !isSystem, 
      isMinimizable: !isSystem, 
      isMaximizable: !isSystem,
      processId: config.processId,
      params: config.params,
      hasFrame,
      isSystem,
    };
    this._windows.set(id, nw);
    this._activeWindowId = id;

    // Link the process to this window
    const proc = this._processes.get(config.processId);
    if (proc) {
      this._processes.set(config.processId, { ...proc, windowId: id });
      this.emit('process:updated', { ...proc, windowId: id });
    }

    this._emitWindowSnapshot();
    return id;
  }

  closeWindow(id: string) {
    const win = this._windows.get(id);
    if (!win) return;
    // terminateProcess handles window removal + snapshot emission
    if (win.processId) {
      this.terminateProcess(win.processId);
    } else {
      this._windows.delete(id);
      const top = Array.from(this._windows.values())
        .filter(w => !w.isMinimized).sort((a, b) => b.zIndex - a.zIndex)[0];
      this._activeWindowId = top ? top.id : null;
      if (top) this._windows.set(top.id, { ...top, isActive: true });
      this._emitWindowSnapshot();
    }
  }

  minimizeWindow(id: string) {
    const win = this._windows.get(id);
    if (!win) return;
    this._windows.set(id, { ...win, isMinimized: true, isActive: false });
    const top = Array.from(this._windows.values())
      .filter(w => !w.isMinimized).sort((a, b) => b.zIndex - a.zIndex)[0];
    if (top) {
      this._windows.set(top.id, { ...top, isActive: true });
      this._activeWindowId = top.id;
    } else {
      this._activeWindowId = null;
    }
    this._emitWindowSnapshot();
  }

  maximizeWindow(id: string) {
    const win = this._windows.get(id);
    if (!win) return;
    const sw = typeof window !== 'undefined' ? window.innerWidth : 1920;
    const sh = typeof window !== 'undefined' ? window.innerHeight - 48 : 1032;
    const updated: WindowState = {
      ...win, isMaximized: true,
      prevBounds: { x: win.x, y: win.y, width: win.width, height: win.height },
      x: 0, y: 0, width: sw, height: sh,
    };
    this._windows.set(id, updated);
    this.emit('window:updated', updated);
  }

  restoreWindow(id: string) {
    const win = this._windows.get(id);
    if (!win) return;
    if (win.isMinimized) {
      this._windows.set(id, { ...win, isMinimized: false, isActive: true, zIndex: ++this._topZIndex });
      this._activeWindowId = id;
      this._emitWindowSnapshot();
    } else if (win.isMaximized && win.prevBounds) {
      const updated: WindowState = {
        ...win, isMaximized: false,
        x: win.prevBounds.x, y: win.prevBounds.y,
        width: win.prevBounds.width, height: win.prevBounds.height,
      };
      this._windows.set(id, updated);
      this._activeWindowId = id;
      this._emitWindowSnapshot();
    }
  }

  focusWindow(id: string) {
    const target = this._windows.get(id);
    // System windows (taskbar, desktop) should never steal focus
    if (target?.isSystem) return;
    const newZ = ++this._topZIndex;
    this._activeWindowId = id;
    for (const [wid, win] of this._windows.entries()) {
      if (win.isSystem) continue; // never touch system windows
      const t = wid === id;
      this._windows.set(wid, { ...win, isActive: t, zIndex: t ? newZ : win.zIndex, isMinimized: t ? false : win.isMinimized });
    }
    this._emitWindowSnapshot();
  }

  moveWindow(id: string, x: number, y: number) {
    const win = this._windows.get(id);
    if (!win) return;
    const updated = { ...win, x, y, isMaximized: false };
    this._windows.set(id, updated);
    this.emit('window:updated', updated);
  }

  resizeWindow(id: string, width: number, height: number) {
    const win = this._windows.get(id);
    if (!win) return;
    const updated: WindowState = { ...win, width: Math.max(win.minWidth, width), height: Math.max(win.minHeight, height) };
    this._windows.set(id, updated);
    this.emit('window:updated', updated);
  }

  updateWindowTitle(id: string, title: string) {
    const win = this._windows.get(id);
    if (!win) return;
    const updated = { ...win, title };
    this._windows.set(id, updated);
    this.emit('window:updated', updated);
  }

  toggleMaximize(id: string) {
    const win = this._windows.get(id);
    if (!win) return;
    if (win.isMaximized) this.restoreWindow(id); else this.maximizeWindow(id);
  }

  getWindow(id: string): WindowState | undefined { return this._windows.get(id); }
  getWindows(): WindowState[] { return Array.from(this._windows.values()); }
  getActiveWindow(): WindowState | undefined { return this._activeWindowId ? this._windows.get(this._activeWindowId) : undefined; }
  getVisibleWindows(): WindowState[] { return this.getWindows().filter(w => !w.isMinimized); }

  // ========== Getters ==========
  get logs() { return [...this._logs]; }
  get bootLog() { return [...this._bootLog]; }
  get isInitialized() { return this._isInitialized; }
  set isInitialized(v: boolean) { this._isInitialized = v; }
  get topZIndex() { return this._topZIndex; }
  get activeWindowId() { return this._activeWindowId; }

  // ========== System Calls ==========
  syscall(call: string, ...args: any[]): any {
    this.log('DEBUG', 'Syscall', `${call}(${args.map(a => JSON.stringify(a)).join(', ')})`);
    this.emit('syscall', call, args);
    return null;
  }

  // ========== Reset ==========
  reset() {
    this._isBooting = false;
    this._isBootFinished = false;
    this._bootPhase = 'OFF';
    this._logs = [];
    this._drivers.clear();
    this._services.clear();
    this._bsodInfo = null;
    this._bootLog = [];
    this._resources.usedMemory = 0;
    this._resources.cpuUsage = 0;
    this._resources.uptime = 0;
    this._isInitialized = false;
    this._shellLoaded = false;
    this._diskDriver = null;
    // Reset lists
    this._processes.clear();
    this._windows.clear();
    this._nextPid = 100;
    this._topZIndex = 100;
    this._activeWindowId = null;
    
    this._initSystemState();
    this._initFileSystem();
    this._initRegistry();
    this._initSystemProcesses();
    if (this._uptimeInterval) clearInterval(this._uptimeInterval);
    this.emit('reset'); // store mirrors ouvem e sincronizam
  }
}

// Export singleton
export const kernel = Kernel.getInstance();
if (typeof window !== 'undefined') {
  (window as any).kernel = kernel;
}
export default kernel;
