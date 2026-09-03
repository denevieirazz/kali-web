import { useMemo } from 'react';
import {
  buildGuidedActions,
  computeWebAttentionScore,
  getWebAttentionBand,
  highestGuidedSeverity,
  type GuidedFinding,
  type GuidedTab,
} from './webGuidance';

type Props = {
  findings: GuidedFinding[];
  status: number;
  hasTls: boolean;
  onOpenTab: (tab: GuidedTab) => void;
  onCopyForAi: () => void;
  onExportEvidence: () => void;
};

const LABEL = {
  info: 'info',
  low: 'baixo',
  medium: 'médio',
  high: 'alto',
  critical: 'crítico',
};

export default function WebOperatorCoach({ findings, status, hasTls, onOpenTab, onCopyForAi, onExportEvidence }: Props) {
  const score = useMemo(() => computeWebAttentionScore(findings), [findings]);
  const band = useMemo(() => getWebAttentionBand(score), [score]);
  const actions = useMemo(() => buildGuidedActions(findings), [findings]);
  const highest = useMemo(() => highestGuidedSeverity(findings), [findings]);

  return <section className={`wi-coach wi-coach--${band.tone}`} aria-label="Modo assistido para técnico">
    <div className="wi-coach-head">
      <div>
        <small>Modo Assistido · CloudOS decide a ordem</small>
        <h3>O que você deve olhar primeiro</h3>
        <p>{band.message}</p>
      </div>
      <div className="wi-coach-score" title="Score de triagem; não é probabilidade de exploração">
        <strong>{score}</strong><span>/100</span><small>atenção</small>
      </div>
    </div>

    <div className="wi-coach-strip">
      <article><small>Prioridade</small><strong>{band.label}</strong><span>triagem automática</span></article>
      <article><small>Maior nível</small><strong>{LABEL[highest]}</strong><span>{findings.length} observação(ões)</span></article>
      <article><small>HTTP</small><strong>{status}</strong><span>{status >= 500 ? 'comece por disponibilidade' : 'resposta coletada'}</span></article>
      <article><small>Transporte</small><strong>{hasTls ? 'TLS ativo' : 'sem TLS final'}</strong><span>{hasTls ? 'certificado validado' : 'revisar HTTPS'}</span></article>
    </div>

    {actions.length ? <div className="wi-coach-actions">
      {actions.map(action => <article key={`${action.rank}-${action.title}`}>
        <b>{action.rank}</b>
        <div>
          <div className="wi-coach-action-title"><strong>{action.title}</strong><span className={`wi-risk wi-risk--${action.severity}`}>{LABEL[action.severity]}</span></div>
          <p><em>Por que importa:</em> {action.whyItMatters}</p>
          <p><em>Evidência:</em> {action.evidence}</p>
          <small><em>Faça agora:</em> {action.action}</small>
        </div>
        <button type="button" onClick={() => onOpenTab(action.openTab)}>Abrir evidência</button>
      </article>)}
    </div> : <div className="wi-coach-clear">
      <strong>Nada urgente apareceu nesta coleta.</strong>
      <p>Continue com validação funcional e compare uma nova coleta após mudanças. Ausência de finding não prova segurança total.</p>
    </div>}

    <div className="wi-coach-footer">
      <div><strong>Não sabe o próximo passo?</strong><span>Copie o contexto e peça para a IA explicar somente as evidências observadas e a correção mais segura.</span></div>
      <button type="button" className="wi-primary" onClick={onCopyForAi}>Explicar com IA</button>
      <button type="button" onClick={onExportEvidence}>Salvar evidência</button>
    </div>
    <p className="wi-coach-note">Score de atenção = priorização de higiene observada. Não é CVSS, não confirma vulnerabilidade e não autoriza exploração.</p>
  </section>;
}
