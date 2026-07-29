const fs = require('fs');
const os = require('os');

let prevCpu = null;

function readCpu() {
  try {
    const raw = fs.readFileSync('/proc/stat', 'utf8');
    const line = raw.split('\n')[0].split(/\s+/).slice(1).map(Number);
    const idle = line[3] + line[4];
    const total = line.reduce((a, b) => a + b, 0);
    let usage = 0;
    if (prevCpu) {
      const dTotal = total - prevCpu.total;
      const dIdle = idle - prevCpu.idle;
      usage = dTotal > 0 ? (1 - dIdle / dTotal) * 100 : 0;
    }
    prevCpu = { total, idle };
    return Math.min(100, Math.max(0, usage));
  } catch {
    return (os.loadavg()[0] || 0) * 10;
  }
}

function readMem() {
  try {
    const raw = fs.readFileSync('/proc/meminfo', 'utf8');
    const get = (k) => parseInt((raw.match(new RegExp(`${k}:\\s+(\\d+)`)) || [])[1] || 0, 10) * 1024;
    const total = get('MemTotal');
    const avail = get('MemAvailable');
    return { total, used: total - avail, percent: total ? ((total - avail) / total) * 100 : 0 };
  } catch {
    const total = os.totalmem();
    const free = os.freemem();
    return { total, used: total - free, percent: total ? ((total - free) / total) * 100 : 0 };
  }
}

function readNet() {
  try {
    const raw = fs.readFileSync('/proc/net/dev', 'utf8');
    const lines = raw.split('\n').slice(2);
    let rx = 0, tx = 0;
    for (const l of lines) {
      const parts = l.trim().split(/\s+/);
      if (!parts[0] || parts[0].replace(':', '') === 'lo') continue;
      rx += parseInt(parts[1], 10) || 0;
      tx += parseInt(parts[9], 10) || 0;
    }
    return { rx, tx };
  } catch { return { rx: 0, tx: 0 }; }
}

let prevNet = readNet();

function snapshot() {
  const net = readNet();
  const deltaRx = Math.max(0, net.rx - prevNet.rx);
  const deltaTx = Math.max(0, net.tx - prevNet.tx);
  prevNet = net;
  return {
    ts: Date.now(),
    cpu: readCpu(),
    mem: readMem(),
    net: { rxBytesPerSec: deltaRx, txBytesPerSec: deltaTx },
    uptime: os.uptime(),
    loadavg: os.loadavg(),
  };
}

module.exports = { snapshot };
