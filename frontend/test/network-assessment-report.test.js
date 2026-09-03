import test from 'node:test';
import assert from 'node:assert/strict';
import { buildNetworkAssessmentMarkdown } from '../src/core/networkAssessmentReport.js';

test('markdown report explains observed surface without claiming vulnerabilities', () => {
  const report = buildNetworkAssessmentMarkdown({
    authorizedScope: ['192.168.1.0/24'],
    localNetwork: { host: 'lab-pc', defaultGateway: '192.168.1.1', dnsServers: ['192.168.1.1'], interfaces: [{ name: 'Ethernet', address: '192.168.1.20', cidr: '192.168.1.0/24' }] },
    assessment: { preset: 'services', target: '192.168.1.10', completedAt: '2026-09-03T12:00:00.000Z', durationMs: 1250, highestAttention: 'medium' },
    selectedHost: {
      address: '192.168.1.10', hostname: 'nas-lab', mac: 'aa:bb:cc:dd:ee:ff',
      role: { label: 'Possível servidor de arquivos / NAS', confidence: 'low' },
      ports: [{ port: 445, protocol: 'tcp', service: 'microsoft-ds', version: '' }],
      findings: [{ title: 'Compartilhamento SMB acessível', severity: 'medium', why: 'Superfície administrativa.', recommendation: 'Revise permissões.' }],
      defensiveChecklist: [{ title: 'Revisar compartilhamentos', detail: 'Confirme menor privilégio.' }],
    },
  });
  assert.match(report, /Relatório de Assessment de Rede/);
  assert.match(report, /Possível servidor de arquivos \/ NAS/);
  assert.match(report, /Porta aberta não equivale a vulnerabilidade/);
  assert.match(report, /Revisar compartilhamentos/);
});

test('report never serializes command execution fields supplied outside the schema', () => {
  const report = buildNetworkAssessmentMarkdown({
    command: 'bad', argv: ['--bad'], token: 'secret',
    assessment: { target: '192.168.1.10', preset: 'services' },
    selectedHost: { address: '192.168.1.10', command: 'bad', argv: ['bad'], ports: [] },
  });
  assert.equal(report.includes('argv'), false);
  assert.equal(report.includes('secret'), false);
  assert.equal(report.includes('command'), false);
});
