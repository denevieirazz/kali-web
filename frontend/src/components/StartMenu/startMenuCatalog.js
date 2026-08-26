function normalize(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('pt-BR')
    .trim();
}

export function mergeStartMenuCatalog(cloudApps, nativeApps) {
  const seen = new Set();
  const cloudIds = new Set();
  const merged = [];

  for (const app of cloudApps || []) {
    if (!app?.id || !app?.name || seen.has(app.id)) continue;
    seen.add(app.id);
    cloudIds.add(app.id);
    merged.push({ ...app, launcher: 'cloud', source: 'cloudos' });
  }

  const sortedNativeApps = [...(nativeApps || [])]
    .filter((app) => app?.id && app?.name)
    .sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));

  for (const app of sortedNativeApps) {
    if (app.fallbackAppId && cloudIds.has(app.fallbackAppId)) continue;
    if (seen.has(app.id)) continue;
    seen.add(app.id);
    merged.push({
      ...app,
      launcher: 'native',
      defaultWidth: 960,
      defaultHeight: 680,
      minWidth: 480,
      minHeight: 320,
      isResizable: true,
    });
  }

  return merged;
}

export function searchStartMenuCatalog(apps, query) {
  const needle = normalize(query);
  if (!needle) return [...(apps || [])];
  return (apps || []).filter((app) => normalize([
    app.name,
    app.source === 'wsl' ? 'linux wsl' : app.source,
    app.distribution,
  ].filter(Boolean).join(' ')).includes(needle));
}
