import type { FileSystemNode } from '../../types';

const now = Date.now();

const defaultPermissions = { read: true, write: true, execute: false, hidden: false, system: false };
const defaultAttributes = { isReadOnly: false, isHidden: false, isSystem: false, isArchive: false };
const sysPermissions = { read: true, write: false, execute: true, hidden: false, system: true };
const sysAttributes = { isReadOnly: true, isHidden: false, isSystem: true, isArchive: false };

export function makeDir(path: string, name: string, parentPath: string, sys = false): FileSystemNode {
  return {
    id: path, name, type: 'directory', path, parentPath, size: 0,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: sys ? sysPermissions : defaultPermissions,
    attributes: sys ? sysAttributes : defaultAttributes,
    children: [],
  };
}

export function makeFile(path: string, name: string, parentPath: string, ext: string, content = '', size = 0): FileSystemNode {
  return {
    id: path, name, type: 'file', path, parentPath, size: size || content.length,
    extension: ext, content,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: defaultPermissions, attributes: defaultAttributes,
  };
}

export function makeSysFile(path: string, name: string, parentPath: string, ext: string, content = ''): FileSystemNode {
  return {
    id: path, name, type: 'file', path, parentPath, size: content.length,
    extension: ext, content,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: sysPermissions, attributes: sysAttributes,
  };
}

export function makeSysExe(path: string, name: string, parentPath: string, description: string, version = '10.0.26100.1'): FileSystemNode {
  return {
    id: path, name, type: 'file', path, parentPath,
    size: Math.floor(Math.random() * 500000) + 50000,
    extension: name.split('.').pop() || 'obx',
    content: `[${name}]\nDescription=${description}\nVersion=${version}\nType=PE32+ executable\nSubsystem=Windows GUI\nCompany=Obsidian Corporation`,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: sysPermissions, attributes: sysAttributes,
    metadata: { version, description, company: 'Obsidian Corporation' },
  };
}

export function makeAppExe(path: string, name: string, parentPath: string, appId: string, icon: string, category: string, displayName: string): FileSystemNode {
  const manifest = JSON.stringify({
    appId,
    name: displayName,
    icon,
    category,
    type: 'executable',
    launchTarget: appId
  }, null, 2);

  return {
    id: path, name, type: 'file', path, parentPath,
    size: 1024 + Math.floor(Math.random() * 2000),
    extension: 'obx',
    content: manifest,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: sysPermissions, attributes: sysAttributes,
    metadata: { appId, type: 'app_executable' },
  };
}

export function makeBinaryExe(path: string, name: string, parentPath: string, code: string): FileSystemNode {
  return {
    id: path, name, type: 'file', path, parentPath,
    size: code.length,
    extension: 'obx',
    content: code,
    createdAt: now, modifiedAt: now, accessedAt: now,
    permissions: sysPermissions, attributes: sysAttributes,
    metadata: { type: 'binary_executable' },
  };
}

export { now };
