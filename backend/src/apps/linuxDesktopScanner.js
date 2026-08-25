import crypto from 'node:crypto';
import { execFile as execFileCallback } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment } from '../wsl/distroService.js';

const execFileAsync = promisify(execFileCallback);

const DEFAULT_CACHE_TTL_MS = 15_000;
const MAX_DESKTOP_ENTRIES = 2_000;
const MAX_DISCOVERY_OUTPUT_BYTES = 32 * 1024 * 1024;
const MAX_ICON_BYTES = 4 * 1024 * 1024;
const PUBLIC_ICON_BASE_PATH = '/__cloudos/linux-runtime/apps';

const cacheByDistribution = new Map();
const pendingScanByDistribution = new Map();

// The script is constant and receives no interpolated input. Python emits JSON so
// filenames and Desktop Entry contents cannot escape a line-oriented protocol.
const DISCOVERY_SCRIPT = String.raw`
import base64
import json
import os
import shutil

MAX_FILES = 2000
MAX_FILE_BYTES = 1024 * 1024

def clean_root(value):
    if not value:
        return None
    value = os.path.abspath(os.path.expanduser(value))
    return value if value.startswith('/') else None

home = os.path.expanduser('~')
default_data_home = clean_root(os.path.join(home, '.local', 'share'))
data_home = clean_root(os.environ.get('XDG_DATA_HOME') or default_data_home)
data_dirs = os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share'
roots = []
for candidate in (data_home, default_data_home, '/usr/local/share', '/usr/share'):
    if candidate and candidate not in roots:
        roots.append(candidate)
for candidate in data_dirs.split(':'):
    root = clean_root(candidate)
    if root and root not in roots:
        roots.append(root)

records = []
seen_ids = set()
for root in roots:
    app_root = os.path.join(root, 'applications')
    if not os.path.isdir(app_root):
        continue
    real_app_root = os.path.realpath(app_root)
    for current, dirnames, filenames in os.walk(app_root, followlinks=False):
        dirnames.sort()
        filenames.sort()
        for filename in filenames:
            if len(records) >= MAX_FILES:
                break
            if not filename.endswith('.desktop'):
                continue
            full_path = os.path.join(current, filename)
            real_path = os.path.realpath(full_path)
            try:
                if os.path.commonpath((real_app_root, real_path)) != real_app_root:
                    continue
                stat = os.stat(real_path)
                if not os.path.isfile(real_path) or stat.st_size > MAX_FILE_BYTES:
                    continue
                with open(real_path, 'rb') as handle:
                    payload = handle.read(MAX_FILE_BYTES + 1)
                if len(payload) > MAX_FILE_BYTES:
                    continue
                content = payload.decode('utf-8')
            except (OSError, UnicodeError, ValueError):
                continue

            relative = os.path.relpath(full_path, app_root).replace(os.sep, '/')
            if relative.startswith('../') or relative == '..':
                continue
            desktop_id = relative.replace('/', '-')
            # XDG precedence: an entry in XDG_DATA_HOME masks the same system ID,
            # including a Hidden=true tombstone.
            if desktop_id in seen_ids:
                continue
            seen_ids.add(desktop_id)

            in_entry = False
            try_exec = None
            for raw_line in content.splitlines():
                line = raw_line.strip()
                if line.startswith('[') and line.endswith(']'):
                    in_entry = line == '[Desktop Entry]'
                    continue
                if in_entry and line.startswith('TryExec='):
                    try_exec = line.partition('=')[2].strip()
            try_exec_available = None
            if try_exec:
                try_exec = (try_exec.replace('\\s', ' ').replace('\\n', '\n')
                                      .replace('\\t', '\t').replace('\\r', '\r')
                                      .replace('\\\\', '\\'))
                if '/' in try_exec:
                    candidate = os.path.expanduser(try_exec)
                    try_exec_available = os.path.isfile(candidate) and os.access(candidate, os.X_OK)
                else:
                    try_exec_available = shutil.which(try_exec) is not None

            records.append({
                'desktopId': desktop_id,
                'desktopFile': full_path,
                'contentBase64': base64.b64encode(payload).decode('ascii'),
                'tryExecAvailable': try_exec_available,
            })
        if len(records) >= MAX_FILES:
            break
    if len(records) >= MAX_FILES:
        break

print(json.dumps(records, ensure_ascii=False, separators=(',', ':')))
`;

// The icon resolver is likewise constant. It never reads outside recognized icon
// roots, follows a bounded result set and verifies the final realpath before read.
const ICON_SCRIPT = String.raw`
import base64
import json
import mimetypes
import os
import sys

MAX_ICON_BYTES = 4 * 1024 * 1024
EXTENSIONS = ('.png', '.svg', '.xpm', '.webp', '.ico')

def clean_root(value):
    if not value:
        return None
    value = os.path.abspath(os.path.expanduser(value))
    return value if value.startswith('/') else None

home = os.path.expanduser('~')
default_data_home = clean_root(os.path.join(home, '.local', 'share'))
data_home = clean_root(os.environ.get('XDG_DATA_HOME') or default_data_home)
data_dirs = os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share'
roots = []
for candidate in [
    os.path.join(home, '.icons'),
    os.path.join(data_home, 'icons') if data_home else None,
    os.path.join(default_data_home, 'icons') if default_data_home else None,
    '/usr/local/share/icons',
    '/usr/share/icons',
    '/usr/local/share/pixmaps',
    '/usr/share/pixmaps',
]:
    root = clean_root(candidate)
    if root and root not in roots:
        roots.append(root)
for data_root in data_dirs.split(':'):
    data_root = clean_root(data_root)
    if not data_root:
        continue
    for candidate in (os.path.join(data_root, 'icons'), os.path.join(data_root, 'pixmaps')):
        if candidate not in roots:
            roots.append(candidate)
for candidate in ('/usr/share/pixmaps', '/var/lib/flatpak/exports/share/icons'):
    if candidate not in roots:
        roots.append(candidate)

def is_inside(candidate, root):
    try:
        return os.path.commonpath((os.path.realpath(candidate), os.path.realpath(root))) == os.path.realpath(root)
    except ValueError:
        return False

icon = sys.argv[1] if len(sys.argv) > 1 else ''
candidate_paths = []
if icon.startswith('/'):
    for root in roots:
        if os.path.isdir(root) and is_inside(icon, root):
            candidate_paths.append(icon)
            break
else:
    if '/' not in icon and '\\' not in icon and icon not in ('.', '..'):
        names = (icon,) if icon.lower().endswith(EXTENSIONS) else tuple(icon + ext for ext in EXTENSIONS)
        for root in roots:
            if not os.path.isdir(root):
                continue
            for current, dirnames, filenames in os.walk(root, followlinks=False):
                dirnames.sort()
                filenames_set = set(filenames)
                for name in names:
                    if name in filenames_set:
                        candidate_paths.append(os.path.join(current, name))
                        break
                if candidate_paths:
                    break
            if candidate_paths:
                break

result = None
for candidate in candidate_paths[:1]:
    try:
        real_path = os.path.realpath(candidate)
        if not any(os.path.isdir(root) and is_inside(real_path, root) for root in roots):
            continue
        size = os.path.getsize(real_path)
        if size <= 0 or size > MAX_ICON_BYTES:
            continue
        with open(real_path, 'rb') as handle:
            payload = handle.read(MAX_ICON_BYTES + 1)
        if len(payload) > MAX_ICON_BYTES:
            continue
        mime_type = mimetypes.guess_type(real_path)[0] or 'application/octet-stream'
        if mime_type not in ('image/png', 'image/svg+xml', 'image/x-xpixmap', 'image/webp', 'image/vnd.microsoft.icon', 'image/x-icon'):
            continue
        result = {
            'path': real_path,
            'mimeType': mime_type,
            'contentBase64': base64.b64encode(payload).decode('ascii'),
        }
    except (OSError, ValueError):
        pass

print(json.dumps(result, separators=(',', ':')))
`;

function scannerError(message, code, cause) {
  return Object.assign(new Error(message), { code, ...(cause ? { cause } : {}) });
}

function normalizeDistribution(value) {
  const distribution = String(value || '').trim();
  if (!distribution || distribution.length > 128 || /[\0-\x1f\\/]/u.test(distribution)) {
    throw scannerError('Distribuição Linux inválida.', 'LINUX_DISTRIBUTION_INVALID');
  }
  return distribution;
}

function normalizeLocale(value) {
  return String(value || process.env.LC_MESSAGES || process.env.LANG || 'en')
    .trim()
    .replace(/\.[^@]+/u, '')
    .replace(/-/gu, '_');
}

function localizedKeyCandidates(key, locale) {
  const normalized = normalizeLocale(locale);
  const [withoutModifier, modifier = ''] = normalized.split('@', 2);
  const [language, territory = ''] = withoutModifier.split('_', 2);
  const variants = [];
  if (language && territory && modifier) variants.push(`${key}[${language}_${territory}@${modifier}]`);
  if (language && territory) variants.push(`${key}[${language}_${territory}]`);
  if (language && modifier) variants.push(`${key}[${language}@${modifier}]`);
  if (language) variants.push(`${key}[${language}]`);
  variants.push(key);
  return [...new Set(variants)];
}

function unescapeDesktopString(value) {
  return String(value || '').replace(/\\([sntr\\])/gu, (_match, escaped) => ({
    s: ' ',
    n: '\n',
    t: '\t',
    r: '\r',
    '\\': '\\'
  })[escaped]);
}

function localizedValue(properties, key, locale) {
  for (const candidate of localizedKeyCandidates(key, locale)) {
    if (properties.has(candidate)) return unescapeDesktopString(properties.get(candidate));
  }
  return '';
}

function semicolonList(value, { lowerCase = false } = {}) {
  return String(value || '')
    .split(';')
    .map((item) => unescapeDesktopString(item).trim())
    .filter(Boolean)
    .map((item) => lowerCase ? item.toLocaleLowerCase('en-US') : item);
}

function desktopBoolean(value) {
  return String(value || '').trim().toLocaleLowerCase('en-US') === 'true';
}

function safeDesktopPath(value) {
  const desktopFile = String(value || '');
  if (!desktopFile.startsWith('/') || desktopFile.length > 4096 || /[\0\r\n]/u.test(desktopFile)) return null;
  const normalized = desktopFile.replace(/\\/gu, '/').replace(/\/{2,}/gu, '/');
  if (!normalized.endsWith('.desktop') || normalized.split('/').includes('..')) return null;
  return normalized;
}

function safeDesktopId(value, desktopFile) {
  const supplied = String(value || '').trim();
  const fallback = String(desktopFile || '').split('/').pop() || '';
  const desktopId = supplied || fallback;
  if (!desktopId.endsWith('.desktop') || desktopId.length > 512 || /[\0\r\n/\\]/u.test(desktopId)) return null;
  return desktopId;
}

function opaqueLinuxAppId(distribution, desktopId) {
  const digest = crypto.createHash('sha256')
    .update('cloudos-linux-desktop\0')
    .update(distribution)
    .update('\0')
    .update(desktopId)
    .digest('hex')
    .slice(0, 32);
  return `linux-${digest}`;
}

function normalizedCategory(categories) {
  const categorySet = new Set(categories.map((category) => category.toLocaleLowerCase('en-US')));
  const groups = [
    ['development', ['development', 'ide', 'building', 'debugger', 'revisioncontrol']],
    ['education', ['education']],
    ['games', ['game']],
    ['graphics', ['graphics', '2dgraphics', '3dgraphics', 'photography', 'publishing', 'viewer']],
    ['internet', ['network', 'webbrowser', 'email', 'instantmessaging', 'chat', 'filetransfer', 'remoteaccess']],
    ['multimedia', ['audiovideo', 'audio', 'video', 'music', 'player', 'recorder']],
    ['office', ['office', 'wordprocessor', 'spreadsheet', 'presentation', 'calendar', 'contactmanagement']],
    ['science', ['science']],
    ['system', ['system', 'settings', 'desktopsettings', 'hardwareSettings', 'filesystem', 'packagemanager']],
    ['utilities', ['utility', 'accessibility']]
  ];
  for (const [group, values] of groups) {
    if (values.some((value) => categorySet.has(value.toLocaleLowerCase('en-US')))) return group;
  }
  return 'other';
}

/**
 * Tokenizes the Desktop Entry Exec grammar. This is deliberately not a shell
 * parser: quotes group one argv item and metacharacters remain inert text.
 */
export function tokenizeDesktopExec(rawExec) {
  const input = String(rawExec || '');
  if (!input.trim() || input.length > 16_384 || /[\0\r\n]/u.test(input)) {
    throw scannerError('Exec inválido no Desktop Entry.', 'LINUX_DESKTOP_EXEC_INVALID');
  }

  const tokens = [];
  let token = '';
  let tokenStarted = false;
  let quoted = false;
  for (let index = 0; index < input.length; index += 1) {
    const character = input[index];
    if (character === '"') {
      quoted = !quoted;
      tokenStarted = true;
      continue;
    }
    if (character === '\\') {
      if (index + 1 >= input.length) {
        throw scannerError('Escape incompleto em Exec.', 'LINUX_DESKTOP_EXEC_INVALID');
      }
      token += input[index + 1];
      tokenStarted = true;
      index += 1;
      continue;
    }
    if (!quoted && /\s/u.test(character)) {
      if (tokenStarted) {
        tokens.push(token);
        token = '';
        tokenStarted = false;
      }
      continue;
    }
    token += character;
    tokenStarted = true;
  }
  if (quoted) throw scannerError('Aspas não finalizadas em Exec.', 'LINUX_DESKTOP_EXEC_INVALID');
  if (tokenStarted) tokens.push(token);
  if (!tokens.length || !tokens[0]) throw scannerError('Exec não contém executável.', 'LINUX_DESKTOP_EXEC_INVALID');
  return tokens;
}

function replaceScalarFieldCodes(token, context) {
  let output = '';
  for (let index = 0; index < token.length; index += 1) {
    if (token[index] !== '%') {
      output += token[index];
      continue;
    }
    const code = token[index + 1];
    if (!code) throw scannerError('Código de campo incompleto em Exec.', 'LINUX_DESKTOP_EXEC_FIELD_CODE_INVALID');
    index += 1;
    if (code === '%') output += '%';
    else if (code === 'c') output += context.name || '';
    else if (code === 'k') output += context.desktopFile || '';
    else throw scannerError(`Código de campo %${code} não pode ser combinado.`, 'LINUX_DESKTOP_EXEC_FIELD_CODE_INVALID');
  }
  return output;
}

/** Materializes a previously tokenized Exec template into a shell-free argv. */
export function expandDesktopExec(execTemplate, context = {}) {
  if (!Array.isArray(execTemplate) || !execTemplate.length) {
    throw scannerError('Template Exec inválido.', 'LINUX_DESKTOP_EXEC_INVALID');
  }
  const files = Array.isArray(context.files) ? context.files.map(String).filter(Boolean) : [];
  const urls = Array.isArray(context.urls) ? context.urls.map(String).filter(Boolean) : [];
  const output = [];

  for (const token of execTemplate) {
    if (token === '%f') {
      if (files[0]) output.push(files[0]);
    } else if (token === '%F') {
      output.push(...files);
    } else if (token === '%u') {
      if (urls[0]) output.push(urls[0]);
    } else if (token === '%U') {
      output.push(...urls);
    } else if (token === '%i') {
      if (context.icon) output.push('--icon', String(context.icon));
    } else if (/^%[dDnNvVm]$/u.test(token)) {
      // Deprecated field codes are ignored as required by the Desktop Entry spec.
    } else {
      const expanded = replaceScalarFieldCodes(String(token), context);
      if (expanded) output.push(expanded);
    }
  }

  if (!output.length || !output[0]) {
    throw scannerError('Exec não produziu executável.', 'LINUX_DESKTOP_EXEC_INVALID');
  }
  return output;
}

export function parseDesktopEntry(content, options = {}) {
  const distribution = normalizeDistribution(options.distribution);
  const desktopFile = safeDesktopPath(options.desktopFile);
  const desktopId = safeDesktopId(options.desktopId, desktopFile);
  if (!desktopFile || !desktopId || typeof content !== 'string' || content.length > 1024 * 1024) return null;

  const properties = new Map();
  let inDesktopEntry = false;
  for (const rawLine of content.replace(/^\uFEFF/u, '').split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      inDesktopEntry = line === '[Desktop Entry]';
      continue;
    }
    if (!inDesktopEntry) continue;
    const separator = rawLine.indexOf('=');
    if (separator <= 0) continue;
    const key = rawLine.slice(0, separator).trim();
    if (!/^[A-Za-z][A-Za-z0-9-]*(?:\[[^\]\0\r\n]+\])?$/u.test(key)) continue;
    properties.set(key, rawLine.slice(separator + 1).trim());
  }

  if (properties.get('Type') !== 'Application') return null;
  if (desktopBoolean(properties.get('Hidden')) || desktopBoolean(properties.get('NoDisplay'))) return null;
  if (properties.has('TryExec') && options.tryExecAvailable === false) return null;

  const name = localizedValue(properties, 'Name', options.locale).trim();
  const rawExec = properties.get('Exec');
  if (!name || !rawExec || /[\0\r\n]/u.test(name)) return null;

  let execTemplate;
  let launchArgv;
  const iconName = unescapeDesktopString(properties.get('Icon') || '').trim().slice(0, 1024);
  try {
    execTemplate = tokenizeDesktopExec(rawExec);
    launchArgv = expandDesktopExec(execTemplate, { name, icon: iconName, desktopFile });
  } catch {
    return null;
  }

  const categories = semicolonList(properties.get('Categories'));
  const mimeTypes = semicolonList(properties.get('MimeType'), { lowerCase: true });
  const keywords = localizedValue(properties, 'Keywords', options.locale)
    ? semicolonList(localizedValue(properties, 'Keywords', options.locale))
    : [];
  const genericName = localizedValue(properties, 'GenericName', options.locale).trim();
  const comment = localizedValue(properties, 'Comment', options.locale).trim();
  const tryExec = unescapeDesktopString(properties.get('TryExec') || '').trim();

  return Object.freeze({
    id: opaqueLinuxAppId(distribution, desktopId),
    source: 'linux',
    kind: 'linux-desktop',
    launchMode: 'xpra-contained',
    distribution,
    desktopId,
    desktopFile,
    name: name.slice(0, 240),
    genericName: genericName.slice(0, 240),
    comment: comment.slice(0, 1_000),
    keywords: Object.freeze(keywords.slice(0, 100)),
    categories: Object.freeze(categories.slice(0, 100)),
    category: normalizedCategory(categories),
    mimeTypes: Object.freeze(mimeTypes.slice(0, 200)),
    iconName,
    terminal: desktopBoolean(properties.get('Terminal')),
    tryExec: tryExec.slice(0, 4096),
    execTemplate: Object.freeze([...execTemplate]),
    launchArgv: Object.freeze([...launchArgv]),
    installed: true,
    isDiscovered: true
  });
}

function decodeDiscoveryRecord(record, distribution, locale) {
  if (!record || typeof record !== 'object') return null;
  let content;
  try {
    const encoded = String(record.contentBase64 || '');
    if (!encoded || encoded.length > (1024 * 1024 * 4 / 3) + 16) return null;
    content = Buffer.from(encoded, 'base64').toString('utf8');
  } catch {
    return null;
  }
  return parseDesktopEntry(content, {
    distribution,
    desktopId: record.desktopId,
    desktopFile: record.desktopFile,
    tryExecAvailable: record.tryExecAvailable,
    locale
  });
}

export function parseLinuxDesktopDiscovery(records, options = {}) {
  const distribution = normalizeDistribution(options.distribution);
  if (!Array.isArray(records)) throw scannerError('Resposta inválida do scanner Linux.', 'LINUX_DESKTOP_SCAN_INVALID');
  const apps = [];
  const seenDesktopIds = new Set();
  for (const record of records.slice(0, MAX_DESKTOP_ENTRIES)) {
    const desktopId = safeDesktopId(record?.desktopId, record?.desktopFile);
    if (!desktopId || seenDesktopIds.has(desktopId)) continue;
    seenDesktopIds.add(desktopId);
    const app = decodeDiscoveryRecord(record, distribution, options.locale);
    if (app) apps.push(app);
  }
  apps.sort((left, right) => left.name.localeCompare(right.name, options.locale || 'pt-BR'));
  return apps;
}

async function resolveDistribution(requestedDistribution, options) {
  if (requestedDistribution) return normalizeDistribution(requestedDistribution);
  if (typeof options.resolveDistribution === 'function') {
    return normalizeDistribution(await options.resolveDistribution());
  }
  const snapshotProvider = options.getWslSnapshot || getWslSnapshot;
  const snapshot = await snapshotProvider();
  const running = Array.isArray(snapshot?.distributions)
    ? snapshot.distributions.find((item) => item?.state === 'Running')?.name
    : null;
  const distribution = snapshot?.preferred || snapshot?.default || running || snapshot?.distributions?.[0]?.name;
  if (!snapshot?.operational || !distribution) {
    throw scannerError('Nenhuma distribuição Linux operacional está disponível.', 'LINUX_RUNTIME_UNAVAILABLE');
  }
  return normalizeDistribution(distribution);
}

async function executeDiscovery(distribution, options) {
  const runner = options.execFileAsync || execFileAsync;
  let stdout;
  try {
    ({ stdout } = await runner(options.wslExecutable || WSL_EXE, [
      '--distribution', distribution, '--exec', 'python3', '-c', DISCOVERY_SCRIPT
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: options.timeoutMs || 15_000,
      windowsHide: true,
      maxBuffer: MAX_DISCOVERY_OUTPUT_BYTES
    }));
  } catch (cause) {
    throw scannerError('Não foi possível enumerar os aplicativos Linux.', 'LINUX_DESKTOP_SCAN_FAILED', cause);
  }

  let records;
  try {
    records = JSON.parse(String(stdout || '[]').replace(/^\uFEFF/u, ''));
  } catch (cause) {
    throw scannerError('O scanner Linux retornou dados inválidos.', 'LINUX_DESKTOP_SCAN_INVALID', cause);
  }
  const apps = parseLinuxDesktopDiscovery(records, { distribution, locale: options.locale });
  return {
    timestamp: Date.now(),
    apps: Object.freeze(apps),
    byId: new Map(apps.map((app) => [app.id, app]))
  };
}

export async function scanLinuxDesktopApps(requestedDistribution, options = {}) {
  const distribution = await resolveDistribution(requestedDistribution, options);
  const cached = cacheByDistribution.get(distribution);
  const cacheTtlMs = Number.isFinite(options.cacheTtlMs) ? Math.max(0, options.cacheTtlMs) : DEFAULT_CACHE_TTL_MS;
  if (!options.force && cached && Date.now() - cached.timestamp < cacheTtlMs) return [...cached.apps];

  if (!options.force && pendingScanByDistribution.has(distribution)) {
    const pending = await pendingScanByDistribution.get(distribution);
    return [...pending.apps];
  }

  const pending = executeDiscovery(distribution, options);
  pendingScanByDistribution.set(distribution, pending);
  try {
    const result = await pending;
    cacheByDistribution.set(distribution, result);
    return [...result.apps];
  } finally {
    if (pendingScanByDistribution.get(distribution) === pending) pendingScanByDistribution.delete(distribution);
  }
}

export async function resolveLinuxDesktopApp(appId, requestedDistribution, options = {}) {
  const id = String(appId || '').trim();
  if (!/^linux-[a-f0-9]{32}$/u.test(id)) return null;
  if (!requestedDistribution) {
    for (const cached of cacheByDistribution.values()) {
      if (cached.byId.has(id)) return cached.byId.get(id);
    }
  }
  const distribution = await resolveDistribution(requestedDistribution, options);
  const apps = await scanLinuxDesktopApps(distribution, options);
  return apps.find((app) => app.id === id) || null;
}

export function toPublicLinuxDesktopApp(app, options = {}) {
  if (!app || !/^linux-[a-f0-9]{32}$/u.test(String(app.id || ''))) return null;
  const iconBasePath = String(options.iconBasePath || PUBLIC_ICON_BASE_PATH).replace(/\/$/u, '');
  return {
    id: app.id,
    name: app.name,
    genericName: app.genericName,
    comment: app.comment,
    keywords: [...app.keywords],
    categories: [...app.categories],
    category: app.category,
    mimeTypes: [...app.mimeTypes],
    terminal: app.terminal,
    icon: app.iconName || null,
    iconUrl: app.iconName ? `${iconBasePath}/${encodeURIComponent(app.id)}/icon?distribution=${encodeURIComponent(app.distribution)}` : null,
    source: 'linux',
    distribution: app.distribution,
    launchMode: 'xpra-contained',
    installed: true,
    isDiscovered: true
  };
}

export async function readLinuxDesktopIcon(appOrId, requestedDistribution, options = {}) {
  const app = typeof appOrId === 'string'
    ? await resolveLinuxDesktopApp(appOrId, requestedDistribution, options)
    : appOrId;
  if (!app?.iconName || app.distribution !== normalizeDistribution(requestedDistribution || app.distribution)) return null;
  if (app.iconName.length > 1024 || /[\0\r\n]/u.test(app.iconName)) return null;

  const runner = options.execFileAsync || execFileAsync;
  let stdout;
  try {
    ({ stdout } = await runner(options.wslExecutable || WSL_EXE, [
      '--distribution', app.distribution, '--exec', 'python3', '-c', ICON_SCRIPT, app.iconName
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: options.timeoutMs || 10_000,
      windowsHide: true,
      maxBuffer: MAX_ICON_BYTES * 2
    }));
  } catch {
    return null;
  }

  let payload;
  try {
    payload = JSON.parse(String(stdout || 'null').replace(/^\uFEFF/u, ''));
  } catch {
    return null;
  }
  if (!payload || typeof payload.contentBase64 !== 'string' || typeof payload.mimeType !== 'string') return null;
  if (!/^image\/(?:png|svg\+xml|x-xpixmap|webp|vnd\.microsoft\.icon|x-icon)$/u.test(payload.mimeType)) return null;
  const data = Buffer.from(payload.contentBase64, 'base64');
  if (!data.length || data.length > MAX_ICON_BYTES) return null;
  return { data, mimeType: payload.mimeType, path: String(payload.path || '') };
}

export function invalidateLinuxDesktopAppCache(distribution) {
  if (distribution) {
    const normalized = normalizeDistribution(distribution);
    cacheByDistribution.delete(normalized);
    pendingScanByDistribution.delete(normalized);
    return;
  }
  cacheByDistribution.clear();
  pendingScanByDistribution.clear();
}

// Short aliases keep integration call sites terse while retaining explicit names.
export const discoverLinuxDesktopApps = scanLinuxDesktopApps;
export const getLinuxDesktopAppById = resolveLinuxDesktopApp;
