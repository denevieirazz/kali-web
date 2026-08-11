export const binaryExes: [string, string, string, string][] = [
  [
    'C:\\ObsidianOS\\System32\\ping.obx', 
    'ping.obx', 
    'C:\\ObsidianOS\\System32', 
    `
      const target = OS.args[0] || '127.0.0.1';
      OS.print(\`Pinging \${target} with 32 bytes of data:\`);
      for(let i=0; i<4; i++) {
        await OS.wait(1000);
        const res = OS.ping();
        OS.print(\`Reply from \${target}: bytes=32 time=\${res.latency}ms TTL=128\`);
      }
      OS.terminate(0);
    `
  ],
  [
    'C:\\ObsidianOS\\System32\\ls.obx', 
    'ls.obx', 
    'C:\\ObsidianOS\\System32', 
    `
      const path = OS.args[0] || '.';
      const files = OS.listFiles(path);
      OS.print(\`Directory of \${path}:\`);
      files.forEach(f => OS.print(\`  \${f}\`));
      OS.terminate(0);
    `
  ],
  [
    'C:\\ObsidianOS\\System32\\sysinfo.obx', 
    'sysinfo.obx', 
    'C:\\ObsidianOS\\System32', 
    `
      const res = OS.getResources();
      OS.print("--- SYSTEM INFORMATION ---");
      OS.print(\`OS: \${OS.getEnv('OS')}\`);
      OS.print(\`Memory: \${Math.floor(res.usedMemory)} MB / \${res.totalMemory} MB\`);
      OS.print(\`Uptime: \${res.uptime} seconds\`);
      OS.print(\`CPU Cores: \${res.cpuCores}\`);
      OS.terminate(0);
    `
  ],
  [
    'C:\\ObsidianOS\\System32\\bootmgr.obx',
    'bootmgr.obx',
    'C:\\ObsidianOS\\System32',
    `
OS.addBootLog('BootMgr: Initializing boot flow...');
// Read partition table from kernel
const pt = kernel.getPartitionTable();
const bc = kernel.getBootConfig();
if (pt) {
  OS.addBootLog('BootMgr: Disk scheme: ' + pt.scheme + ' (' + pt.diskLabel + ')');
  pt.partitions.forEach(function(p) {
    if (p.driveLetter) OS.addBootLog('BootMgr: Partition ' + p.index + ': ' + p.driveLetter + ': [' + p.type + '] ' + p.sizeMB + 'MB "' + p.label + '"');
  });
}
if (bc) {
  OS.addBootLog('BootMgr: Boot scheme: ' + bc.scheme + ' | Default: ' + bc.defaultEntry + ' | Timeout: ' + bc.timeout + 's');
  var defaultEntry = bc.entries.find(function(e) { return e.id === bc.defaultEntry; });
  if (defaultEntry) OS.addBootLog('BootMgr: Loading -> ' + defaultEntry.label);
}
const bootConfig = OS.readFile('C:\\\\ObsidianOS\\\\System32\\\\boot.ini');
if (!bootConfig) { OS.triggerBSOD({ stopCode: 'BOOT_LOADER_FAILURE', technicalInfo: 'boot.ini missing' }); return; }
const defaultArcMatch = bootConfig.match(/default=(.*)/i);
const arcPath = defaultArcMatch ? defaultArcMatch[1].trim() : '';
OS.addBootLog('BootMgr: ARC Path -> ' + arcPath);
if (!arcPath.includes('partition(1)')) { OS.triggerBSOD({ stopCode: 'INACCESSIBLE_BOOT_DEVICE', technicalInfo: 'Arc Path Partition Fail' }); return; }
const sysRootMatch = arcPath.match(/partition[(]1[)]\\\\(.*)/i);
const sysRoot = (sysRootMatch && sysRootMatch[1]) ? sysRootMatch[1].trim() : 'ObsidianOS';
const files = OS.listFiles('C:');
const actualRoot = files.find(f => f.toLowerCase() === sysRoot.toLowerCase());
if (!actualRoot) { OS.triggerBSOD({ stopCode: 'BOOT_LOADER_FAILURE', technicalInfo: 'System folder not found: ' + sysRoot }); return; }
OS.addBootLog('BootMgr: System Root -> C:\\\\' + actualRoot + ' [OK]');
OS.setBootPhase('KERNEL_INIT');
OS.addBootLog('BootMgr: Loading ntoskrnl.obx...');
const kernelCode = OS.readFile('C:\\\\' + actualRoot + '\\\\System32\\\\ntoskrnl.obx');
if (!kernelCode) { OS.triggerBSOD({ stopCode: 'KERNEL_DATA_INPAGE_ERROR', technicalInfo: 'ntoskrnl.obx missing' }); return; }
OS.allocateMemory(64, 'ntoskrnl.obx');
OS.createProcess('System', 'System Process', '⚙️');
OS.addBootLog('BootMgr: Loading kernel32.dll...');
const k32ok = OS.loadLibrary('C:\\\\ObsidianOS\\\\System32\\\\kernel32.dll');
if (!k32ok) { OS.triggerBSOD({ stopCode: 'KERNEL32_INIT_FAILED', technicalInfo: 'kernel32.dll failed to load', failedComponent: 'kernel32.dll', bugCheckCode: '0x0000007B', parameters: ['kernel32.dll'] }); return; }
OS.allocateMemory(12, 'kernel32.dll');
OS.addBootLog('  ✓ kernel32.dll');
OS.addBootLog('BootMgr: Loading gdi32.dll...');
const gdi32ok = OS.loadLibrary('C:\\\\ObsidianOS\\\\System32\\\\gdi32.dll');
if (!gdi32ok) { OS.triggerBSOD({ stopCode: 'GDI32_INIT_FAILED', technicalInfo: 'gdi32.dll failed to load', failedComponent: 'gdi32.dll', bugCheckCode: '0x0000007C', parameters: ['gdi32.dll'] }); return; }
OS.allocateMemory(8, 'gdi32.dll');
OS.addBootLog('  ✓ gdi32.dll');
OS.addBootLog('BootMgr: Loading user32.dll...');
const user32ok = OS.loadLibrary('C:\\\\ObsidianOS\\\\System32\\\\user32.dll');
if (!user32ok) { OS.triggerBSOD({ stopCode: 'USER32_INIT_FAILED', technicalInfo: 'user32.dll failed to load', failedComponent: 'user32.dll', bugCheckCode: '0x0000007D', parameters: ['user32.dll'] }); return; }
OS.allocateMemory(10, 'user32.dll');
OS.addBootLog('  ✓ user32.dll');
OS.setBootPhase('HAL_INIT');
OS.addBootLog('BootMgr: Loading hal.dll...');
const halOk = OS.loadLibrary('C:\\\\ObsidianOS\\\\System32\\\\hal.dll');
if (!halOk) { OS.triggerBSOD({ stopCode: 'HAL_INITIALIZATION_FAILED', technicalInfo: 'hal.dll failed to initialize', failedComponent: 'hal.dll', bugCheckCode: '0x0000005C', parameters: ['hal.dll'] }); return; }
OS.allocateMemory(8, 'hal.dll');
OS.addBootLog('  ✓ hal.dll');
OS.setBootPhase('DRIVER_LOAD');
OS.addBootLog('BootMgr: Loading drivers...');
OS.addBootLog('  Loading volmgr.sys...');
const volmgrOk = await OS.loadDriverAsync('C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\volmgr.sys');
if (!volmgrOk) { OS.triggerBSOD({ stopCode: 'VOLMGR_FAILED', technicalInfo: 'Volume Manager failed to initialize. Disk cannot be mounted.', failedComponent: 'volmgr.sys', bugCheckCode: '0x0000006B', parameters: ['volmgr.sys'] }); return; }
OS.addBootLog('  ✓ volmgr.sys');
OS.addBootLog('  Loading ntfs.sys...');
const ntfsOk = await OS.loadDriverAsync('C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\ntfs.sys');
if (!ntfsOk) { OS.triggerBSOD({ stopCode: 'NTFS_FILE_SYSTEM', technicalInfo: 'NTFS driver failed to initialize.', failedComponent: 'ntfs.sys', bugCheckCode: '0x00000024', parameters: ['ntfs.sys'] }); return; }
OS.addBootLog('  ✓ ntfs.sys');
OS.addBootLog('  Loading vss.sys...');
const vssOk = await OS.loadDriverAsync('C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\vss.sys');
if (vssOk) { OS.addBootLog('  ✓ vss.sys'); } else { OS.addBootLog('  ! vss.sys failed (non-critical)'); }
const passiveDrivers = ['disk.sys', 'display.sys', 'hid.sys', 'netio.sys'];
for (const d of passiveDrivers) {
  OS.registerDriver({ name: d, status: 'loaded', type: 'kernel' });
  OS.addBootLog('  ✓ ' + d);
}
OS.setBootPhase('SERVICE_INIT');
OS.addBootLog('BootMgr: Enabling user session...');
OS.finalizeBoot();
OS.terminate(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\drivers\\volmgr.sys',
    'volmgr.sys',
    'C:\\ObsidianOS\\System32\\drivers',
    `
OS.addBootLog('volmgr: Initializing Volume Manager...');
const available = await kernel.opfsDriver.isAvailable();
if (!available) { OS.error('volmgr: OPFS not available in this browser.'); OS.terminate(1); return; }
const diskExists = await kernel.opfsDriver.diskExists();
if (!diskExists) {
  OS.addBootLog('volmgr: No disk found. Formatting virtual disk...');
  const defaultNodes = await kernel.getDefaultNodes();
  await kernel.opfsDriver.formatDisk(defaultNodes);
  OS.addBootLog('volmgr: Format complete. Volume C: created.');
} else { OS.addBootLog('volmgr: Existing disk found. Mounting C:...'); }
OS.registerDriver({ name: 'volmgr', path: 'C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\volmgr.sys', status: 'loaded', type: 'storage', loadOrder: 1, dependencies: [] });
OS.addBootLog('volmgr: Volume C: mounted [OPFS]');
OS.terminate(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\drivers\\ntfs.sys',
    'ntfs.sys',
    'C:\\ObsidianOS\\System32\\drivers',
    `
OS.addBootLog('ntfs: Initializing NTFS driver...');
await kernel.registerFsDriver(kernel.opfsDriver);
const alreadyHydrated = kernel.getFsNodeCount() > 0 && kernel.isDiskDriverActive();
if (!alreadyHydrated) {
  OS.addBootLog('ntfs: Hydrating filesystem cache...');
  const count = await kernel.hydrateFromDisk();
  OS.addBootLog('ntfs: Loaded ' + count + ' nodes into cache.');
} else { OS.addBootLog('ntfs: Cache already loaded (' + kernel.getFsNodeCount() + ' nodes).'); }
OS.registerDriver({ name: 'ntfs', path: 'C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\ntfs.sys', status: 'loaded', type: 'filesystem', loadOrder: 2, dependencies: ['volmgr'] });
OS.addBootLog('ntfs: NTFS driver ready.');
OS.terminate(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\drivers\\vss.sys',
    'vss.sys',
    'C:\\ObsidianOS\\System32\\drivers',
    `
OS.addBootLog('vss: Volume Shadow Copy Service starting...');
const SNAPSHOT_FILE = 'C:\\\\System Volume Information\\\\VSS\\\\snapshot.json';
const snapshot = {};
let count = 0;
kernel._filesystem.forEach(function(node, path) {
  if (node.attributes && node.attributes.isSystem && node.type === 'file' && node.content) {
    snapshot[path] = node.content;
    count++;
  }
});
OS.writeFile(SNAPSHOT_FILE, JSON.stringify({ timestamp: Date.now(), files: snapshot }));
OS.addBootLog('vss: Snapshot created (' + count + ' system files)');
OS.registerDriver({ name: 'vss', path: 'C:\\\\ObsidianOS\\\\System32\\\\drivers\\\\vss.sys', status: 'loaded', type: 'storage', loadOrder: 3, dependencies: ['ntfs'] });
OS.terminate(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\System32\\cmd.osl',
    'cmd.osl',
    'C:\\ObsidianOS\\System32',
    `
      system::log("ObsidianOS Shell [Version 1.0.0]");
      system::log("(c) Obsidian Corporation. All rights reserved.");
      
      while (true) {
        let cwd = system::fs_getcwd();
        system::log("");
        system::log(cwd + "> ");
        
        let input = system::stdin();
        
        if (input == "help") {
          system::log("Comandos disponiveis:");
          system::log("  ls    - Listar arquivos");
          system::log("  cd    - Mudar diretorio");
          system::log("  echo  - Exibir texto");
          system::log("  help  - Mostrar esta ajuda");
          system::log("  exit  - Sair do shell");
        } else if (input == "ls") {
          let files = system::fs_list("");
          system::log(files);
        } else if (input == "exit") {
          return 0;
        } else if (input == "") {
          // Do nothing
        } else {
          system::log("Comando nao reconhecido: " + input);
        }
      }
    `.trim()
  ]
];
