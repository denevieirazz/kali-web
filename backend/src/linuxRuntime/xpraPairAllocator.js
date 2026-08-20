export const XPRA_PORT_START = 14500;
export const XPRA_PORT_END = 14549;
export const XPRA_DISPLAY_START = 100;
export const XPRA_DISPLAY_END = 149;
export const XPRA_BIND_TCP_HOST = '0.0.0.0';

export function displayForPort(port) {
  const numeric = Number(port);
  if (!Number.isInteger(numeric) || numeric < XPRA_PORT_START || numeric > XPRA_PORT_END) return null;
  return XPRA_DISPLAY_START + (numeric - XPRA_PORT_START);
}

export function portForDisplay(display) {
  const numeric = Number(display);
  if (!Number.isInteger(numeric) || numeric < XPRA_DISPLAY_START || numeric > XPRA_DISPLAY_END) return null;
  return XPRA_PORT_START + (numeric - XPRA_DISPLAY_START);
}

export function isXpraPair({ display, port } = {}) {
  const numericDisplay = Number(display);
  const numericPort = Number(port);
  return displayForPort(numericPort) === numericDisplay && portForDisplay(numericDisplay) === numericPort;
}

export function chooseXpraPair({ occupiedDisplays = [], freePorts = [] } = {}) {
  const occupied = new Set([...occupiedDisplays].map(Number).filter(Number.isInteger));
  const free = new Set([...freePorts].map(Number).filter(Number.isInteger));
  for (let port = XPRA_PORT_START; port <= XPRA_PORT_END; port += 1) {
    const display = displayForPort(port);
    if (display !== null && free.has(port) && !occupied.has(display)) return { display, port };
  }
  return null;
}

export function validateLedgerPair(entry) {
  if (!entry || !isXpraPair(entry)) {
    return {
      ok: false,
      code: 'XPRA_LEDGER_PAIR_INVALID',
      evidence: entry ? `display=:${entry.display}; port=${entry.port}` : 'entry=null',
    };
  }
  return {
    ok: true,
    code: 'XPRA_LEDGER_PAIR_VALID',
    evidence: `display=:${Number(entry.display)}; port=${Number(entry.port)}`,
  };
}
