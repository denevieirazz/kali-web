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

function parsePercent(value) {
  const match = String(value || '').match(/(\d{1,3})\s*%/);
  if (!match) return null;
  return Math.max(0, Math.min(100, Number(match[1])));
}

export function classifyWifiSecurity(authentication, cipher) {
  const text = `${authentication || ''} ${cipher || ''}`.toLowerCase();
  if (!text.trim()) return { attention: 'info', label: 'segurança não identificada' };
  if (/\b(open|aberta|none|sem autentica)/i.test(text)) return { attention: 'high', label: 'rede aberta' };
  if (/wep/i.test(text)) return { attention: 'high', label: 'WEP legado' };
  if (/wpa3/i.test(text)) return { attention: 'info', label: 'WPA3' };
  if (/wpa2/i.test(text)) return { attention: 'low', label: 'WPA2' };
  if (/wpa/i.test(text)) return { attention: 'medium', label: 'WPA legado ou modo misto' };
  return { attention: 'info', label: 'segurança identificada' };
}

export function analyzeWifiPosture(summary) {
  const connected = summary?.connected || {};
  const networks = Array.isArray(summary?.networks) ? summary.networks : [];
  const connectedSecurity = classifyWifiSecurity(connected.authentication, connected.cipher);
  const signalPercent = parsePercent(connected.signal);
  const currentChannel = String(connected.channel || '').trim() || null;
  const channelOccupancy = {};
  let openOrLegacyNetworks = 0;

  for (const network of networks) {
    const security = classifyWifiSecurity(network.authentication, network.cipher);
    if (security.attention === 'high') openOrLegacyNetworks += 1;
    for (const radio of network.radios || []) {
      const channel = String(radio.channel || '').trim();
      if (!channel) continue;
      channelOccupancy[channel] = (channelOccupancy[channel] || 0) + 1;
    }
  }

  const currentChannelOccupancy = currentChannel ? channelOccupancy[currentChannel] || 0 : 0;
  const recommendations = [];
  if (!connected.ssid) recommendations.push('Nenhuma conexão Wi‑Fi ativa foi identificada; confirme se o adaptador está ligado e se a rede esperada está conectada.');
  if (connectedSecurity.attention === 'high') recommendations.push('A conexão atual usa proteção aberta ou legada; prefira WPA2/WPA3 e desative WEP/rede aberta no ponto de acesso quando possível.');
  else if (connectedSecurity.attention === 'medium') recommendations.push('A conexão aparenta usar WPA legado ou modo misto; revise a configuração do roteador e migre para WPA2/WPA3 quando todos os dispositivos suportarem.');
  if (signalPercent !== null && signalPercent < 40) recommendations.push('O sinal está fraco; reposicione o dispositivo ou ponto de acesso antes de concluir que há falha de rede.');
  else if (signalPercent !== null && signalPercent < 65) recommendations.push('O sinal está intermediário; monitore perda/latência e considere melhorar cobertura se houver instabilidade.');
  if (currentChannelOccupancy >= 4) recommendations.push(`O canal ${currentChannel} tem ${currentChannelOccupancy} rádios visíveis; considere revisar a seleção automática de canal para reduzir contenção.`);
  if (openOrLegacyNetworks > 0) recommendations.push(`Há ${openOrLegacyNetworks} rede(s) visível(is) aberta(s) ou com proteção legada; evite conexão automática e mantenha perfis Wi‑Fi confiáveis.`);
  if (!recommendations.length) recommendations.push('Nenhum indicador básico de configuração Wi‑Fi chamou atenção nesta coleta; continue acompanhando sinal, canal e política do ponto de acesso.');

  const attentionOrder = { info: 0, low: 1, medium: 2, high: 3 };
  let highestAttention = connectedSecurity.attention;
  if (openOrLegacyNetworks > 0 && attentionOrder.high > attentionOrder[highestAttention]) highestAttention = 'high';
  if (signalPercent !== null && signalPercent < 40 && attentionOrder.medium > attentionOrder[highestAttention]) highestAttention = 'medium';

  return {
    highestAttention,
    connectedSecurity,
    signalPercent,
    currentChannel,
    currentChannelOccupancy,
    channelOccupancy,
    visibleNetworkCount: networks.length,
    visibleRadioCount: networks.reduce((sum, network) => sum + (network.radios?.length || 0), 0),
    openOrLegacyNetworks,
    recommendations: recommendations.slice(0, 6),
    note: 'Análise defensiva de configuração e qualidade; não testa senhas, não injeta pacotes e não interfere nas redes visíveis.',
  };
}

export function enrichWifiDiagnostics(value) {
  const summary = {
    connected: parseWifiInterface(value?.interfaces),
    networks: parseVisibleWifiNetworks(value?.visibleNetworks),
  };
  return {
    ...value,
    summary,
    health: analyzeWifiPosture(summary),
  };
}
