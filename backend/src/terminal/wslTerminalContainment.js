const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const DISTRO = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const LINUX_PATH = /^\/(?:[A-Za-z0-9._+@%=-]+\/)*[A-Za-z0-9._+@%=-]+$/;

export const WSL_TERMINAL_CONTAINMENT = 'mount-pid-nointerop-v1';
export const WSL_TERMINAL_SAFE_PATH = '/usr/local/bin:/usr/bin:/bin';

// Classic seccomp BPF for x86_64. It rejects socket(AF_UNIX, ...) with EPERM,
// rejects a process that changes syscall ABI, and allows every other syscall.
// TCP/UDP remain available, while X11 abstract sockets, Wayland, D-Bus and the
// WSL interop socket cannot be opened even if one appears after the canaries.
const NO_UNIX_SOCKET_BPF_BASE64 = 'IAAAAAQAAAAVAAEAPgAAwAYAAAAAAACAIAAAAAAAAAAVAAADKQAAACAAAAAQAAAAFQAAAQEAAAAGAAAAAQAFAAYAAAAAAP9/';

const CANARY_SCRIPT = String.raw`
fail() {
  echo "CLOUDOS_TERMINAL_CONTAINMENT_CANARY_FAILED:$1" >&2
  exit 70
}

payload_mode="$1"
expected_uid="$2"
parent_mount_namespace="$3"

[ "$$" -eq 1 ] || fail pid-namespace
[ "$(id -u)" = "$expected_uid" ] || fail identity-mismatch
[ "$(id -u)" -ne 0 ] || fail root-identity
[ "$(readlink /proc/self/ns/mnt)" != "$parent_mount_namespace" ] || fail mount-namespace
run_filesystem="$(findmnt -n -o FSTYPE --mountpoint /run)"
tmp_filesystem="$(findmnt -n -o FSTYPE --mountpoint /tmp)"
run_user_filesystem="$(findmnt -n -o FSTYPE --mountpoint /run/user)"
if [ -z "$run_filesystem" ] || printf '%s\n' "$run_filesystem" | grep -qv '^tmpfs$'; then fail "private-run:$run_filesystem"; fi
if [ -z "$tmp_filesystem" ] || printf '%s\n' "$tmp_filesystem" | grep -qv '^tmpfs$'; then fail "private-tmp:$tmp_filesystem"; fi
if [ -z "$run_user_filesystem" ] || printf '%s\n' "$run_user_filesystem" | grep -qv '^tmpfs$'; then fail "private-run-user:$run_user_filesystem"; fi
[ -w /tmp ] || fail tmp-not-writable
[ -w "$XDG_RUNTIME_DIR" ] || fail runtime-not-writable
[ "$PATH" = "/usr/local/bin:/usr/bin:/bin" ] || fail unsafe-path
for blocked_environment in DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET PULSE_SERVER WSL_INTEROP WSLENV DBUS_SESSION_BUS_ADDRESS; do
  if env | grep -q "^$blocked_environment="; then
    fail "environment-present:$blocked_environment"
  fi
done
[ ! -S /tmp/.X11-unix/X0 ] || fail x11-socket-visible
[ ! -S /mnt/wslg/runtime-dir/wayland-0 ] || fail wayland-socket-visible
[ ! -x /init ] || fail init-executable
[ ! -r /init ] || fail init-readable

for masked_path in /mnt/wslg /run/WSL /run/systemd /run/dbus /proc/sys/fs/binfmt_misc; do
  if [ -e "$masked_path" ] && [ -r "$masked_path" ]; then
    fail "mask-readable:$masked_path"
  fi
done

cap_eff="$(awk '/^CapEff:/ { print $2 }' /proc/self/status)"
case "$cap_eff" in
  ''|0000000000000000) ;;
  *) fail effective-capabilities ;;
esac

seccomp_mode="$(awk '/^Seccomp:/ { print $2 }' /proc/self/status)"
seccomp_filters="$(awk '/^Seccomp_filters:/ { print $2 }' /proc/self/status)"
[ "$seccomp_mode" = 2 ] || fail seccomp-not-active
case "$seccomp_filters" in ''|0|*[!0-9]*) fail seccomp-filter-missing ;; esac

if awk '$2 ~ /:1770$/ && $4 == "0A" { found=1 } END { exit(found ? 0 : 1) }' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
  fail tcp-x11-listener-visible
fi

if [ -r /proc/sys/fs/binfmt_misc/WSLInterop ] && grep -q '^enabled' /proc/sys/fs/binfmt_misc/WSLInterop; then
  fail interop-handler-enabled
fi

if /init /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1; then
  fail init-interop-execution
fi
if /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1; then
  fail pe-interop-execution
fi

case "$payload_mode" in
  core)
    [ -x /run/cloudos-terminal-payload/cloudos-core ] || fail core-payload
    exec /run/cloudos-terminal-payload/cloudos-core serve
    ;;
  shell)
    [ -x /bin/bash ] || fail bash-missing
    exec /bin/bash -l
    ;;
  *)
    fail payload-mode
    ;;
esac
`.trim();

const ISOLATED_SCRIPT = String.raw`
payload_mode="$1"
payload_path="$2"
canary_script="$3"
parent_mount_namespace="$4"

[ "$(id -u)" -eq 0 ] || { echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:not-root >&2; exit 69; }

mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run
install -d -m 0700 /run/cloudos-terminal-payload
mount -t tmpfs -o mode=0700,nosuid,nodev tmpfs /run/cloudos-terminal-payload

case "$payload_mode" in
  core)
    [ -n "$payload_path" ] && [ -f "$payload_path" ] && [ -x "$payload_path" ] || {
      echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:core-unavailable >&2
      exit 69
    }
    cp -- "$payload_path" /run/cloudos-terminal-payload/cloudos-core
    chmod 0500 /run/cloudos-terminal-payload/cloudos-core
    ;;
  shell) ;;
  *) echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:payload-mode >&2; exit 69 ;;
esac

install -d -m 1777 /tmp
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp
install -d -m 0755 /run/user /run/WSL /run/systemd /run/dbus
mount -t tmpfs -o mode=0755,nosuid,nodev,noexec tmpfs /run/user

mask_dir=/run/cloudos-terminal-payload/mask-dir
mask_file=/run/cloudos-terminal-payload/mask-file
seccomp_filter=/run/cloudos-terminal-payload/no-unix-socket.bpf
install -d -m 000 "$mask_dir"
install -m 000 /dev/null "$mask_file"
printf '%s' '${NO_UNIX_SOCKET_BPF_BASE64}' | base64 -d > "$seccomp_filter"
chmod 0400 "$seccomp_filter"

for target in /mnt/wslg /run/WSL /run/systemd /run/dbus /proc/sys/fs/binfmt_misc; do
  if [ -e "$target" ]; then
    [ -d "$target" ] || { echo "CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:mask-type:$target" >&2; exit 69; }
    mount --bind "$mask_dir" "$target"
    mount -o remount,bind,ro,noexec,nosuid,nodev "$target"
  fi
done

if [ -e /init ]; then
  [ -f /init ] || { echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:init-type >&2; exit 69; }
  mount --bind "$mask_file" /init
  mount -o remount,bind,ro,noexec,nosuid,nodev /init
fi

identity="$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { print $1 ":" $3 ":" $4 ":" $6; exit }' /etc/passwd)"
if [ -z "$identity" ]; then
  identity="$(awk -F: '$1 == "nobody" && $3 > 0 { print $1 ":" $3 ":" $4 ":" $6; exit }' /etc/passwd)"
fi
[ -n "$identity" ] || { echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:no-nonroot-user >&2; exit 69; }

previous_ifs="$IFS"
IFS=:
set -- $identity
IFS="$previous_ifs"
target_user="$1"
target_uid="$2"
target_gid="$3"
target_home="$4"
case "$target_uid:$target_gid" in *[!0-9:]*|0:*) echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:unsafe-identity >&2; exit 69 ;; esac

if [ "$payload_mode" = core ]; then
  chown "$target_uid:$target_gid" /run/cloudos-terminal-payload/cloudos-core
fi
chmod 0711 /run/cloudos-terminal-payload

contained_home="$target_home"
if [ ! -d "$contained_home" ] || [ "$target_uid" -eq 65534 ]; then
  contained_home=/tmp/cloudos-home
  install -d -m 0700 "$contained_home"
  chown "$target_uid:$target_gid" "$contained_home"
fi

contained_runtime="/run/user/$target_uid"
install -d -m 0700 "$contained_runtime"
chown "$target_uid:$target_gid" "$contained_runtime"

exec setpriv \
  --reuid="$target_uid" \
  --regid="$target_gid" \
  --clear-groups \
  --no-new-privs \
  --bounding-set=-all \
  --inh-caps=-all \
  --ambient-caps=-all \
  --seccomp-filter "$seccomp_filter" \
  -- env -i \
    HOME="$contained_home" \
    USER="$target_user" \
    LOGNAME="$target_user" \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/bin:/bin \
    LANG=C.UTF-8 \
    TERM=xterm-256color \
    XDG_RUNTIME_DIR="$contained_runtime" \
    CLOUDOS=1 \
    CLOUDOS_TERMINAL_CONTAINMENT=mount-pid-nointerop-v1 \
    /bin/sh -ceu "$canary_script" cloudos-terminal-canary "$payload_mode" "$target_uid" "$parent_mount_namespace"
`.trim();

const OUTER_SCRIPT = String.raw`
for tool in unshare mount setpriv findmnt awk install cp chmod chown readlink grep id base64; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:tool:$tool" >&2
    exit 69
  }
done

[ "$(id -u)" -eq 0 ] || { echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:bootstrap-not-root >&2; exit 69; }
parent_mount_namespace="$(readlink /proc/self/ns/mnt)"
[ -n "$parent_mount_namespace" ] || { echo CLOUDOS_TERMINAL_CONTAINMENT_SETUP_FAILED:mount-namespace-unavailable >&2; exit 69; }

exec unshare \
  --mount \
  --pid \
  --fork \
  --kill-child \
  --mount-proc=/proc \
  --propagation private \
  /bin/sh -ceu "$1" cloudos-terminal-isolate "$2" "$3" "$4" "$parent_mount_namespace"
`.trim();

function validateDistribution(distribution) {
  if (!DISTRO.test(distribution || '')) throw new TypeError('Invalid WSL distribution identifier.');
  return distribution;
}

function validateCorePath(linuxCorePath) {
  if (typeof linuxCorePath !== 'string' || linuxCorePath.length > 4096 || !LINUX_PATH.test(linuxCorePath)) {
    throw new TypeError('Invalid cloudos-core Linux path.');
  }
  return linuxCorePath;
}

function buildArgs(distribution, mode, payloadPath = '') {
  validateDistribution(distribution);
  if (mode === 'core') validateCorePath(payloadPath);
  if (!['core', 'shell'].includes(mode)) throw new TypeError('Invalid terminal containment payload mode.');

  return [
    '--distribution', distribution,
    '--user', 'root',
    '--exec', '/usr/bin/env', '-i',
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin',
    'LANG=C.UTF-8',
    'TERM=xterm-256color',
    '/bin/sh', '-ceu', OUTER_SCRIPT,
    'cloudos-terminal-bootstrap',
    ISOLATED_SCRIPT,
    mode,
    payloadPath,
    CANARY_SCRIPT
  ];
}

export function buildContainedCoreBootstrapArgs(distribution, linuxCorePath) {
  return buildArgs(distribution, 'core', linuxCorePath);
}

export function buildContainedLegacyShellArgs(distribution) {
  return buildArgs(distribution, 'shell');
}

export function buildWslHostEnvironment(source = process.env) {
  const systemRoot = source.SystemRoot || source.SYSTEMROOT || 'C:\\Windows';
  const environment = {
    SystemRoot: systemRoot,
    windir: source.windir || source.WINDIR || systemRoot,
    ComSpec: source.ComSpec || source.COMSPEC || `${systemRoot}\\System32\\cmd.exe`,
    Path: `${systemRoot}\\System32;${systemRoot}`,
    PATHEXT: '.COM;.EXE;.BAT;.CMD',
    CLOUDOS: '1'
  };
  for (const key of ['TEMP', 'TMP', 'USERPROFILE', 'LOCALAPPDATA']) {
    if (typeof source[key] === 'string' && source[key]) environment[key] = source[key];
  }
  return environment;
}

export const WSL_TERMINAL_EXECUTABLE = WSL_EXE;
