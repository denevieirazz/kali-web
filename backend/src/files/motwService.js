import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const MOTW_PAYLOAD = '[ZoneTransfer]\r\nZoneId=3\r\n';

export function applyMotw(filePath) {
  if (process.platform !== 'win32' || !filePath || typeof filePath !== 'string') return false;
  try {
    if (!fs.existsSync(filePath)) return false;
    const stat = fs.statSync(filePath);
    if (!stat.isFile()) return false;
    if (filePath.includes(':Zone.Identifier') || filePath.endsWith('.tmp')) return false;
    fs.writeFileSync(`${filePath}:Zone.Identifier`, MOTW_PAYLOAD, 'utf8');
    return true;
  } catch {
    return false;
  }
}

export function startMotwWatcher() {
  if (process.platform !== 'win32') return;
  const dirs = [
    path.join(os.homedir(), 'Downloads'),
    path.join(os.homedir(), 'CloudOS', 'Downloads')
  ];

  for (const downloadsDir of dirs) {
    if (!fs.existsSync(downloadsDir)) {
      try { fs.mkdirSync(downloadsDir, { recursive: true }); } catch {}
    }
    try {
      fs.watch(downloadsDir, (eventType, filename) => {
        if (!filename || filename.includes(':') || filename.endsWith('.tmp') || filename.startsWith('.')) return;
        const fullPath = path.join(downloadsDir, filename);
        setTimeout(() => {
          applyMotw(fullPath);
        }, 500);
      });
    } catch (err) {
      console.warn('[MotwWatcher] Não foi possível iniciar o watcher:', downloadsDir, err.message);
    }
  }
}
