import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildDefensiveChecklist,
  buildNetworkAiContext,
  classifyHostObservations,
  enrichNetworkAssessment,
  inferHostRole,
  parseArpTable,
  parseIpv4RoutePrint,
} from '../src/security/networkInsights.js';

test('parses Windows ARP neighbors without executable input', () => {
  const output = `Interface: 192.168.1.20 --- 0x8\n  Internet Address      Physical Address      Type\n  192.168.1.1           aa-bb-cc-dd-ee-ff     dynamic\n  192.168.1.50          10-20-30-40-50-60     dynamic\n`;
  assert.deepEqual(parseArpTable(output), [
    { interfaceAddress: '192.168.1.20', address: '192.168.1.1', mac: 'aa:bb:cc:dd:ee:ff', state: 'dynamic' },
    { interfaceAddress: '192.168.1.20', address: '192.168.1.50', mac: '10:20:30:40:50:60', state: 'dynamic' },
  ]);
});

test('parses and orders IPv4 default routes by metric', () => {
  const output = `0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.20     35\n0.0.0.0          0.0.0.0      10.0.0.1        10.0.0.5         5`;
  const routes = parseIpv4RoutePrint(output);
  assert.equal(routes[0].gateway, '10.0.0.1');
  assert.equal(routes[1].gateway, '192.168.1.1');
});

test('risk insights describe observed surface without claiming vulnerability', () => {
  const insight = classifyHostObservations({
    address: '192.168.1.10',
    ports: [
      { port: 23, protocol: 'tcp', state: 'open', service: 'telnet' },
      { port: 445, protocol: 'tcp', state: 'open', service: 'microsoft-ds' },
      { port: 80, protocol: 'tcp', state: 'open', service: 'http' },
    ],
  });
  assert.equal(insight.highestSeverity, 'high');
  assert.equal(insight.findings.length, 2);
  assert.match(insight.note, /Não confirmam vulnerabilidade/i);
  assert.ok(insight.findings.every(item => item.certainty === 'observed-surface-only'));
  assert.ok(insight.checklist.some(item => item.id === 'firewall-segmentation'));
});

test('device role inference remains explicitly heuristic', () => {
  const printer = inferHostRole({ ports: [{ port: 9100, state: 'open', protocol: 'tcp', service: 'jetdirect' }] });
  assert.equal(printer.id, 'printer');
  assert.equal(printer.confidence, 'low');
  assert.equal(printer.basis, 'heuristic-from-observed-services');

  const devops = inferHostRole({ ports: [
    { port: 2376, state: 'open', protocol: 'tcp', service: 'docker' },
    { port: 6443, state: 'open', protocol: 'tcp', service: 'https' },
  ] });
  assert.equal(devops.id, 'container-platform');
  assert.equal(devops.confidence, 'medium');
});

test('defensive checklist is review-oriented and bounded', () => {
  const checklist = buildDefensiveChecklist({ ports: [
    { port: 443, state: 'open', protocol: 'tcp', service: 'https' },
    { port: 3389, state: 'open', protocol: 'tcp', service: 'ms-wbt-server' },
  ] }, [{ id: 'rdp', severity: 'medium', title: 'RDP', recommendation: 'Restrinja origens administrativas.' }]);
  assert.ok(checklist.some(item => item.id === 'web-hardening'));
  assert.ok(checklist.some(item => item.id === 'remote-admin-hardening'));
  assert.ok(checklist.every(item => !/exploit|brute|credential attack/i.test(`${item.title} ${item.detail}`)));
  assert.ok(checklist.length <= 12);
});

test('enrichment summarizes findings across hosts', () => {
  const result = enrichNetworkAssessment({ hosts: [
    { address: '192.168.1.10', ports: [{ port: 2375, protocol: 'tcp', state: 'open', service: 'docker' }] },
    { address: '192.168.1.11', ports: [{ port: 80, protocol: 'tcp', state: 'open', service: 'http' }] },
  ] });
  assert.equal(result.insights.highestSeverity, 'critical');
  assert.equal(result.insights.counts.critical, 1);
  assert.equal(result.insights.hosts[0].role.id, 'container-platform');
});

test('AI context contains observations and defensive constraints, never command argv', () => {
  const assessment = enrichNetworkAssessment({
    preset: 'services', target: '192.168.1.10', completedAt: '2026-09-03T12:00:00.000Z', durationMs: 100,
    hosts: [{ address: '192.168.1.10', hostname: 'lab', ports: [{ port: 3389, protocol: 'tcp', state: 'open', service: 'ms-wbt-server', version: '' }] }],
  });
  const context = buildNetworkAiContext({
    project: 'Lab', authorizedScope: ['192.168.1.0/24'],
    overview: { host: 'pc', interfaces: [{ name: 'Ethernet', address: '192.168.1.20', cidr: '192.168.1.0/24' }] },
    diagnostics: { dnsServers: ['192.168.1.1'], defaultRoutes: [{ gateway: '192.168.1.1' }] },
    assessment, selectedHost: assessment.hosts[0],
  });
  assert.equal(context.purpose, 'authorized-defensive-network-assessment');
  assert.equal(context.selectedHost.address, '192.168.1.10');
  assert.equal(context.selectedHost.role.id, 'remote-admin');
  assert.ok(context.selectedHost.defensiveChecklist.length > 0);
  assert.equal(context.constraints.doNotGenerateCredentialAttacks, true);
  assert.equal(JSON.stringify(context).includes('argv'), false);
  assert.equal(JSON.stringify(context).includes('command'), false);
});
