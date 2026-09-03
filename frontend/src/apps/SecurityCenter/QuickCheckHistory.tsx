import { useEffect, useMemo, useRef, useState } from 'react';
import { getUserStorageKey } from '../../services/userScope.js';
import './QuickCheckHistory.css';

type ScanResultLike = {
  preset: string;
  label: string;
  target: string;
  completedAt: string;
  hosts: Array<{ address: string; up: boolean; ports: Array<{ port: number; state: string; service: string }> }>;
  insights?: { highestSeverity?: string };
};

type DiagnosticsLike = null | {
  reachability: { reachable: boolean; averageMs: number | null };
  identity: { mac: string | null; isDefaultGateway: boolean };
};

type HistoryRecord = {
  id: string;
  preset: string;
  label: string;
  target: string;
  completedAt: string;
  highestAttention: string;
  hostCount: number;
  openPortCount: number;
  openPorts: number[];
  reachable: boolean | null;
  averageMs: number | null;
  mac: string | null;
  isGateway: boolean | null;
};

type Props = {
  result: ScanResultLike | null;
  hostDiagnostics: DiagnosticsLike;
  busy: boolean;
  onUseTarget: (target: string) => void;
  onRerun: (preset: string, target: string) => void;
};

const STORAGE_KEY = 'cloudos-security-quick-check-history-v1';
const MAX_RECORDS = 12;

function storageKey() {
  return getUserStorageKey(STORAGE_KEY);
}

function normalizeRecord(value: unknown): HistoryRecord | null {
  if (!value || typeof value !== 'object') return null;
  const item = value as Partial<HistoryRecord>;
  if (typeof item.target !== 'string' || typeof item.preset !== 'string' || typeof item.completedAt !== 'string') return null;
  if (!/^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(item.target) && !item.target.includes('/')) return null;
  return {
    id: typeof item.id === 'string' ? item.id : `${item.completedAt}-${item.preset}-${item.target}`,
    preset: item.preset.slice(0, 64),
    label: typeof item.label === 'string' ? item.label.slice(0, 120) : item.preset.slice(0, 64),
    target: item.target.slice(0, 64),
    completedAt: item.completedAt,
    highestAttention: typeof item.highestAttention === 'string' ? item.highestAttention.slice(0, 32) : 'info',
    hostCount: Number.isInteger(item.hostCount) ? Math.max(0, Number(item.hostCount)) : 0,
    openPortCount: Number.isInteger(item.openPortCount) ? Math.max(0, Number(item.openPortCount)) : 0,
    openPorts: Array.isArray(item.openPorts) ? item.openPorts.filter(port => Number.isInteger(port) && port > 0 && port <= 65535).slice(0, 20) : [],
    reachable: typeof item.reachable === 'boolean' ? item.reachable : null,
    averageMs: typeof item.averageMs === 'number' && Number.isFinite(item.averageMs) ? item.averageMs : null,
    mac: typeof item.mac === 'string' ? item.mac.slice(0, 32) : null,
    isGateway: typeof item.isGateway === 'boolean' ? item.isGateway : null,
  };
}

function loadHistory(): HistoryRecord[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(storageKey()) || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed.map(normalizeRecord).filter((item): item is HistoryRecord => item !== null).slice(0, MAX_RECORDS);
  } catch {
    localStorage.removeItem(storageKey());
    return [];
  }
}

function saveHistory(records: HistoryRecord[]) {
  localStorage.setItem(storageKey(), JSON.stringify(records.slice(0, MAX_RECORDS)));
}

function fromResult(result: ScanResultLike, diagnostics: DiagnosticsLike): HistoryRecord {
  const open = result.hosts.flatMap(host => host.ports.filter(port => port.state === 'open').map(port => port.port));
  return {
    id: `${result.completedAt}-${result.preset}-${result.target}`,
    preset: result.preset,
    label: result.label,
    target: result.target,
    completedAt: result.completedAt,
    highestAttention: result.insights?.highestSeverity || 'info',
    hostCount: result.hosts.filter(host => host.up).length,
    openPortCount: open.length,
    openPorts: [...new Set(open)].sort((a, b) => a - b).slice(0, 20),
    reachable: diagnostics ? diagnostics.reachability.reachable : null,
    averageMs: diagnostics?.reachability.averageMs ?? null,
    mac: diagnostics?.identity.mac ?? null,
    isGateway: diagnostics?.identity.isDefaultGateway ?? null,
  };
}

export default function QuickCheckHistory({ result, hostDiagnostics, busy, onUseTarget, onRerun }: Props) {
  const [records, setRecords] = useState<HistoryRecord[]>(loadHistory);
  const lastStoredId = useRef('');

  useEffect(() => {
    if (!result) return;
    const record = fromResult(result, hostDiagnostics);
    if (lastStoredId.current === record.id) return;
    lastStoredId.current = record.id;
    setRecords(current => {
      const next = [record, ...current.filter(item => item.id !== record.id)].slice(0, MAX_RECORDS);
      saveHistory(next);
      return next;
    });
  }, [hostDiagnostics, result]);

  const latestTargets = useMemo(() => new Set(records.map(item => item.target)).size, [records]);

  if (!records.length) return null;

  const clear = () => {
    setRecords([]);
    saveHistory([]);
  };

  return <section className="qch-root" aria-label="Histórico de checks rápidos">
    <header>
      <div><small>Histórico local deste usuário</small><strong>Repetir sem configurar tudo de novo</strong><span>{records.length} check(s) · {latestTargets} alvo(s)</span></div>
      <button type="button" onClick={clear}>Limpar</button>
    </header>
    <div className="qch-list">
      {records.map(record => <article key={record.id}>
        <div className="qch-main"><strong>{record.label}</strong><span>{record.target}</span><small>{new Date(record.completedAt).toLocaleString()}</small></div>
        <div className="qch-metrics"><span>{record.hostCount} host(s)</span><span>{record.openPortCount} porta(s)</span>{record.averageMs !== null && <span>{record.averageMs} ms</span>}<em>{record.highestAttention}</em></div>
        {record.openPorts.length > 0 && <div className="qch-ports">{record.openPorts.slice(0, 8).map(port => <span key={port}>{port}</span>)}</div>}
        <div className="qch-actions">
          {!record.target.includes('/') && <button type="button" onClick={() => onUseTarget(record.target)}>Usar IP</button>}
          <button type="button" disabled={busy} onClick={() => onRerun(record.preset, record.target)}>↻ Repetir check</button>
        </div>
      </article>)}
    </div>
  </section>;
}
