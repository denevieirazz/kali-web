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

/** Returns true only when a native layout IPC would change observable state. */
export function nativeSurfaceLayoutChanged(previous, bounds, visible) {
  if (!bounds) return false;
  if (!previous) return true;
  return previous.visible !== visible
    || previous.bounds.x !== bounds.x
    || previous.bounds.y !== bounds.y
    || previous.bounds.width !== bounds.width
    || previous.bounds.height !== bounds.height;
}

function nativeBoundsEqual(left, right) {
  if (left === right) return true;
  if (!left || !right) return false;
  return left.x === right.x
    && left.y === right.y
    && left.width === right.width
    && left.height === right.height;
}

/**
 * Compares only state observable by NativeAppWindow. Host refresh timestamps and
 * fresh object identities must not wake React when the native session is unchanged.
 */
export function nativeSessionListsEqual(previous, next) {
  if (previous === next) return true;
  if (!Array.isArray(previous) || !Array.isArray(next) || previous.length !== next.length) return false;

  for (let index = 0; index < previous.length; index += 1) {
    const left = previous[index];
    const right = next[index];
    if (!left || !right
      || left.sessionId !== right.sessionId
      || left.title !== right.title
      || left.processId !== right.processId
      || left.minimized !== right.minimized
      || left.maximized !== right.maximized
      || left.contained !== right.contained
      || left.containmentMode !== right.containmentMode
      || left.visible !== right.visible
      || !nativeBoundsEqual(left.bounds, right.bounds)) {
      return false;
    }
  }
  return true;
}

/** Finds the concrete native window created by an allow-listed launch. */
export function nativeSessionForLaunch(sessions, launch) {
  if (!Array.isArray(sessions) || !launch) return null;
  if (typeof launch.sessionId === 'string' && launch.sessionId) {
    const exact = sessions.find((session) => session?.sessionId === launch.sessionId);
    if (exact) return exact;
  }
  if (!Number.isInteger(launch.pid) || launch.pid <= 0) return null;
  return sessions.find((session) => session?.processId === launch.pid) || null;
}
