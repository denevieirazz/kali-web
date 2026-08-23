const NATIVE_APP_ID = /^native-[a-f0-9]{24}$/;

function rowsFromPayload(payload) {
  if (Array.isArray(payload)) return payload;
  return Array.isArray(payload?.apps) ? payload.apps : [];
}

export function mapWindowsCatalogApps(payload) {
  const seen = new Set();
  const apps = [];

  for (const row of rowsFromPayload(payload)) {
    if (!row || row.source !== 'windows') continue;
    if (typeof row.id !== 'string' || !NATIVE_APP_ID.test(row.id) || seen.has(row.id)) continue;
    if (typeof row.name !== 'string' || !row.name.trim()) continue;

    seen.add(row.id);
    apps.push({
      id: row.id,
      name: row.name.trim().slice(0, 160),
      icon: typeof row.icon === 'string' && row.icon.trim() ? row.icon : '▦',
      defaultWidth: 1040,
      defaultHeight: 700,
      minWidth: 480,
      minHeight: 320,
      isResizable: true,
      isSingleInstance: false,
      category: 'utilities',
    });
  }

  return apps.sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
}
