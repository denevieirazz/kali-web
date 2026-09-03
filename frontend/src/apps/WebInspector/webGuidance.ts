export type GuidedSeverity = 'info' | 'low' | 'medium' | 'high' | 'critical';

export type GuidedFinding = {
  id: string;
  severity: GuidedSeverity;
  title: string;
  evidence: string;
  recommendation: string;
};

export type GuidedTab = 'overview' | 'headers' | 'cookies' | 'redirects' | 'evidence';

export type GuidedAction = {
  rank: number;
  severity: GuidedSeverity;
  title: string;
  whyItMatters: string;
  evidence: string;
  action: string;
  openTab: GuidedTab;
};

const ORDER: GuidedSeverity[] = ['info', 'low', 'medium', 'high', 'critical'];
const SCORE_WEIGHT: Record<GuidedSeverity, number> = {
  info: 1,
  low: 4,
  medium: 12,
  high: 24,
  critical: 36,
};

function plainLanguage(id: string, fallback: string) {
  if (id === 'transport-http') return 'A página terminou sem HTTPS. Isso reduz a proteção do tráfego entre navegador e servidor.';
  if (id === 'hsts-missing') return 'O navegador não recebeu uma ordem para continuar usando HTTPS nas próximas visitas.';
  if (id === 'csp-missing') return 'A resposta não anunciou uma política clara sobre quais scripts, frames e conteúdos o navegador pode carregar.';
  if (id === 'nosniff-missing') return 'O navegador não recebeu a instrução explícita para respeitar o tipo de conteúdo informado pelo servidor.';
  if (id === 'frame-policy-missing') return 'Não foi observada uma regra explícita dizendo quem pode colocar essa página dentro de um frame.';
  if (id.startsWith('cookie-secure-')) return 'Esse cookie não declarou que deve trafegar somente por HTTPS.';
  if (id.startsWith('cookie-httponly-')) return 'Esse cookie não declarou bloqueio de leitura por JavaScript. Confirme se a aplicação realmente precisa dessa leitura.';
  if (id.startsWith('cookie-samesite-')) return 'Esse cookie não declarou uma política SameSite explícita para navegação entre sites.';
  if (id === 'server-error') return 'O servidor respondeu com erro 5xx. Antes de procurar falha de segurança, confirme disponibilidade e logs.';
  if (id === 'cors-wildcard') return 'A resposta declarou acesso por qualquer origem. Isso pode ser intencional, mas merece confirmação no contexto do recurso.';
  if (id === 'powered-by') return 'O servidor anunciou tecnologia usada pela aplicação. Isso é exposição de informação, não exploração confirmada.';
  return fallback;
}

function tabForFinding(id: string): GuidedTab {
  if (id.startsWith('cookie-')) return 'cookies';
  if (id === 'transport-http') return 'redirects';
  if (id === 'server-error') return 'overview';
  if (id.includes('tls') || id === 'hsts-missing') return 'overview';
  if (id.includes('header') || id.includes('csp') || id.includes('cors') || id.includes('frame') || id.includes('nosniff') || id.includes('powered-by') || id.includes('referrer')) return 'headers';
  return 'overview';
}

export function computeWebAttentionScore(findings: GuidedFinding[]) {
  const raw = findings.reduce((total, finding) => total + SCORE_WEIGHT[finding.severity], 0);
  return Math.min(100, raw);
}

export function getWebAttentionBand(score: number) {
  if (score >= 60) return { label: 'prioridade alta', tone: 'high' as const, message: 'Há várias observações que merecem revisão antes de considerar esta coleta tranquila.' };
  if (score >= 30) return { label: 'revisar agora', tone: 'medium' as const, message: 'Existem pontos relevantes. Comece pelas prioridades abaixo e valide no servidor/CDN.' };
  if (score >= 10) return { label: 'atenção moderada', tone: 'low' as const, message: 'A superfície parece relativamente organizada, mas ainda há itens de higiene para confirmar.' };
  return { label: 'baixa atenção', tone: 'ok' as const, message: 'Poucas observações foram coletadas. Isso não equivale a certificação de segurança.' };
}

export function buildGuidedActions(findings: GuidedFinding[], maxActions = 4): GuidedAction[] {
  return [...findings]
    .sort((left, right) => ORDER.indexOf(right.severity) - ORDER.indexOf(left.severity))
    .slice(0, Math.max(1, Math.min(maxActions, 6)))
    .map((finding, index) => ({
      rank: index + 1,
      severity: finding.severity,
      title: finding.title,
      whyItMatters: plainLanguage(finding.id, finding.evidence),
      evidence: finding.evidence,
      action: finding.recommendation,
      openTab: tabForFinding(finding.id),
    }));
}

export function highestGuidedSeverity(findings: GuidedFinding[]): GuidedSeverity {
  return findings.reduce<GuidedSeverity>((highest, finding) =>
    ORDER.indexOf(finding.severity) > ORDER.indexOf(highest) ? finding.severity : highest, 'info');
}
