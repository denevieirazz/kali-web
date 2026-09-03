import test from 'node:test';
import assert from 'node:assert/strict';
import { enrichWifiDiagnostics, parseVisibleWifiNetworks, parseWifiInterface } from '../src/security/wifiInsights.js';

test('parses connected Wi-Fi interface in English netsh output', () => {
  const parsed = parseWifiInterface(`Name                   : Wi-Fi\nState                  : connected\nSSID                   : LabNet\nBSSID                  : aa:bb:cc:dd:ee:ff\nSignal                 : 88%\nChannel                : 6\nRadio type             : 802.11ax\nAuthentication         : WPA2-Personal`);
  assert.equal(parsed.name, 'Wi-Fi');
  assert.equal(parsed.ssid, 'LabNet');
  assert.equal(parsed.signal, '88%');
  assert.equal(parsed.channel, '6');
});

test('parses connected Wi-Fi interface with Portuguese labels', () => {
  const parsed = parseWifiInterface(`Nome                   : Wi-Fi\nEstado                 : conectado\nSSID                   : MinhaRede\nSinal                  : 74%\nCanal                  : 11\nAutenticação           : WPA3-Pessoal`);
  assert.equal(parsed.name, 'Wi-Fi');
  assert.equal(parsed.state, 'conectado');
  assert.equal(parsed.ssid, 'MinhaRede');
  assert.equal(parsed.authentication, 'WPA3-Pessoal');
});

test('parses visible SSIDs and radio observations without active probing', () => {
  const networks = parseVisibleWifiNetworks(`SSID 1 : LabNet\n    Authentication         : WPA2-Personal\n    Encryption             : CCMP\n    BSSID 1                 : aa:bb:cc:dd:ee:ff\n         Signal             : 91%\n         Radio type         : 802.11ax\n         Channel            : 36\nSSID 2 : Guest\n    Authentication         : Open\n    BSSID 1                 : 11:22:33:44:55:66\n         Signal             : 42%\n         Channel            : 1`);
  assert.equal(networks.length, 2);
  assert.equal(networks[0].ssid, 'LabNet');
  assert.equal(networks[0].radios[0].signal, '91%');
  assert.equal(networks[0].radios[0].channel, '36');
  assert.equal(networks[1].authentication, 'Open');
});

test('wifi enrichment preserves read-only note and adds summary', () => {
  const result = enrichWifiDiagnostics({
    available: true,
    note: 'Diagnóstico somente leitura',
    interfaces: 'SSID : LabNet\nSignal : 80%',
    visibleNetworks: 'SSID 1 : LabNet\n BSSID 1 : aa:bb:cc:dd:ee:ff\n Signal : 80%\n Channel : 6',
  });
  assert.equal(result.note, 'Diagnóstico somente leitura');
  assert.equal(result.summary.connected.ssid, 'LabNet');
  assert.equal(result.summary.networks[0].ssid, 'LabNet');
});
