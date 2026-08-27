import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  NativeHostError,
  nativeHostBridge,
  type NativeInstallerArtifact,
  type NativeInstallerPrepareResult,
  type NativeInstallerReadiness,
} from '../../services/nativeHostBridge';
import './WindowsInstaller.css';

function formatBytes(value: number) {
  if (!Number.isFinite(value) || value < 0) return '—';
  if (value < 1024) return `${value} B`;
  const units = ['KB', 'MB', 'GB'];
  let size = value / 1024;
  let unit = units[0];
  for (let index = 1; index < units.length && size >= 1024; index += 1) {
    size /= 1024;
    unit = units[index];
  }
  return `${size >= 10 ? size.toFixed(1) : size.toFixed(2)} ${unit}`;
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'Data indisponível' : date.toLocaleString();
}

function trustLabel(artifact: NativeInstallerArtifact) {
  switch (artifact.trust) {
    case 'Trusted': return artifact.publisher ? `Assinado · ${artifact.publisher}` : 'Assinatura confiável';
    case 'Unsigned': return 'Sem assinatura confiável';
    case 'Untrusted': return 'Assinatura recusada pelo Windows';
    case 'VerificationUnavailable': return 'Verificação de assinatura indisponível';
  }
}

function readinessLabel(readiness?: NativeInstallerReadiness) {
  if (!readiness) return null;
  switch (readiness.status) {
    case 'Ready': return 'Capability preparada';
    case 'BlockedByPolicy': return 'Confirmação explícita necessária';
    case 'ArtifactChanged': return 'Arquivo alterado depois do download';
    case 'ArtifactMissing': return 'Arquivo não está mais disponível';
    case 'UnsupportedFormat': return 'Formato ainda não suportado';
    case 'BrokerRequired': return 'Broker privilegiado necessário';
  }
}

export default function WindowsInstaller() {
  const [artifacts, setArtifacts] = useState<NativeInstallerArtifact[]>([]);
  const [brokerAvailable, setBrokerAvailable] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busyArtifactId, setBusyArtifactId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingApproval, setPendingApproval] = useState<NativeInstallerArtifact | null>(null);
  const [readinessByArtifact, setReadinessByArtifact] = useState<Record<string, NativeInstallerReadiness>>({});
  const [preparedByArtifact, setPreparedByArtifact] = useState<Record<string, NativeInstallerPrepareResult>>({});

  const loadArtifacts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      if (!nativeHostBridge.available) {
        throw new NativeHostError('NATIVE_HOST_UNAVAILABLE', 'O Host nativo do CloudOS não está ativo.');
      }
      const result = await nativeHostBridge.listInstallerArtifacts();
      setArtifacts(result.artifacts);
      setBrokerAvailable(result.elevationBrokerAvailable);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'O catálogo de instaladores não pôde ser carregado.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadArtifacts();
  }, [loadArtifacts]);

  const prepare = useCallback(async (artifact: NativeInstallerArtifact, allowUntrusted: boolean) => {
    if (preparedByArtifact[artifact.artifactId]?.readiness.status === 'Ready') return;
    setBusyArtifactId(artifact.artifactId);
    setError(null);
    try {
      const result = await nativeHostBridge.prepareInstaller(artifact.artifactId, allowUntrusted);
      setReadinessByArtifact(current => ({ ...current, [artifact.artifactId]: result.readiness }));

      if (result.readiness.status === 'BlockedByPolicy' && !allowUntrusted) {
        setPendingApproval(artifact);
        return;
      }

      setPendingApproval(current => current?.artifactId === artifact.artifactId ? null : current);
      if (result.readiness.status === 'Ready') {
        if (!result.capabilityId || !result.expiresAtUtc) {
          throw new Error('O Host retornou uma capability incompleta e ela foi recusada pela interface.');
        }
        setPreparedByArtifact(current => ({ ...current, [artifact.artifactId]: result }));
      }
    } catch (prepareError) {
      setError(prepareError instanceof Error ? prepareError.message : 'O instalador não pôde ser preparado.');
    } finally {
      setBusyArtifactId(null);
    }
  }, [preparedByArtifact]);

  const summary = useMemo(() => ({
    total: artifacts.length,
    trusted: artifacts.filter(artifact => artifact.trust === 'Trusted').length,
    pending: artifacts.filter(artifact => artifact.trust !== 'Trusted').length,
    prepared: Object.values(preparedByArtifact).filter(item => item.readiness.status === 'Ready').length,
  }), [artifacts, preparedByArtifact]);

  return (
    <section className="windows-installer">
      <header className="windows-installer__header">
        <div>
          <p className="windows-installer__eyebrow">CloudOS Windows Runtime</p>
          <h1>Instaladores baixados</h1>
          <p>
            Catálogo nativo com SHA-256, WinVerifyTrust e capabilities one-shot. Este gate valida e prepara o arquivo;
            ele ainda não inicia o instalador.
          </p>
        </div>
        <button type="button" className="windows-installer__refresh" onClick={() => void loadArtifacts()} disabled={loading}>
          {loading ? 'Atualizando…' : '↻ Atualizar'}
        </button>
      </header>

      <div className="windows-installer__metrics">
        <article><span>Catalogados</span><strong>{summary.total}</strong><small>Downloads gerenciados</small></article>
        <article><span>Confiáveis</span><strong>{summary.trusted}</strong><small>Publisher verificado</small></article>
        <article><span>Requer atenção</span><strong>{summary.pending}</strong><small>Sem confiança automática</small></article>
        <article><span>Preparados</span><strong>{summary.prepared}</strong><small>Capability desta sessão</small></article>
      </div>

      <div className="windows-installer__boundary" role="status">
        <div>
          <strong>Execução continua bloqueada neste gate</strong>
          <p>EXE só poderá avançar pelo mesmo Job/quarentena/captured-surface do runtime Windows. MSI permanece broker-only até qualificação física.</p>
        </div>
        <span className={brokerAvailable ? 'windows-installer__broker windows-installer__broker--ready' : 'windows-installer__broker'}>
          Broker: {brokerAvailable ? 'disponível' : 'indisponível'}
        </span>
      </div>

      {error && <div className="windows-installer__error" role="alert">{error}</div>}

      {pendingApproval && (
        <div className="windows-installer__approval" role="alertdialog" aria-labelledby="installer-approval-title">
          <div>
            <strong id="installer-approval-title">Confirmação de publisher necessária</strong>
            <p>
              <b>{pendingApproval.fileName}</b> não possui confiança automática do Windows ({pendingApproval.trust}).
              Confirmar permite somente criar uma capability temporária e revalidada; não executa o arquivo.
            </p>
          </div>
          <div className="windows-installer__approval-actions">
            <button type="button" className="windows-installer__secondary" onClick={() => setPendingApproval(null)}>
              Cancelar
            </button>
            <button
              type="button"
              onClick={() => void prepare(pendingApproval, true)}
              disabled={busyArtifactId === pendingApproval.artifactId}
            >
              {busyArtifactId === pendingApproval.artifactId ? 'Revalidando…' : 'Confirmar preparo não confiável'}
            </button>
          </div>
        </div>
      )}

      <div className="windows-installer__list" aria-busy={loading}>
        {!loading && artifacts.length === 0 && (
          <div className="windows-installer__empty">
            <strong>Nenhum instalador catalogado</strong>
            <p>Downloads .exe/.msi concluídos pelo Navegador CloudOS aparecerão aqui automaticamente.</p>
          </div>
        )}

        {artifacts.map(artifact => {
          const readiness = readinessByArtifact[artifact.artifactId];
          const prepared = preparedByArtifact[artifact.artifactId];
          const ready = prepared?.readiness.status === 'Ready';
          const busy = busyArtifactId === artifact.artifactId;
          return (
            <article className="windows-installer__item" key={artifact.artifactId}>
              <div className="windows-installer__icon" aria-hidden="true">▣</div>
              <div className="windows-installer__item-main">
                <div className="windows-installer__item-heading">
                  <div>
                    <strong>{artifact.fileName}</strong>
                    <span>{artifact.kind === 'WindowsInstallerPackage' ? 'MSI' : artifact.kind === 'WindowsExecutable' ? 'EXE' : artifact.kind}</span>
                  </div>
                  <span className={`windows-installer__trust windows-installer__trust--${artifact.trust.toLowerCase()}`}>
                    {artifact.trust}
                  </span>
                </div>
                <p>{trustLabel(artifact)}</p>
                <div className="windows-installer__meta">
                  <span>{formatBytes(artifact.sizeBytes)}</span>
                  <span>SHA-256 {artifact.sha256.slice(0, 12)}…</span>
                  <span>{formatDate(artifact.registeredAtUtc)}</span>
                </div>
                {readiness && (
                  <div className={`windows-installer__readiness windows-installer__readiness--${readiness.status.toLowerCase()}`}>
                    <strong>{readinessLabel(readiness)}</strong>
                    {readiness.reason && <span>{readiness.reason}</span>}
                  </div>
                )}
                {ready && prepared.expiresAtUtc && (
                  <div className="windows-installer__ready-note">
                    Capability one-shot emitida até {formatDate(prepared.expiresAtUtc)}. Nenhum processo foi iniciado.
                  </div>
                )}
              </div>
              <div className="windows-installer__actions">
                <button
                  type="button"
                  onClick={() => void prepare(artifact, false)}
                  disabled={busy || ready || !nativeHostBridge.available}
                >
                  {busy ? 'Validando…' : ready ? 'Preparado' : 'Validar e preparar'}
                </button>
                {artifact.kind === 'WindowsInstallerPackage' && <small>Execução MSI exige broker qualificado.</small>}
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
