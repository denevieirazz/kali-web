import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd(), 'test-results/drone');
const findingsFile = path.join(root, 'findings.json');
const snapshotsFile = path.join(root, 'snapshots.json');
const reportFile = path.resolve(process.cwd(), 'DRONE_REPORT.md');
const severities = ['CRÍTICO', 'ALTO', 'MÉDIO', 'BAIXO'];

const findings = fs.existsSync(findingsFile) ? JSON.parse(fs.readFileSync(findingsFile, 'utf8')) : [{
  id: 'DRONE-INFRA-0001',
  severity: 'CRÍTICO',
  category: 'drone',
  title: 'Drone terminou sem findings.json',
  evidence: 'A patrulha não produziu o arquivo estruturado de achados. Tratar como falha fechada de infraestrutura até investigação.',
}];
const snapshots = fs.existsSync(snapshotsFile) ? JSON.parse(fs.readFileSync(snapshotsFile, 'utf8')) : [];
const human = value => {
  if (value === null || value === undefined) return 'n/d';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  return `${(value / 1024 / 1024).toFixed(1)} MiB`;
};
const esc = value => String(value).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');

const counts = Object.fromEntries(severities.map(severity => [severity, findings.filter(item => item.severity === severity).length]));
const lines = [
  '# DRONE_REPORT.md', '',
  '## CloudOS Workflow Drone', '',
  `**Branch:** \`stabilization/cloudos-workflow-batch-4\`  `,
  `**Commit:** \`${process.env.GITHUB_SHA || 'local'}\`  `,
  `**Execução:** ${new Date().toISOString()}  `,
  `**Achados:** ${findings.length} (${counts['CRÍTICO']} crítico, ${counts['ALTO']} alto, ${counts['MÉDIO']} médio, ${counts['BAIXO']} baixo)`, '',
  '> Drone de auditoria: caça defeitos de runtime, rede, UX, memória, Terminal e Workflow. Não implementa nem valida features novas.', '',
];

if (!findings.length) lines.push('**Nenhum defeito reproduzível encontrado nesta patrulha.**', '');

for (const severity of severities) {
  lines.push(`# ${severity}`, '');
  const items = findings.filter(item => item.severity === severity);
  if (!items.length) {
    lines.push('Nenhum achado.', '');
    continue;
  }
  for (const item of items) {
    lines.push(`## ${item.id} — ${item.title}`, '', `**Categoria:** ${item.category}`, '', '**Evidência:**', '', '```text', String(item.evidence || '').slice(0, 12000), '```', '');
    if (item.screenshot) lines.push(`**Screenshot:** \`${item.screenshot}\``, '');
  }
}

lines.push('# TELEMETRIA', '', '| Snapshot | Heap usado | Heap total | DOM nodes | Listeners | RO | MO | Timers | Intervals | localStorage | sessionStorage | Janelas | Tabs Terminal |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
for (const item of snapshots) {
  lines.push(`| ${esc(item.label)} | ${human(item.heapUsed)} | ${human(item.heapTotal)} | ${item.domNodes ?? 'n/d'} | ${item.jsEventListeners ?? 'n/d'} | ${item.resizeObservers ?? 'n/d'} | ${item.mutationObservers ?? 'n/d'} | ${item.timeouts ?? 'n/d'} | ${item.intervals ?? 'n/d'} | ${human(item.localStorageBytes)} | ${human(item.sessionStorageBytes)} | ${item.windows ?? 'n/d'} | ${item.terminalTabs ?? 'n/d'} |`);
}

lines.push('', '# GATE', '');
if (counts['CRÍTICO'] || counts['ALTO']) lines.push(`**FALHOU:** ${counts['CRÍTICO']} crítico(s) e ${counts['ALTO']} alto(s) exigem revisão.`);
else if (counts['MÉDIO'] || counts['BAIXO']) lines.push('**ALERTA:** somente achados médios/baixos.');
else lines.push('**PASSOU:** nenhum achado.');

fs.writeFileSync(reportFile, `${lines.join('\n')}\n`, 'utf8');
console.log(`DRONE_REPORT=${reportFile}`);
console.log(`DRONE_COUNTS critical=${counts['CRÍTICO']} high=${counts['ALTO']} medium=${counts['MÉDIO']} low=${counts['BAIXO']}`);

if (process.argv.includes('--gate') && (counts['CRÍTICO'] || counts['ALTO'])) process.exit(1);
