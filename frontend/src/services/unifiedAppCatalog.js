const OPAQUE_APP_ID = /^(?:native|linux|wsl)-[a-f0-9]{16,64}$/i;
const MAX_LIST_ITEMS = 64;

const CATEGORY_RULES = [
  ['internet', /^(?:Network|WebBrowser|Email|InstantMessaging|Chat|News)$/i],
  ['development', /^(?:Development|IDE|GUIDesigner|Building|Debugger|RevisionControl)$/i],
  ['office', /^(?:Office|WordProcessor|Spreadsheet|Presentation|TextEditor)$/i],
  ['multimedia', /^(?:AudioVideo|Audio|Video|Player|Recorder|Music)$/i],
  ['graphics', /^(?:Graphics|Photography|RasterGraphics|VectorGraphics|2DGraphics|3DGraphics)$/i],
  ['security', /^(?:Security|X-Security|X-Kali-Security)$/i],
  ['system', /^(?:System|Settings|DesktopSettings|HardwareSettings|PackageManager|Monitor)$/i],
  ['entertainment', /^(?:Game|Amusement)$/i],
  ['utilities', /^(?:Utility|FileTools|FileManager|Archiving|Calculator|Clock)$/i],
];

function cleanString(value, maxLength = 256) {
  if (typeof value !== 'string') return '';
  return value.replace(/[\0\r\n]/g, ' ').trim().slice(0, maxLength);
}

function cleanList(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(item => cleanString(item)).filter(Boolean))].slice(0, MAX_LIST_ITEMS);
}

function normalizeSource(value) {
  if (value === 'windows') return 'windows';
  if (value === 'linux' || value === 'wsl') return 'linux';
  return null;
}

function primaryCategory(categories, source, scannerCategory = '') {
  for (const [category, matcher] of CATEGORY_RULES) {
    if (categories.some(item => matcher.test(item))) return category;
  }
  const normalized = cleanString(scannerCategory, 40).toLocaleLowerCase('en-US');
  if (normalized === 'games') return 'entertainment';
  if (['education', 'science', 'other'].includes(normalized)) return normalized;
  return source === 'linux' ? 'utilities' : 'utilities';
}

function safeIconUrl(value) {
  const iconUrl = cleanString(value, 1024);
  if (!iconUrl) return null;
  return iconUrl.startsWith('/__cloudos/') && !iconUrl.startsWith('//') ? iconUrl : null;
}

function mapCatalogRow(row) {
  if (!row || typeof row !== 'object') return null;
  const source = normalizeSource(row.source);
  const id = cleanString(row.id, 96);
  const name = cleanString(row.name, 160);
  if (!source || !OPAQUE_APP_ID.test(id) || !name) return null;

  const categories = cleanList(row.categories);
  const keywords = cleanList(row.keywords);
  const mimeTypes = cleanList(row.mimeTypes).map(item => item.toLocaleLowerCase('en-US'));
  const iconUrl = safeIconUrl(row.iconUrl);
  const rawIcon = cleanString(row.icon, 32);
  const fallback = rawIcon && [...rawIcon].length <= 4 ? rawIcon : (source === 'linux' ? '🐧' : '▦');
  const requestedMode = cleanString(row.windowMode, 40);
  const launchMode = source === 'linux'
    ? (requestedMode === 'xpra-contained' ? 'xpra-contained' : 'unavailable')
    : (requestedMode === 'native-managed' ? 'native-managed' : 'unavailable');
  const launchable = row.launchable !== false && launchMode !== 'unavailable';

  return {
    id,
    name,
    genericName: cleanString(row.genericName, 160),
    comment: cleanString(row.comment || row.description, 500),
    keywords,
    categories,
    mimeTypes,
    category: primaryCategory(categories, source, row.category),
    icon: iconUrl || fallback,
    iconUrl,
    emojiFallback: fallback,
    defaultWidth: source === 'linux' ? 1020 : 1040,
    defaultHeight: source === 'linux' ? 680 : 700,
    minWidth: 480,
    minHeight: 320,
    isResizable: true,
    isSingleInstance: false,
    catalogSource: source,
    source,
    distribution: cleanString(row.distribution, 120) || null,
    launchMode,
    launchable,
    isLinux: source === 'linux',
    linuxAppId: source === 'linux' ? id : undefined,
    isNative: source === 'windows',
    nativeAppId: source === 'windows' ? id : undefined,
  };
}

function rowsFromPayload(payload) {
  if (Array.isArray(payload)) return payload;
  return Array.isArray(payload?.apps) ? payload.apps : [];
}

/**
 * Converts the authenticated backend inventory to renderer-safe app definitions.
 * Executable commands and filesystem paths are deliberately never copied.
 */
export function mapUnifiedCatalogApps(payload) {
  const seen = new Set();
  const apps = [];
  for (const row of rowsFromPayload(payload)) {
    const app = mapCatalogRow(row);
    if (!app || seen.has(app.id)) continue;
    seen.add(app.id);
    apps.push(app);
  }
  return apps.sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
}
