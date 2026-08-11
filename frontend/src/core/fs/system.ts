import { now } from './helpers';

export const systemExes: [string, string, string, string, string?][] = [
  ['C:\\ObsidianOS\\System32\\ntoskrnl.obx', 'ntoskrnl.obx', 'C:\\ObsidianOS\\System32', 'ObsidianOS NT Kernel'],
  ['C:\\ObsidianOS\\System32\\csrss.obx', 'csrss.obx', 'C:\\ObsidianOS\\System32', 'Client/Server Runtime Subsystem'],
  ['C:\\ObsidianOS\\System32\\smss.obx', 'smss.obx', 'C:\\ObsidianOS\\System32', 'Session Manager Subsystem'],
  [
    'C:\\ObsidianOS\\System32\\obslogon.obx', 
    'obslogon.obx', 
    'C:\\ObsidianOS\\System32', 
    'Obsidian Logon Application',
    `
async function main() {
    OS.print("ObsLogon: Iniciando subsistema de segurança...");
    let setupRun;
    try {
        setupRun = OS.Registry.GetValue('HKEY_LOCAL_MACHINE\\\\SYSTEM\\\\Setup', 'SetupInProgress');
        OS.print("ObsLogon: Registro lido. SetupInProgress = " + setupRun);
    } catch(e) {
        OS.print("ObsLogon: Falha ao ler registro de setup. Assumindo WINLOGON.");
        setupRun = 0;
    }
    if (setupRun === 1) {
        OS.print("ObsLogon: OOBE detectado. Iniciando Setup Wizard...");
        OS.Kernel.SetBootPhase('OOBE');
    } else {
        OS.print("ObsLogon: Sistema configurado. Aguardando autenticação...");
        OS.Kernel.SetBootPhase('WINLOGON');
    }
    while (true) {
        try {
            const auth = OS.User.IsAuthenticated();
            if (auth) {
                OS.print("ObsLogon: Usuário autenticado. Carregando Shell...");
                OS.Kernel.SetBootPhase('DESKTOP_READY');
                OS.Process.Create('explorer.obx', 'ObsidianOS Shell', 'C:\\\\ObsidianOS\\\\System32\\\\explorer.obx');
                break; 
            }
        } catch(e) {
            OS.print("ObsLogon: Erro no loop de monitoramento: " + e.message);
        }
        await OS.Utils.Sleep(800);
    }
}
main().catch(err => {
    OS.print("CRITICAL_LOGON_FAILURE: " + err);
    while(true) { }
});
    `.trim()
  ],
  ['C:\\ObsidianOS\\System32\\services.obx', 'services.obx', 'C:\\ObsidianOS\\System32', 'Services and Controller App'],
  ['C:\\ObsidianOS\\System32\\lsass.obx', 'lsass.obx', 'C:\\ObsidianOS\\System32', 'Local Security Authority Process'],
  ['C:\\ObsidianOS\\System32\\svchost.obx', 'svchost.obx', 'C:\\ObsidianOS\\System32', 'Host Process for Services'],
  ['C:\\ObsidianOS\\System32\\dwm.obx', 'dwm.obx', 'C:\\ObsidianOS\\System32', 'Desktop Window Manager'],
  ['C:\\ObsidianOS\\System32\\explorer.obx', 'explorer.obx', 'C:\\ObsidianOS\\System32', 'ObsidianOS Shell'],
  ['C:\\ObsidianOS\\System32\\conhost.obx', 'conhost.obx', 'C:\\ObsidianOS\\System32', 'Console Window Host'],
  ['C:\\ObsidianOS\\System32\\SearchHost.obx', 'SearchHost.obx', 'C:\\ObsidianOS\\System32', 'Search Host Process'],
  ['C:\\ObsidianOS\\System32\\RuntimeBroker.obx', 'RuntimeBroker.obx', 'C:\\ObsidianOS\\System32', 'Runtime Broker'],
  ['C:\\ObsidianOS\\System32\\spoolsv.obx', 'spoolsv.obx', 'C:\\ObsidianOS\\System32', 'Print Spooler Service'],
  ['C:\\ObsidianOS\\System32\\wininit.obx', 'wininit.obx', 'C:\\ObsidianOS\\System32', 'ObsidianOS Start-Up Application'],
  ['C:\\ObsidianOS\\System32\\fontdrvhost.obx', 'fontdrvhost.obx', 'C:\\ObsidianOS\\System32', 'User-mode Font Driver Host'],
  ['C:\\ObsidianOS\\System32\\sihost.obx', 'sihost.obx', 'C:\\ObsidianOS\\System32', 'Shell Infrastructure Host'],
  ['C:\\ObsidianOS\\System32\\taskhostw.obx', 'taskhostw.obx', 'C:\\ObsidianOS\\System32', 'Task Host Window'],
  ['C:\\ObsidianOS\\System32\\ctfmon.obx', 'ctfmon.obx', 'C:\\ObsidianOS\\System32', 'CTF Loader'],
  ['C:\\ObsidianOS\\System32\\user32.dll', 'user32.dll', 'C:\\ObsidianOS\\System32', 'Multi-User ObsidianOS USER API Client DLL'],
  ['C:\\ObsidianOS\\System32\\gdi32.dll', 'gdi32.dll', 'C:\\ObsidianOS\\System32', 'GDI Client DLL'],
  ['C:\\ObsidianOS\\System32\\ntdll.dll', 'ntdll.dll', 'C:\\ObsidianOS\\System32', 'NT Layer DLL'],
  ['C:\\ObsidianOS\\System32\\advapi32.dll', 'advapi32.dll', 'C:\\ObsidianOS\\System32', 'Advanced API DLL'],
  ['C:\\ObsidianOS\\System32\\shell32.dll', 'shell32.dll', 'C:\\ObsidianOS\\System32', 'ObsidianOS Shell Common DLL'],
  ['C:\\ObsidianOS\\System32\\ole32.dll', 'ole32.dll', 'C:\\ObsidianOS\\System32', 'OLE32 Component Object Model'],
  ['C:\\ObsidianOS\\System32\\msvcrt.dll', 'msvcrt.dll', 'C:\\ObsidianOS\\System32', 'C Runtime Library'],
  ['C:\\ObsidianOS\\System32\\combase.dll', 'combase.dll', 'C:\\ObsidianOS\\System32', 'COM Base Library'],
  ['C:\\ObsidianOS\\System32\\rpcrt4.dll', 'rpcrt4.dll', 'C:\\ObsidianOS\\System32', 'Remote Procedure Call Runtime'],
  ['C:\\ObsidianOS\\System32\\sechost.dll', 'sechost.dll', 'C:\\ObsidianOS\\System32', 'Security Host Library'],
  ['C:\\ObsidianOS\\System32\\bcryptprimitives.dll', 'bcryptprimitives.dll', 'C:\\ObsidianOS\\System32', 'Cryptographic Primitives Library'],
];

export const dllModules: [string, string, string, string][] = [
  [
    'C:\\ObsidianOS\\System32\\hal.dll',
    'hal.dll',
    'C:\\ObsidianOS\\System32',
    `
OS.HAL = {
  getCpuInfo: function() {
    var res = OS.getResources();
    return {
      cores: res.cpuCores,
      usage: res.cpuUsage,
      architecture: 'x86_64',
      vendor: 'ObsidianCorp',
      model: 'Virtual CPU @ 3.20GHz',
      features: ['SSE4.2', 'AVX2', 'AES-NI', 'RDRAND']
    };
  },
  getMemoryMap: function() {
    var res = OS.getResources();
    return {
      totalPhysical: res.totalMemory,
      usedPhysical: res.usedMemory,
      freePhysical: res.totalMemory - res.usedMemory,
      pageSize: 4096,
      addressWidth: 48
    };
  },
  getDiskInfo: function() {
    var res = OS.getResources();
    return {
      totalDisk: res.totalDisk,
      usedDisk: res.usedDisk,
      freeDisk: res.totalDisk - res.usedDisk,
      filesystem: 'NTFS',
      label: 'ObsidianOS',
      driveLetter: 'C'
    };
  },
  getNetworkInfo: function() {
    var res = OS.getResources();
    return {
      connected: res.networkUp,
      adapter: 'ObsidianNet Virtual Adapter',
      mac: 'OB:5I:D1:AN:0S:NT',
      speed: '1 Gbps',
      type: 'Ethernet'
    };
  },
  raiseInterrupt: function(irq, description) {
    OS.addBootLog('HAL: IRQ ' + irq + ' -> ' + description);
    return { irq: irq, handled: true, timestamp: OS.getTimestamp() };
  },
  getPowerState: function() {
    return {
      state: 'S0',
      batteryLevel: 85,
      acConnected: true,
      sleepStates: ['S1', 'S3', 'S4', 'S5']
    };
  },
  getSystemTime: function() {
    var ts = OS.getTimestamp();
    return {
      timestamp: ts,
      iso: new Date(ts).toISOString(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      uptime: OS.getResources().uptime
    };
  },
  queryAcpi: function(table) {
    var tables = { DSDT: 'Differentiated System Description Table', FADT: 'Fixed ACPI Description Table', MADT: 'Multiple APIC Description Table', SSDT: 'Secondary System Description Table' };
    return { table: table, description: tables[table] || 'Unknown ACPI Table', status: 'present' };
  }
};
`.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\kernel32.dll',
    'kernel32.dll',
    'C:\\ObsidianOS\\System32',
    `
OS.Kernel32 = {
  GetCurrentProcessId: function() {
    return OS.pid;
  },
  CreateProcess: function(name, title, icon) {
    return OS.createProcess(name, title, icon || '⚙️');
  },
  TerminateProcess: function(pid, exitCode) {
    OS.terminate(exitCode || 0);
    return true;
  },
  GetCommandLine: function() {
    return OS.args.join(' ');
  },
  VirtualAlloc: function(size, name) {
    return OS.allocateMemory(size, name || 'VirtualAlloc');
  },
  GlobalMemoryStatus: function() {
    var mem = OS.getResources();
    return {
      totalPhys: mem.totalMemory,
      availPhys: mem.totalMemory - mem.usedMemory,
      usedPhys: mem.usedMemory,
      loadPercent: Math.round((mem.usedMemory / mem.totalMemory) * 100)
    };
  },
  ReadFile: function(path) {
    return OS.readFile(path);
  },
  WriteFile: function(path, content) {
    return OS.writeFile(path, content);
  },
  FindFirstFile: function(path) {
    var files = OS.listFiles(path);
    return files.length > 0 ? { found: true, name: files[0], index: 0, all: files } : { found: false };
  },
  FindNextFile: function(handle) {
    if (!handle || !handle.all) return { found: false };
    handle.index++;
    return handle.index < handle.all.length
      ? { found: true, name: handle.all[handle.index], index: handle.index, all: handle.all }
      : { found: false };
  },
  GetFileAttributes: function(path) {
    var content = OS.readFile(path);
    return content !== undefined
      ? { exists: true, size: content.length, readonly: false, system: path.includes('System32') }
      : { exists: false };
  },
  GetEnvironmentVariable: function(name) {
    var env = { OS: 'ObsidianOS_NT', COMPUTERNAME: 'OBSIDIAN-PC', USERNAME: OS.getEnv('USER'), SYSTEMROOT: 'C:\\\\ObsidianOS', TEMP: 'C:\\\\ObsidianOS\\\\Temp', PATH: 'C:\\\\ObsidianOS\\\\System32;C:\\\\ObsidianOS\\\\SDK\\\\examples', PROCESSOR_ARCHITECTURE: 'AMD64', NUMBER_OF_PROCESSORS: String(OS.getResources().cpuCores) };
    return env[name] || '';
  },
  SetEnvironmentVariable: function(name, value) {
    OS.print('[Kernel32] SetEnvironmentVariable: ' + name + '=' + value);
    return true;
  },
  GetSystemInfo: function() {
    var res = OS.getResources();
    return {
      processorType: 'PROCESSOR_AMD64',
      numberOfProcessors: res.cpuCores,
      pageSize: 4096,
      processorLevel: 6,
      processorRevision: 0x0A00,
      allocationGranularity: 65536
    };
  },
  Sleep: function(ms) {
    return OS.wait(ms);
  },
  GetTickCount: function() {
    return OS.getResources().uptime * 1000;
  },
  QueryPerformanceCounter: function() {
    return OS.getTimestamp();
  },
  GetLastError: function() { return 0; },
  SetLastError: function(code) { OS.error('[Kernel32] SetLastError: ' + code); },
  FormatMessage: function(code) {
    var messages = { 0: 'The operation completed successfully.', 2: 'The system cannot find the file specified.', 5: 'Access is denied.', 8: 'Not enough memory resources.', 32: 'The process cannot access the file.', 87: 'The parameter is incorrect.' };
    return messages[code] || 'Unknown error code: ' + code;
  }
};
`.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\gdi32.dll',
    'gdi32.dll',
    'C:\\ObsidianOS\\System32',
    `
OS.GDI32 = {
  internalQueue: [],
  __queue: function(op, args) {
     this.internalQueue.push(Object.assign({ op: op }, args));
  },
  Flush: function() {
     if (this.internalQueue.length > 0) {
        kernel.emit('gdi:draw', { pid: OS.pid, commands: this.internalQueue });
        this.internalQueue = [];
     }
  },
  SetFillStyle: function(color) { this.__queue('fillStyle', { color: color }); },
  FillRect: function(x, y, w, h) { this.__queue('fillRect', { x: x, y: y, w: w, h: h }); },
  ClearRect: function(x, y, w, h) { this.__queue('clearRect', { x: x, y: y, w: w, h: h }); },
  SetFont: function(font) { this.__queue('font', { font: font }); },
  DrawText: function(text, x, y) { this.__queue('fillText', { text: String(text), x: x, y: y }); }
};
`.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\user32.dll',
    'user32.dll',
    'C:\\ObsidianOS\\System32',
    `
OS.User32 = {
  elements: [],
  listeners: {},
  SetRenderMode: function(mode) {
    kernel.emit('user32:set_mode', { pid: OS.pid, mode: mode });
  },
  __renderDOM: function() {
    var html = this.elements.map(function(el) {
       var style = "position:absolute;left:" + el.x + "px;top:" + el.y + "px;";
       if (el.width) style += "width:" + el.width + "px;";
       if (el.height) style += "height:" + el.height + "px;";
       if (el.type === 'button') {
          return "<button id='" + el.id + "' style='" + style + "'>" + el.text + "</button>";
       } else if (el.type === 'input') {
          return "<input id='" + el.id + "' style='" + style + "' value='" + (el.text || '') + "' />";
       } else if (el.type === 'label') {
          return "<div id='" + el.id + "' style='" + style + "'>" + el.text + "</div>";
       }
       return "";
    }).join("");
    kernel.emit('user32:dom_update', { pid: OS.pid, html: html });
  },
  CreateElement: function(type, id, x, y, width, height, text) {
    var existing = this.elements.findIndex(function(e) { return e.id === id; });
    var obj = { type: type, id: id, x: x, y: y, width: width, height: height, text: text };
    if (existing >= 0) this.elements[existing] = obj;
    else this.elements.push(obj);
    this.__renderDOM();
  },
  UpdateElementText: function(id, text) {
    var existing = this.elements.find(function(e) { return e.id === id; });
    if (existing) {
       existing.text = text;
       this.__renderDOM();
    }
  },
  CreateButton: function(id, text, x, y, width, height) { this.CreateElement('button', id, x, y, width, height, text); },
  CreateLabel: function(id, text, x, y, width, height) { this.CreateElement('label', id, x, y, width, height, text); },
  CreateInput: function(id, text, x, y, width, height) { this.CreateElement('input', id, x, y, width, height, text); },
  OnMessage: function(id, eventType, callback) {
    if (!this.listeners[id]) this.listeners[id] = {};
    this.listeners[id][eventType.toLowerCase()] = callback;
  },
  MessageLoop: async function() {
    this.SetRenderMode('dom');
    this.__renderDOM();
    kernel.on('user32:dom_event', function(data) {
       if (data.pid === OS.pid) {
          if (OS.User32.listeners[data.elementId] && OS.User32.listeners[data.elementId][data.event]) {
             OS.User32.listeners[data.elementId][data.event](data);
          }
       }
    });
    while (true) { await OS.wait(100); }
  }
};
`.trim()
  ]
];

export const sysConfigFiles: [string, string, string, string, string][] = [
  ['C:\\ObsidianOS\\System32\\win.ini', 'win.ini', 'C:\\ObsidianOS\\System32', 'ini', '; ObsidianOS System Configuration\n[ObsidianOS]\nload=\nrun=\n[Desktop]\nWallpaper=default\nTileWallpaper=0'],
  ['C:\\ObsidianOS\\System32\\boot.ini', 'boot.ini', 'C:\\ObsidianOS\\System32', 'ini', '[boot loader]\ntimeout=30\ndefault=multi(0)disk(0)rdisk(0)partition(1)\\OBSIDIANOS\n[operating systems]\nmulti(0)disk(0)rdisk(0)partition(1)\\OBSIDIANOS="ObsidianOS Professional" /fastdetect'],
  ['C:\\ObsidianOS\\System32\\config\\SYSTEM', 'SYSTEM', 'C:\\ObsidianOS\\System32\\config', 'dat', '[Registry Hive]\nType=SYSTEM\nLastWritten=' + now],
  ['C:\\ObsidianOS\\System32\\config\\SOFTWARE', 'SOFTWARE', 'C:\\ObsidianOS\\System32\\config', 'dat', '[Registry Hive]\nType=SOFTWARE\nLastWritten=' + now],
  ['C:\\ObsidianOS\\System32\\config\\SAM', 'SAM', 'C:\\ObsidianOS\\System32\\config', 'dat', '[Registry Hive]\nType=SAM\nSecurity=ENCRYPTED\nLastWritten=' + now],
  ['C:\\ObsidianOS\\System32\\config\\SECURITY', 'SECURITY', 'C:\\ObsidianOS\\System32\\config', 'dat', '[Registry Hive]\nType=SECURITY\nLastWritten=' + now],
];
