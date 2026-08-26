function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/**
 * Converts an element rectangle into the small, integer viewport contract
 * accepted by the native host. The host still validates and clamps the final
 * position; this prevents stale/off-screen DOM measurements reaching it.
 */
export function nativeViewportBounds(rect, viewport) {
  if (!rect || !viewport) return null;
  const rawX = finiteNumber(rect.x ?? rect.left);
  const rawY = finiteNumber(rect.y ?? rect.top);
  const rawWidth = finiteNumber(rect.width);
  const rawHeight = finiteNumber(rect.height);
  const viewportWidth = finiteNumber(viewport.width);
  const viewportHeight = finiteNumber(viewport.height);

  if ([rawX, rawY, rawWidth, rawHeight, viewportWidth, viewportHeight].some((value) => value === null)) return null;
  if (rawWidth <= 0 || rawHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0) return null;

  const x = Math.max(0, Math.min(Math.round(rawX), Math.floor(viewportWidth) - 1));
  const y = Math.max(0, Math.min(Math.round(rawY), Math.floor(viewportHeight) - 1));
  const right = Math.max(x + 1, Math.min(Math.round(rawX + rawWidth), Math.floor(viewportWidth)));
  const bottom = Math.max(y + 1, Math.min(Math.round(rawY + rawHeight), Math.floor(viewportHeight)));

  return { x, y, width: right - x, height: bottom - y };
}

/** Finds the concrete native window created by an allow-listed launch. */
export function nativeSessionForLaunch(sessions, launch) {
  if (!Array.isArray(sessions) || !launch) return null;
  if (typeof launch.sessionId === 'string' && launch.sessionId) {
    const exact = sessions.find((session) => session?.sessionId === launch.sessionId);
    if (exact) return exact;
  }
  if (!Number.isInteger(launch.pid) || launch.pid <= 0) return null;
  const candidates = sessions.filter((session) => session?.processId === launch.pid);
  if (!candidates.length) return null;
  return candidates.sort((left, right) => nativeSessionScore(right) - nativeSessionScore(left))[0] || null;
}

function nativeSessionScore(session) {
  const title = typeof session?.title === 'string' ? session.title.trim() : '';
  const genericTitle = /^Aplicativo\s+\d+$/i.test(title);
  const width = finiteNumber(session?.bounds?.width) || 0;
  const height = finiteNumber(session?.bounds?.height) || 0;
  const area = Math.min(width * height, 10_000_000);
  return (title && !genericTitle ? 1_000_000_000 : 0)
    + (session?.visible !== false ? 100_000_000 : 0)
    + (session?.contained === true ? 10_000_000 : 0)
    + area;
}
