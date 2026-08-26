import path from 'node:path';
import { buildReadOnlyRootfsFinalize, buildWritableContainedHomeMount } from './linuxRootfsSandbox.js';

const SANDBOX_DRIVE_ROOT = '/run/cloudos-drive';
const DRIVE_MOUNT_FLAGS = 'rw,nosuid,nodev,noexec,nosymfollow';
const DRIVE_BINDINGS = Object.freeze([
  Object.freeze({ source: ['Home', 'Desktop'], name: 'Desktop' }),
  Object.freeze({ source: ['Home', 'Documents'], name: 'Documents' }),
  Object.freeze({ source: ['Home', 'Downloads'], name: 'Downloads' }),
  Object.freeze({ source: ['Home', 'Projects'], name: 'Projects' }),
  Object.freeze({ source: ['Shared'], name: 'Shared' }),
]);

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

export function normalizeWslCloudOsDriveRoot(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().replace(/\\/g, '/').replace(/\/+$/, '');
  if (!/^\/mnt\/[a-z](?:\/[^/\0\r\n]+)+$/i.test(normalized)) return null;
  if (normalized.split('/').some(segment => segment === '.' || segment === '..')) return null;
  return normalized;
}

export function mapCloudOsDriveFilePath(value, wslRoot) {
  if (value === null || value === undefined || value === '') return null;
  const root = normalizeWslCloudOsDriveRoot(wslRoot);
  if (!root) throw new Error('CLOUDOS_DRIVE_WSL_ROOT_INVALID');

  const candidate = String(value).replace(/\\/g, '/');
  if (!candidate.startsWith('/')) throw new Error('CLOUDOS_DRIVE_FILE_OUTSIDE_SANDBOX');
  const relative = path.posix.relative(root, candidate);
  if (!relative || relative === '.' || relative === '..' || relative.startsWith('../') || path.posix.isAbsolute(relative)) {
    throw new Error('CLOUDOS_DRIVE_FILE_OUTSIDE_SANDBOX');
  }

  for (const binding of DRIVE_BINDINGS) {
    const sourcePrefix = binding.source.join('/');
    if (relative === sourcePrefix) return `${SANDBOX_DRIVE_ROOT}/${binding.name}`;
    if (relative.startsWith(`${sourcePrefix}/`)) {
      const suffix = relative.slice(sourcePrefix.length + 1);
      if (!suffix || suffix.split('/').some(segment => segment === '.' || segment === '..')) {
        throw new Error('CLOUDOS_DRIVE_FILE_OUTSIDE_SANDBOX');
      }
      return `${SANDBOX_DRIVE_ROOT}/${binding.name}/${suffix}`;
    }
  }

  throw new Error('CLOUDOS_DRIVE_FILE_OUTSIDE_SANDBOX');
}

export function buildCloudOsDriveSandboxMounts({ wslRoot, containedHome, uid, gid } = {}) {
  const root = normalizeWslCloudOsDriveRoot(wslRoot);
  if (!root) return [];
  if (!/^\/var\/lib\/cloudos\/contained-homes\/[a-zA-Z0-9._-]+$/.test(String(containedHome || ''))) {
    throw new Error('CLOUDOS_CONTAINED_HOME_INVALID');
  }
  if (!Number.isInteger(uid) || uid <= 0 || !Number.isInteger(gid) || gid <= 0) {
    throw new Error('CLOUDOS_CONTAINED_IDENTITY_INVALID');
  }

  const sourcePaths = DRIVE_BINDINGS.map(binding => `${root}/${binding.source.join('/')}`);
  const commands = [
    ...sourcePaths.map(source => `[ -d ${shellQuote(source)} ] && [ ! -L ${shellQuote(source)} ] || { echo CLOUDOS_DRIVE_BIND_INVALID >&2; exit 47; }`),
    ...buildWritableContainedHomeMount({ containedHome, uid, gid }),
    'install -d -m 755 /run/cloudos-drive',
    'mount -t tmpfs -o mode=755,nosuid,nodev,noexec tmpfs /run/cloudos-drive',
  ];

  for (let index = 0; index < DRIVE_BINDINGS.length; index += 1) {
    const binding = DRIVE_BINDINGS[index];
    const source = sourcePaths[index];
    const staging = `${SANDBOX_DRIVE_ROOT}/${binding.name}`;
    const homeTarget = `${containedHome}/${binding.name}`;
    commands.push(
      `install -d -o ${uid} -g ${gid} -m 700 ${shellQuote(staging)}`,
      `mount --bind ${shellQuote(source)} ${shellQuote(staging)}`,
      `mount -o remount,bind,${DRIVE_MOUNT_FLAGS} ${shellQuote(staging)} || { echo CLOUDOS_DRIVE_NOSYMFOLLOW_UNAVAILABLE >&2; exit 47; }`,
      `[ ! -L ${shellQuote(homeTarget)} ] || rm -f -- ${shellQuote(homeTarget)}`,
      `[ ! -e ${shellQuote(homeTarget)} ] || [ -d ${shellQuote(homeTarget)} ] || rm -f -- ${shellQuote(homeTarget)}`,
      `install -d -o ${uid} -g ${gid} -m 700 ${shellQuote(homeTarget)}`,
      `mount --bind ${shellQuote(staging)} ${shellQuote(homeTarget)}`,
      `mount -o remount,bind,${DRIVE_MOUNT_FLAGS} ${shellQuote(homeTarget)} || { echo CLOUDOS_DRIVE_NOSYMFOLLOW_UNAVAILABLE >&2; exit 47; }`,
    );
  }

  commands.push(
    ...DRIVE_BINDINGS.map(binding => `[ -d ${shellQuote(`${SANDBOX_DRIVE_ROOT}/${binding.name}`)} ] || { echo CLOUDOS_DRIVE_BIND_MISSING >&2; exit 47; }`),
    ...buildReadOnlyRootfsFinalize({ containedHome, uid, gid }),
  );
  return commands;
}

export const cloudOsDriveSandboxPolicy = Object.freeze({
  sandboxRoot: SANDBOX_DRIVE_ROOT,
  mountFlags: Object.freeze(DRIVE_MOUNT_FLAGS.split(',')),
  bindings: DRIVE_BINDINGS.map(binding => Object.freeze({ source: [...binding.source], name: binding.name })),
});
