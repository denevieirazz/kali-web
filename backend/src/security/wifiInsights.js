function foldLabel(value) {
  return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase();
}

function keyValue(line) {
  const index = line.indexOf(':');
  if (index < 0) return null;
  return { key: foldLabel(line.slice(0, index)), value: line.slice(index + 1).trim() };
}

function pick(entries, aliases) {
  for (const alias of aliases) {
    const normalized = foldLabel(alias);
    const match = entries.find(item => item.key === normalized);
    if (match?.value) return match.value;
  }
  return null;
}

export function parseWifiInterface(output) {
  const entries = String(output || '').split(/\r?\n/).map(keyValue).filter(Boolean);
  return {
    name: pick(entries, ['Name', 'Nome']),
    state: pick(entries, ['State', 'Estado']),
    ssid: pick(entries, ['SSID']),
    bssid: pick(entries, ['BSSID']),
    signal: pick(entries, ['Signal', 'Sinal']),
    channel: pick(entries, ['Channel', 'Canal']),
    radioType: pick(entries, ['Radio type', 'Tipo de rádio', 'Tipo de radio']),
    authentication: pick(entries, ['Authentication', 'Autenticação', 'Autenticacao']),
    cipher: pick(entries, ['Cipher', 'Cifra']),
    receiveRateMbps: pick(entries, ['Receive rate (Mbps)', 'Taxa de Recepção (Mbps)', 'Taxa de Recepcao (Mbps)']),
    transmitRateMbps: pick(entries, ['Transmit rate (Mbps)', 'Taxa de Transmissão (Mbps)', 'Taxa de Transmissao (Mbps)']),
  };
}

export function parseVisibleWifiNetworks(output) {
  const networks = [];
  let current = null;
  let currentBssid = null;

  const pushBssid = () => {
    if (current && currentBssid) {
      current.radios.push(currentBssid);
      currentBssid = null;
    }
  };
  const pushNetwork = () => {
    pushBssid();
    if (current) networks.push(current);
    current = null;
  };

  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const line = rawLine.trim();
    const ssidMatch = line.match(/^SSID\s+\d+\s*:\s*(.*)$/i);
    if (ssidMatch) {
      pushNetwork();
      current = { ssid: ssidMatch[1].trim() || '(oculto)', authentication: null, cipher: null, radios: [] };
      continue;
    }
    if (!current) continue;

    const bssidMatch = line.match(/^BSSID\s+\d+\s*:\s*([0-9a-f:-]{17})$/i);
    if (bssidMatch) {
      pushBssid();
      currentBssid = { bssid: bssidMatch[1].replace(/-/g, ':').toLowerCase(), signal: null, channel: null, radioType: null };
      continue;
    }

    const item = keyValue(line);
    if (!item) continue;
    if (['authentication', 'autenticacao'].includes(item.key)) current.authentication = item.value || null;
    else if (['encryption', 'cipher', 'criptografia', 'cifra'].includes(item.key)) current.cipher = item.value || null;
    else if (currentBssid && ['signal', 'sinal'].includes(item.key)) currentBssid.signal = item.value || null;
    else if (currentBssid && ['channel', 'canal'].includes(item.key)) currentBssid.channel = item.value || null;
    else if (currentBssid && ['radio type', 'tipo de radio'].includes(item.key)) currentBssid.radioType = item.value || null;
  }
  pushNetwork();

  return networks.slice(0, 100);
}

export function enrichWifiDiagnostics(value) {
  return {
    ...value,
    summary: {
      connected: parseWifiInterface(value?.interfaces),
      networks: parseVisibleWifiNetworks(value?.visibleNetworks),
    },
  };
}
