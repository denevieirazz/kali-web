import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  readinessClient,
  type ReadinessCheck,
  type ReadinessDeliveryState,
  type ReadinessEvidence,
  type ReadinessObservation,
  type ReadinessProfile,
  type ReadinessSnapshot,
  type ReadinessVerdict
} from '../../services/readinessClient';
import './SystemReadiness.css';

const PROFILES: Array<{ id: ReadinessProfile; label: string; detail: string }> = [
  { id: 'hybrid-dev', label: 'Híbrido atual', detail: 'Uso diário e desenvolvimento sem substituir a interface do Windows.' },
  { id: 'shell-preview', label: 'Prévia de shell', detail: 'CloudOS em tela cheia, com o Windows preservado como recuperação.' },
  { id: 'shell-candidate', label: 'Shell futuro', detail: 'Requisitos para uma futura substituição controlada da interface.' }
];

const GROUPS: Array<{ id: string; label: string; detail: string }> = [
  { id: 'runtime', label: 'Agente e runtime', detail: 'Serviços locais que sustentam a interface.' },
  { id: 'host', label: 'Host nativo', detail: 'WebView2, bridge e identidade da sessão.' },
  { id: 'boot', label: 'Inicialização', detail: 'Comportamento visual e modo de execução.' },
  { id: 'windows', label: 'Aplicativos Windows', detail: 'Catálogo, abertura e coordenação de janelas.' },
  { id: 'linux', label: 'Linux e WSL', detail: 'WSL 2, WSLg e distribuições instaladas.' },
  { id: 'storage', label: 'Dados e arquivos', detail: 'Persistência necessária para o workspace.' },
  { id: 'recovery', label: 'Recuperação', detail: 'Fallback, rollback e proteção contra falhas.' },
  { id: 'security', label: 'Segurança', detail: 'Limites de privilégio e proteção do sistema.' },
  { id: 'system', label: 'Outras verificações', detail: 'Sinais adicionais informados pelo agente.' }
];

const DELIVERY_LABELS: Record<ReadinessDeliveryState, string> = {
  implemented: 'Implementado',
  pending: 'Pendente',
  blocked: 'Bloqueado'
};

const OBSERVATION_LABELS: Record<ReadinessObservation, string> = {
  pass: 'Aprovado',
  warning: 'Atenção',
  fail: 'Falhou',
  unknown: 'Não verificado',
  'not-applicable': 'Não aplicável'
};

const SOURCE_LABELS: Record<string, string> = {
  agent: 'Agente local',
  backend: 'Agente local',
  'native-host': 'Host nativo',
  browser: 'Interface WebView2',
  policy: 'Política do CloudOS',
  windows: 'Windows',
  wsl: 'WSL'
};

const VERDICT_COPY: Record<ReadinessVerdict, { label: string; detail: string }> = {
  ready: { label: 'Pronto para este perfil', detail: 'Todas as verificações obrigatórias observadas foram aprovadas.' },
  conditional: { label: 'Pronto com ressalvas', detail: 'O perfil pode ser explorado, mas ainda existem alertas ou itens não concluídos.' },
  'not-ready': { label: 'Ainda não está pronto', detail: 'Um ou mais requisitos obrigatórios continuam pendentes, bloqueados ou falharam.' }
};

function safeEvidenceValue(evidence?: ReadinessEvidence) {
  if (!evidence) return 'Nenhuma evidência foi fornecida.';
  if (evidence.label) return evidence.label;
  const value = evidence.value;
  if (typeof value === 'boolean') return value ? 'Confirmado' : 'Não confirmado';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return value.slice(0, 180);
  if (Array.isArray(value)) {
    const safeItems = value.filter((item) => ['string', 'number', 'boolean'].includes(typeof item)).slice(0, 5);
    return safeItems.length ? safeItems.join(', ') : 'Evidência estruturada disponível';
  }
  if (value && typeof value === 'object') {
    const safeEntries = Object.entries(value as Record<string, unknown>)
      .filter(([key, item]) => !/(token|secret|password|credential|path|command)/i.test(key)
        && ['string', 'number', 'boolean'].includes(typeof item))
      .slice(0, 4)
      .map(([key, item]) => `${key}: ${String(item).slice(0, 80)}`);
    return safeEntries.length ? safeEntries.join(' · ') : 'Evidência estruturada disponível';
  }
  return evidence.code || 'Evidência registrada sem valor público.';
}

function formatTimestamp(value: string | undefined) {
  if (!value) return 'horário não informado';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return 'horário inválido';
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'medium'
  }).format(parsed);
}

function ReadinessCheckRow({ check, blocking }: { check: ReadinessCheck; blocking: boolean }) {
  return (
    <article className={`readiness-check observation-${check.observation}${blocking ? ' is-blocking' : ''}`}>
      <span className="readiness-check-marker" aria-hidden="true" />
      <div className="readiness-check-copy">
        <div className="readiness-check-heading">
          <h3>{check.label}</h3>
          {blocking && <span className="readiness-blocker-label">Impede este perfil</span>}
        </div>
        <p>{check.detail}</p>
        <div className="readiness-evidence">
          <span><b>Origem</b>{SOURCE_LABELS[check.source] || check.source}</span>
          <span><b>Evidência</b>{safeEvidenceValue(check.evidence)}</span>
          {check.evidence?.code && <span><b>Código</b>{check.evidence.code}</span>}
          {check.evidence?.observedAt && <span><b>Observado</b>{formatTimestamp(check.evidence.observedAt)}</span>}
        </div>
      </div>
      <div className="readiness-check-states" aria-label="Estados da verificação">
        <span className={`delivery-chip delivery-${check.deliveryState}`}>{DELIVERY_LABELS[check.deliveryState]}</span>
        <span className={`observation-chip observation-${check.observation}`}>{OBSERVATION_LABELS[check.observation]}</span>
      </div>
    </article>
  );
}

function LoadingState() {
  return (
    <div className="readiness-loading" role="status" aria-live="polite">
      <span className="readiness-spinner" aria-hidden="true" />
      <div><strong>Verificando o computador</strong><p>O CloudOS está reunindo evidências do agente, do host nativo e desta interface.</p></div>
    </div>
  );
}

export default function SystemReadiness() {
  const [profile, setProfile] = useState<ReadinessProfile>('shell-preview');
  const [snapshot, setSnapshot] = useState<ReadinessSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const requestSequence = useRef(0);

  const scan = useCallback(async (targetProfile: ReadinessProfile) => {
    const requestId = ++requestSequence.current;
    setLoading(true);
    setError(null);
    try {
      const nextSnapshot = await readinessClient.scan(targetProfile, true);
      if (requestId === requestSequence.current) setSnapshot(nextSnapshot);
    } catch (scanError) {
      if (requestId === requestSequence.current) {
        setError(scanError instanceof Error ? scanError.message : 'A verificação não pôde ser concluída.');
      }
    } finally {
      if (requestId === requestSequence.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    scan(profile);
  }, [profile, scan]);

  const groupedChecks = useMemo(() => {
    const checks = snapshot?.checks || [];
    const knownGroups = new Set(GROUPS.map((group) => group.id));
    return GROUPS.map((group) => ({ ...group, checks: checks.filter((check) => check.group === group.id) }))
      .concat(checks
        .filter((check) => !knownGroups.has(check.group))
        .reduce<Array<{ id: string; label: string; detail: string; checks: ReadinessCheck[] }>>((groups, check) => {
          let group = groups.find((item) => item.id === check.group);
          if (!group) {
            group = { id: check.group, label: check.group, detail: 'Verificações adicionais do agente.', checks: [] };
            groups.push(group);
          }
          group.checks.push(check);
          return groups;
        }, []))
      .filter((group) => group.checks.length);
  }, [snapshot]);

  const blockers = new Set(snapshot?.summary.blockingCheckIds || []);
  const verdict = snapshot?.summary.verdict || 'not-ready';
  const verdictCopy = VERDICT_COPY[verdict];
  const selectedProfile = PROFILES.find((item) => item.id === profile)!;
  const shellCandidate = profile === 'shell-candidate';

  return (
    <section className="system-readiness" aria-labelledby="readiness-title">
      <div className="readiness-profile-strip" role="tablist" aria-label="Perfil de prontidão">
        {PROFILES.map((item) => (
          <button
            type="button"
            role="tab"
            aria-selected={profile === item.id}
            className={profile === item.id ? 'active' : ''}
            key={item.id}
            onClick={() => setProfile(item.id)}
          >
            <strong>{item.label}</strong>
            <small>{item.detail}</small>
          </button>
        ))}
      </div>

      <article className={`readiness-verdict verdict-${verdict}${shellCandidate ? ' shell-candidate' : ''}`} aria-live="polite">
        <div className="readiness-verdict-symbol" aria-hidden="true">{shellCandidate ? '⌁' : verdict === 'ready' ? '✓' : verdict === 'conditional' ? '!' : '×'}</div>
        <div className="readiness-verdict-copy">
          <span className="panel-kicker">{selectedProfile.label.toUpperCase()}</span>
          <h2 id="readiness-title">{shellCandidate ? 'Modo shell futuro bloqueado' : verdictCopy.label}</h2>
          <p>{shellCandidate
            ? 'Esta versão apenas mede a preparação. Ela não troca o shell, não altera o registro do Windows e não remove a interface de recuperação.'
            : verdictCopy.detail}</p>
          <div className="readiness-summary-line">
            <span><b>{snapshot?.summary.counts.passed ?? 0}</b> aprovadas</span>
            <span><b>{snapshot?.summary.counts.warnings ?? 0}</b> alertas</span>
            <span><b>{snapshot?.summary.counts.pending ?? 0}</b> pendentes</span>
            <span><b>{snapshot?.summary.blockingCheckIds.length ?? 0}</b> bloqueadores</span>
          </div>
        </div>
        <div className="readiness-verdict-actions">
          <small>Última leitura<br /><b>{formatTimestamp(snapshot?.generatedAt)}</b></small>
          <button type="button" className="secondary-button" onClick={() => scan(profile)} disabled={loading}>
            {loading ? 'Verificando…' : 'Verificar novamente'}
          </button>
        </div>
      </article>

      {error && <div className="readiness-error" role="alert"><strong>Não foi possível concluir a leitura</strong><span>{error}</span></div>}
      {loading && !snapshot ? <LoadingState /> : (
        <div className={loading ? 'readiness-content is-refreshing' : 'readiness-content'} aria-busy={loading}>
          {groupedChecks.map((group) => (
            <section className="readiness-group" key={group.id} aria-labelledby={`readiness-group-${group.id}`}>
              <header>
                <div><h2 id={`readiness-group-${group.id}`}>{group.label}</h2><p>{group.detail}</p></div>
                <span>{group.checks.length} {group.checks.length === 1 ? 'verificação' : 'verificações'}</span>
              </header>
              <div className="readiness-check-list">
                {group.checks.map((check) => <ReadinessCheckRow key={check.id} check={check} blocking={blockers.has(check.id)} />)}
              </div>
            </section>
          ))}

          <section className="readiness-limitations" aria-labelledby="readiness-limitations-title">
            <header><span className="panel-kicker">FRONTEIRAS CONHECIDAS</span><h2 id="readiness-limitations-title">O que esta preparação não promete</h2><p>Limites explícitos evitam que a interface apresente compatibilidade que o computador não confirmou.</p></header>
            <div>
              {(snapshot?.limitations || []).map((limitation) => (
                <article key={limitation.id}>
                  <span aria-hidden="true">i</span>
                  <div><strong>{limitation.title}</strong><p>{limitation.detail}</p><small>{SOURCE_LABELS[limitation.source] || limitation.source}</small></div>
                </article>
              ))}
            </div>
          </section>

          <div className="readiness-safety-note">
            <span aria-hidden="true">⌂</span>
            <div><strong>Preparação reversível</strong><p>Não há botão de ativação nesta tela. Explorer, serviços do Windows e caminhos de recuperação permanecem intactos.</p></div>
          </div>
        </div>
      )}
    </section>
  );
}
