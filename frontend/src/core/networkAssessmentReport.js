function text(value, fallback = 'não informado') {
  const clean = typeof value === 'string' ? value.replace(/[\u0000-\u001f]/g, ' ').trim() : '';
  return clean || fallback;
}

function lineList(items) {
  return items.length ? items.map(item => `- ${item}`).join('\n') : '- Nenhum item registrado.';
}

export function buildNetworkAssessmentMarkdown(context) {
  const assessment = context?.assessment || {};
  const network = context?.localNetwork || {};
  const host = context?.selectedHost || null;
  const changes = context?.latestComparableChange || null;
  const generatedAt = new Date().toISOString();
  const sections = [
    '# CloudOS — Relatório de Assessment de Rede',
    '',
    `Gerado em: ${generatedAt}`,
    'Finalidade: avaliação defensiva/autorizada. Este relatório descreve superfície observada e não confirma vulnerabilidades.',
    '',
    '## Escopo',
    lineList(Array.isArray(context?.authorizedScope) ? context.authorizedScope.map(item => text(item)) : []),
    '',
    '## Rede local',
    `- Host de coleta: ${text(network.host)}`,
    `- Gateway padrão: ${text(network.defaultGateway)}`,
    `- DNS: ${Array.isArray(network.dnsServers) && network.dnsServers.length ? network.dnsServers.map(item => text(item)).join(', ') : 'não informado'}`,
    `- Interfaces: ${Array.isArray(network.interfaces) && network.interfaces.length ? network.interfaces.map(item => `${text(item.name)} ${text(item.address)}${item.cidr ? ` (${text(item.cidr)})` : ''}`).join('; ') : 'não informado'}`,
    '',
    '## Avaliação executada',
    `- Preset: ${text(assessment.preset)}`,
    `- Alvo: ${text(assessment.target)}`,
    `- Concluída em: ${text(assessment.completedAt)}`,
    `- Duração: ${Number.isFinite(Number(assessment.durationMs)) ? `${Number(assessment.durationMs)} ms` : 'não informada'}`,
    `- Maior nível de atenção: ${text(assessment.highestAttention, 'informativo')}`,
  ];

  if (host) {
    sections.push('', '## Dispositivo selecionado');
    sections.push(`- IP: ${text(host.address)}`);
    sections.push(`- Hostname: ${text(host.hostname)}`);
    sections.push(`- MAC: ${text(host.mac)}`);
    sections.push(`- Função provável: ${text(host.role?.label, 'não classificada')} (${text(host.role?.confidence, 'confiança não informada')}; inferência heurística)`);
    sections.push('', '### Serviços observados');
    const ports = Array.isArray(host.ports) ? host.ports : [];
    sections.push(lineList(ports.map(port => `${Number(port.port) || '?'} / ${text(port.protocol, 'tcp')} — ${text(port.service, 'serviço não identificado')}${port.version ? ` — ${text(port.version)}` : ''}`)));
    sections.push('', '### Indicadores de atenção');
    const findings = Array.isArray(host.findings) ? host.findings : [];
    if (findings.length) {
      for (const finding of findings) {
        sections.push(`- **${text(finding.title)}** [${text(finding.severity, 'info')}]: ${text(finding.why)} Recomendação: ${text(finding.recommendation)}`);
      }
    } else sections.push('- Nenhum indicador adicional gerado pela classificação de superfície.');
    sections.push('', '### Checklist defensivo');
    const checklist = Array.isArray(host.defensiveChecklist) ? host.defensiveChecklist : [];
    sections.push(lineList(checklist.map(item => `[ ] ${text(item.title)} — ${text(item.detail)}`)));
  }

  if (changes?.comparable) {
    sections.push('', '## Mudanças desde a avaliação comparável anterior');
    sections.push(`- Hosts adicionados: ${changes.addedHosts?.length ? changes.addedHosts.map(item => text(item)).join(', ') : 'nenhum'}`);
    sections.push(`- Hosts removidos: ${changes.removedHosts?.length ? changes.removedHosts.map(item => text(item)).join(', ') : 'nenhum'}`);
    for (const change of changes.changedHosts || []) {
      const opened = change.openedPorts?.length ? `novas portas: ${change.openedPorts.join(', ')}` : '';
      const closed = change.closedPorts?.length ? `portas ausentes agora: ${change.closedPorts.join(', ')}` : '';
      sections.push(`- ${text(change.address)}: ${[opened, closed, change.onlineChanged ? `estado online: ${change.online ? 'ativo' : 'inativo'}` : ''].filter(Boolean).join('; ') || 'sem alteração descrita'}`);
    }
  }

  sections.push('', '## Limites da interpretação', '- Porta aberta não equivale a vulnerabilidade.', '- Versão detectada remotamente pode ser aproximada.', '- Função do dispositivo é uma hipótese baseada nos serviços observados.', '- Próximos passos recomendados: confirmar proprietário, configuração, patching, firewall/segmentação e evidências adicionais dentro do escopo autorizado.', '');
  return sections.join('\n');
}
