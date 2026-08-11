export const sdkFiles: [string, string, string, string][] = [
  [
    'C:\\ObsidianOS\\SDK\\lib\\obsidian.js',
    'obsidian.js',
    'C:\\ObsidianOS\\SDK\\lib',
    `
var StdIO = {
  print: (m) => OS.print(m),
  error: (m) => OS.error(m),
  clear: () => OS.print("\u001b[2J\u001b[H")
};
var FS = {
  read: (p) => OS.readFile(p),
  write: (p, c) => OS.writeFile(p, c),
  ls: (p) => OS.listFiles(p)
};
var Proc = {
  pid: OS.pid,
  args: OS.args,
  exit: (c) => OS.terminate(c),
  wait: (ms) => OS.wait(ms)
};
var Kernel = {
  uptime: () => OS.getResources().uptime,
  ping: () => OS.ping()
};
var print = StdIO.print;
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\SDK\\docs\\syscalls.txt',
    'syscalls.txt',
    'C:\\ObsidianOS\\SDK\\docs',
    `
--- OBSIDIAN OS SYSTEM CALL REFERENCE ---
Version: 2.0.0-GA
Loaded libraries: kernel32.dll, hal.dll

════════════════════════════════════════
 CORE OS API  (always available as OS.*)
════════════════════════════════════════
OS.print(msg)               stdout
OS.error(msg)               stderr
OS.readFile(path)           read file → string | undefined
OS.writeFile(path, content) write/create file
OS.listFiles(path)          list directory → string[]
OS.wait(ms)                 async sleep
OS.terminate(exitCode)      exit process
OS.getResources()           { totalMemory, usedMemory, cpuCores, cpuUsage, uptime, networkUp }
OS.getEnv(key)              OS | USER
OS.getTimestamp()           Date.now()
OS.ping()                   { status, latency }
OS.loadLibrary(dllPath)     load a .dll module → bool
OS.pid                      current process id
OS.args                     string[] of launch arguments
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\SDK\\examples\\hello_world.obx',
    'hello_world.obx',
    'C:\\ObsidianOS\\SDK\\examples',
    `
StdIO.print("--- Hello from the SDK ---");
StdIO.print("PID: " + Proc.pid);
StdIO.print("Running on: " + OS.getEnv('OS'));
await Proc.wait(500);
StdIO.print("Closing in 1 second...");
await Proc.wait(1000);
Proc.exit(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\SDK\\examples\\sysdiag.obx',
    'sysdiag.obx',
    'C:\\ObsidianOS\\SDK\\examples',
    `
print("╔══════════════════════════════════╗");
print("║   ObsidianOS System Diagnostics  ║");
print("╚══════════════════════════════════╝");
await Proc.wait(200);
var cpu = OS.HAL.getCpuInfo();
print(""); print("[ CPU ]");
print("  Model   : " + cpu.model);
print("  Cores   : " + cpu.cores);
print("  Usage   : " + cpu.usage.toFixed(1) + "%");
print("  Features: " + cpu.features.join(", "));
await Proc.wait(150);
var mem = OS.HAL.getMemoryMap();
var memStatus = OS.Kernel32.GlobalMemoryStatus();
print(""); print("[ MEMORY ]");
print("  Total   : " + mem.totalPhysical + " MB");
print("  Used    : " + mem.usedPhysical.toFixed(1) + " MB");
print("  Free    : " + mem.freePhysical.toFixed(1) + " MB");
print("  Load    : " + memStatus.loadPercent + "%");
await Proc.wait(150);
var disk = OS.HAL.getDiskInfo();
print(""); print("[ DISK ]");
print("  Drive   : " + disk.driveLetter + ":");
print("  FS      : " + disk.filesystem);
print("  Total   : " + (disk.totalDisk / 1024).toFixed(0) + " GB");
print("  Free    : " + (disk.freeDisk / 1024).toFixed(0) + " GB");
await Proc.wait(150);
var net = OS.HAL.getNetworkInfo();
print(""); print("[ NETWORK ]");
print("  Adapter : " + net.adapter);
print("  Status  : " + (net.connected ? "Connected" : "Disconnected"));
print("  Speed   : " + net.speed);
var pingRes = OS.ping();
print("  Ping    : " + pingRes.latency + "ms");
await Proc.wait(150);
var time = OS.HAL.getSystemTime();
print(""); print("[ SYSTEM ]");
print("  Time    : " + time.iso);
print("  Uptime  : " + time.uptime + "s");
print("  PID     : " + OS.Kernel32.GetCurrentProcessId());
print("  CmdLine : " + (OS.Kernel32.GetCommandLine() || "(none)"));
print(""); print("Diagnostics complete.");
Proc.exit(0);
    `.trim()
  ],
  [
    'C:\\ObsidianOS\\SDK\\examples\\calc_gdi.obx',
    'calc_gdi.obx',
    'C:\\ObsidianOS\\SDK\\examples',
    `
OS.User32.CreateLabel('display', '0', 20, 20, 260, 40);
OS.User32.UpdateElementText('display', '<div style="font-size:24px; text-align:right; border:1px solid #000; padding:5px; background:#fff; border-radius:4px">0</div>');
let currentVal = '0'; let op = ''; let lastVal = 0;
function updateDisplay() { OS.User32.UpdateElementText('display', '<div style="font-size:24px; text-align:right; border:1px solid #000; padding:5px; background:#fff; border-radius:4px">' + currentVal + '</div>'); }
function handleNum(n) { if (currentVal === '0' || currentVal === 'Err') currentVal = n; else currentVal += n; updateDisplay(); }
function handleOp(o) { lastVal = parseFloat(currentVal); op = o; currentVal = '0'; updateDisplay(); }
function handleEq() {
    let result = 0; let curr = parseFloat(currentVal);
    if(op === '+') result = lastVal + curr;
    if(op === '-') result = lastVal - curr;
    if(op === '*') result = lastVal * curr;
    if(op === '/') result = curr === 0 ? 'Err' : lastVal / curr;
    currentVal = String(result); op = ''; updateDisplay();
}
let keys = [ ['7','8','9','/'], ['4','5','6','*'], ['1','2','3','-'], ['0','C','=','+'] ];
for(let r=0; r<4; r++) {
   for(let c=0; c<4; c++) {
      let k = keys[r][c]; let id = 'btn_' + k;
      OS.User32.CreateButton(id, k, 20 + c*65, 80 + r*65, 60, 60);
      OS.User32.OnMessage(id, 'click', function() {
          if(k === 'C') { currentVal = '0'; lastVal = 0; op = ''; updateDisplay(); }
          else if(k === '=') { handleEq(); }
          else if(['+','-','*','/'].indexOf(k) !== -1) { handleOp(k); }
          else { handleNum(k); }
      });
   }
}
await OS.User32.MessageLoop();
    `.trim()
  ]
];
