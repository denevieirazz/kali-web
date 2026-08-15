export const TASKBAR_SIZE = 48;

const VALID_POSITIONS = new Set(['top', 'right', 'bottom', 'left']);

function normalizeDimension(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.floor(number)) : 0;
}

export function normalizeTaskbarPosition(value) {
  const normalized = typeof value === 'string' ? value.toLowerCase() : '';
  return VALID_POSITIONS.has(normalized) ? normalized : 'bottom';
}

export function calculateShellLayout(viewport, requestedPosition, requestedTaskbarSize = TASKBAR_SIZE) {
  const width = normalizeDimension(viewport?.width);
  const height = normalizeDimension(viewport?.height);
  const position = normalizeTaskbarPosition(requestedPosition);
  const rawSize = normalizeDimension(requestedTaskbarSize) || TASKBAR_SIZE;
  const horizontal = position === 'top' || position === 'bottom';
  const taskbarSize = Math.min(rawSize, horizontal ? height : width);

  const taskbar = { x: 0, y: 0, width, height: taskbarSize };
  const desktop = { x: 0, y: 0, width, height };

  switch (position) {
    case 'top':
      desktop.y = taskbarSize;
      desktop.height = Math.max(0, height - taskbarSize);
      break;
    case 'left':
      taskbar.width = taskbarSize;
      taskbar.height = height;
      desktop.x = taskbarSize;
      desktop.width = Math.max(0, width - taskbarSize);
      break;
    case 'right':
      taskbar.x = Math.max(0, width - taskbarSize);
      taskbar.width = taskbarSize;
      taskbar.height = height;
      desktop.width = Math.max(0, width - taskbarSize);
      break;
    case 'bottom':
    default:
      taskbar.y = Math.max(0, height - taskbarSize);
      desktop.height = Math.max(0, height - taskbarSize);
      break;
  }

  return { position, taskbar, desktop };
}
