const CONTAINED_HOME = /^\/var\/lib\/cloudos\/contained-homes\/[a-zA-Z0-9._-]+$/;

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

function validateContainedHome(containedHome, uid, gid) {
  const home = String(containedHome || '');
  if (!CONTAINED_HOME.test(home)) throw new Error('CLOUDOS_CONTAINED_HOME_INVALID');
  if (!Number.isInteger(uid) || uid <= 0 || !Number.isInteger(gid) || gid <= 0) {
    throw new Error('CLOUDOS_CONTAINED_IDENTITY_INVALID');
  }
  return home;
}

export function buildWritableContainedHomeMount({ containedHome, uid, gid } = {}) {
  const home = validateContainedHome(containedHome, uid, gid);
  return [
    `mount --bind ${shellQuote(home)} ${shellQuote(home)}`,
    `mount -o remount,bind,rw,nosuid,nodev,noexec ${shellQuote(home)}`,
  ];
}

export function buildReadOnlyRootfsFinalize({ containedHome, uid, gid } = {}) {
  const home = validateContainedHome(containedHome, uid, gid);
  const quotedHome = shellQuote(home);
  return [
    'mount -o remount,bind,ro,nosuid,nodev /',
    'cloudos_root_ro=0; while IFS=" " read -r cloudos_id cloudos_parent cloudos_major cloudos_root cloudos_mp cloudos_opts cloudos_rest; do if [ "$cloudos_mp" = / ]; then case ",$cloudos_opts," in *,ro,*) cloudos_root_ro=1 ;; esac; fi; done < /proc/self/mountinfo; [ "$cloudos_root_ro" = 1 ] || { echo CLOUDOS_ROOTFS_WRITABLE >&2; exit 49; }',
    `cloudos_home_rw=0; while IFS=" " read -r cloudos_id cloudos_parent cloudos_major cloudos_root cloudos_mp cloudos_opts cloudos_rest; do if [ "$cloudos_mp" = ${quotedHome} ]; then case ",$cloudos_opts," in *,rw,*) cloudos_home_rw=1 ;; esac; fi; done < /proc/self/mountinfo; [ "$cloudos_home_rw" = 1 ] || { echo CLOUDOS_CONTAINED_HOME_READONLY >&2; exit 49; }`,
  ];
}

export const linuxRootfsSandboxPolicy = Object.freeze({
  rootReadOnly: true,
  rootFlags: Object.freeze(['ro', 'nosuid', 'nodev']),
  containedHomeFlags: Object.freeze(['rw', 'nosuid', 'nodev', 'noexec']),
});
