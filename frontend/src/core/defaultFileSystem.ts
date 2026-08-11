// ============================================
// Virtual File System Store
// ============================================
import type { FileSystemNode } from '../types';
import { 
  makeDir, makeFile, makeSysFile, makeSysExe, 
  makeAppExe, makeBinaryExe 
} from './fs/helpers';

import { dirs } from './fs/dirs';
import { systemExes, dllModules, sysConfigFiles } from './fs/system';
import { driverFiles } from './fs/drivers';
import { appExes } from './fs/apps';
import { binaryExes } from './fs/binaries';
import { sdkFiles } from './fs/sdk';
import { userFiles } from './fs/user';
import { oslScripts } from './fs/osl.ts';



// Re-export helpers for kernel use
export { makeFile, makeDir };

// Build a realistic file system
export const defaultNodes: Record<string, FileSystemNode> = {};
if (typeof window !== 'undefined') {
  (window as any).__obsidian_defaultNodes = defaultNodes;
}

// 1. Dirs
dirs.forEach(([path, name, parent, sys]) => {
  defaultNodes[path as string] = makeDir(path as string, name as string, parent as string, sys as boolean);
});

// 2. System Executables
systemExes.forEach(([path, name, parent, desc, content]) => {
  if (content) {
    const node = makeBinaryExe(path, name, parent, content);
    if (!node.metadata) node.metadata = {};
    node.metadata.description = desc;
    node.attributes.isSystem = true;
    defaultNodes[path] = node;
  } else {
    defaultNodes[path] = makeSysExe(path, name, parent, desc);
  }
});

// 3. Applications
appExes.forEach(([path, name, parent, appId, icon, cat, display]) => {
  defaultNodes[path] = makeAppExe(path, name, parent, appId, icon, cat, display);
});

// 4. Binaries/Utilities
binaryExes.forEach(([path, name, parent, code]) => {
  defaultNodes[path] = makeBinaryExe(path, name, parent, code);
});

// 5. DLL Modules
dllModules.forEach(([path, name, parent, code]) => {
  defaultNodes[path] = makeBinaryExe(path, name, parent, code);
});

// 6. SDK Files
sdkFiles.forEach(([path, name, parent, code]) => {
  if (path.endsWith('.exe')) {
     defaultNodes[path] = makeBinaryExe(path, name, parent, code);
  } else {
     defaultNodes[path] = makeFile(path, name, parent, path.split('.').pop() || 'txt', code);
  }
});

// 7. Drivers
driverFiles.forEach(([path, name, parent, desc]) => {
  defaultNodes[path] = makeSysExe(path, name, parent, desc);
});

// 8. User Files
userFiles.forEach(([path, name, parent, ext, content, size]) => {
  defaultNodes[path] = makeFile(path, name, parent, ext, content, size);
});

// 9. System Config Files
sysConfigFiles.forEach(([path, name, parent, ext, content]) => {
  defaultNodes[path] = makeSysFile(path, name, parent, ext, content);
});

// 10. OSL Scripts
oslScripts.forEach(([path, name, parent, content]: [string, string, string, string]) => {
  defaultNodes[path] = makeFile(path, name, parent, 'osl', content);
});


