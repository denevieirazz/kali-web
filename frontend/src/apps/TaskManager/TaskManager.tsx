import { Component, useCallback, useEffect, useMemo, useRef, useState, type ErrorInfo, type ReactNode } from 'react';
import kernel from '../../core/kernel';
import { appendHistory, diskPercent, healthSummary, isSystemProcess, memoryPercent, sortProcesses } from '../../core/systemCenterMetrics.js';
import { useProcessManager } from '../../stores/processManager';
import type { Process } from '../../types';
import {
  linuxSystemCenterClient,
  type CgroupAssignment,
  type LinuxMetrics,
  type LinuxProcessInfo,
  type LinuxSignal,
  type LinuxStatus,
  type SystemCenterSource,
} from './linuxSystemCenterClient';
import {
  LatestRequestGate,
  LINUX_SYSTEM_CENTER_MAX_ROWS,
  LINUX_SYSTEM_CENTER_POLL_MS,
  safeSystemCenterError,
} from './linuxSystemCenterModel.js';
import './TaskManager.css';
import './LinuxSystemCenter.css';

type Tab = 'processes' | 'performance' | 'services' | 'drivers';
type SortField = 'pid' | 'cpu' | 'memory' | 'name' | 'user';

const fmtBytes = (value: number) => {
  if (!Number.isFinite(value) || value <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let amount = value;
  let index = 0;
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024;
    index += 1;
  }
  return `${amount.toFixed(index < 2 ? 0 : 1)} ${units[index]}`;
};

const fmtVirtualMemory = (value: number) =>
  value >= 1024 ? `${(value / 1024).toFixed(1)} GB` : `${Math.round(value || 0)} MB`;

const fmtUptime = (value: number) => {
  const seconds = Math.max(0, Math.floor(value || 0));
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}min`;
  return `${minutes}min ${seconds % 60}s`;
};

function Sparkline({ values, label }: { values: number[]; label: string }) {
  const points = values.length > 1
    ? values.map((value, index) => `${(index / (values.length - 1)) * 100},${100 - Math.max(0, Math.min(100, value))}`).join(' ')
    : '0,100 100,100';
  return (
    <svg className="sys-sparkline" viewBox="0 0 100 100" preserveAspectRatio="none" role="img" aria-label={label}>
      <polyline points={points} fill="none" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

class LinuxProcessRowBoundary extends Component<
  { pid: number; children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(_error: Error, _info: ErrorInfo) {
    // A fronteira existe para manter o restante da tabela utilizável.
    // O payload já foi normalizado e nenhum dado sensível é logado aqui.
  }

  render() {
    if (this.state.failed) {
      return (
        <tr className="tm-row" data-linux-row-error={this.props.pid}>
          <td colSpan={8}>Processo PID {this.props.pid}: linha inválida isolada.</td>
        </tr>
      );
    }
    return this.props.children;
  }
}

function LinuxProcessRow({
  process,
  selected,
  onSelect,
}: {
  process: LinuxProcessInfo;
  selected: boolean;
  onSelect: (pid: number) => void;
}) {
  return (
    <tr
      data-linux-pid={process.pid}
      className={`tm-row ${selected ? 'selected' : ''}`}
      onClick={() => onSelect(process.pid)}
    >
      <td>
        <strong>{process.name}</strong>
        {process.protected && <span className="p-sys-tag">PROTEGIDO</span>}
        <small className="sys-secondary">
          {process.executable || 'executável não disponível'}
          {process.args.length ? ` · ${process.args.join(' ')}` : ''}
        </small>
      </td>
      <td>
        {process.pid}
        <small className="sys-secondary">PPID {process.ppid}</small>
      </td>
      <td>{process.state}</td>
      <td>
        {process.user}
        <small className="sys-secondary">UID {process.uid >= 0 ? process.uid : '—'}</small>
      </td>
      <td>{process.cpuPercent.toFixed(1)}%</td>
      <td>
        {fmtBytes(process.rssBytes)}
        <small className="sys-secondary">VM {fmtBytes(process.virtualBytes)}</small>
      </td>
      <td>{process.threads}</td>
      <td><code>{process.cgroup || '—'}</code></td>
    </tr>
  );
}

export default function TaskManagerApp({}: { windowId: string }) {
  const [activeTab, setActiveTab] = useState<Tab>('processes');
  const [source, setSource] = useState<SystemCenterSource>('linux-real');
  const [query, setQuery] = useState('');
  const [stateFilter, setStateFilter] = useState('');
  const [userFilter, setUserFilter] = useState('');
  const [sortField, setSortField] = useState<SortField>('pid');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [selectedPid, setSelectedPid] = useState<number | null>(null);

  const [linuxStatus, setLinuxStatus] = useState<LinuxStatus | null>(null);
  const [linuxProcesses, setLinuxProcesses] = useState<LinuxProcessInfo[]>([]);
  const [linuxTotal, setLinuxTotal] = useState(0);
  const [linuxMetrics, setLinuxMetrics] = useState<LinuxMetrics | null>(null);
  const [linuxLoading, setLinuxLoading] = useState(false);
  const [linuxError, setLinuxError] = useState('');
  const [linuxMetricsError, setLinuxMetricsError] = useState('');
  const [linuxRowNotice, setLinuxRowNotice] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');
  const [assignment, setAssignment] = useState<CgroupAssignment | null>(null);

  const [hostMetrics, setHostMetrics] = useState<any>(null);
  const [hostError, setHostError] = useState('');
  const gateRef = useRef(new LatestRequestGate());

  const [resources, setResources] = useState(() => ({ ...kernel.resources }));
  const [services, setServices] = useState(() => kernel.getAllServices());
  const [drivers, setDrivers] = useState(() => kernel.getAllDrivers());
  const [cpuHistory, setCpuHistory] = useState<number[]>(() => [kernel.resources.cpuUsage]);
  const [memoryHistory, setMemoryHistory] = useState<number[]>(() => [memoryPercent(kernel.resources)]);
  const virtualProcesses = useProcessManager(state => state.processes);
  const terminateVirtual = useProcessManager(state => state.terminateProcess);

  useEffect(() => {
    const refresh = () => {
      const next = { ...kernel.resources };
      setResources(next);
      setServices(kernel.getAllServices());
      setDrivers(kernel.getAllDrivers());
      setCpuHistory(history => appendHistory(history, next.cpuUsage));
      setMemoryHistory(history => appendHistory(history, memoryPercent(next)));
    };
    refresh();
    const timer = window.setInterval(refresh, 1000);
    return () => window.clearInterval(timer);
  }, []);

  const refreshLinux = useCallback(async () => {
    const request = gateRef.current.next();
    setLinuxLoading(true);
    setLinuxError('');
    setLinuxMetricsError('');

    try {
      const status = await linuxSystemCenterClient.status(request.signal);
      if (!request.current()) return;
      setLinuxStatus(status);

      if (!status.available) {
        setLinuxProcesses([]);
        setLinuxMetrics(null);
        setLinuxTotal(0);
        setLinuxRowNotice('');
        setLinuxError(status.reason || 'Linux System Center indisponível.');
        return;
      }

      const processTask = linuxSystemCenterClient.processes({
        page: 1,
        pageSize: LINUX_SYSTEM_CENTER_MAX_ROWS,
        query,
        state: stateFilter,
        user: userFilter,
        sortBy: sortField,
        sortDir,
      }, request.signal).then(page => {
        if (!request.current()) return;
        setLinuxProcesses(page.processes.slice(0, LINUX_SYSTEM_CENTER_MAX_ROWS));
        setLinuxTotal(page.total);
        const sampledAt = Date.parse(page.sampledAt);
        setLastUpdated(new Date(Number.isFinite(sampledAt) ? sampledAt : Date.now()).toLocaleTimeString());
        const notices = [];
        if (page.partialRows > 0) notices.push(`${page.partialRows} linha(s) parcial(is) normalizada(s)`);
        if (page.droppedRows > 0) notices.push(`${page.droppedRows} linha(s) sem PID válido isolada(s)`);
        setLinuxRowNotice(notices.join(' · '));
        setLinuxError('');
        if (selectedPid !== null && !page.processes.some(process => process.pid === selectedPid)) {
          setSelectedPid(null);
          setAssignment(null);
        }
      }).catch(error => {
        if (request.current()) setLinuxError(safeSystemCenterError(error));
      });

      const metricsTask = linuxSystemCenterClient.metrics(request.signal).then(metrics => {
        if (!request.current()) return;
        setLinuxMetrics(metrics);
        if (metrics.partial) {
          setLinuxMetricsError(`Métricas Linux parciais: ${metrics.missingFields.join(', ')}`);
        } else {
          setLinuxMetricsError('');
        }
      }).catch(error => {
        if (!request.current()) return;
        setLinuxMetrics(null);
        setLinuxMetricsError(safeSystemCenterError(error));
      });

      await Promise.all([processTask, metricsTask]);
    } catch (error) {
      if (!request.current()) return;
      setLinuxStatus(null);
      setLinuxError(safeSystemCenterError(error));
    } finally {
      if (request.current()) setLinuxLoading(false);
    }
  }, [query, selectedPid, sortDir, sortField, stateFilter, userFilter]);

  useEffect(() => {
    if (source !== 'linux-real') return;
    let cancelled = false;
    let timer = 0;
    const poll = async () => {
      await refreshLinux();
      if (!cancelled) timer = window.setTimeout(() => void poll(), LINUX_SYSTEM_CENTER_POLL_MS);
    };
    void poll();
    return () => {
      cancelled = true;
      if (timer) window.clearTimeout(timer);
    };
  }, [source, refreshLinux]);

  useEffect(() => () => gateRef.current.dispose(), []);

  useEffect(() => {
    if (source !== 'host-windows') return;
    let active = true;
    const controller = new AbortController();
    const refresh = async () => {
      try {
        const data = await linuxSystemCenterClient.hostMetrics(controller.signal);
        if (active) {
          setHostMetrics(data);
          setHostError('');
        }
      } catch (error) {
        if (active) setHostError(safeSystemCenterError(error));
      }
    };
    void refresh();
    const timer = window.setInterval(refresh, LINUX_SYSTEM_CENTER_POLL_MS);
    return () => {
      active = false;
      controller.abort();
      window.clearInterval(timer);
    };
  }, [source]);

  const health = useMemo(
    () => healthSummary({ processes: virtualProcesses, services, drivers, resources }),
    [virtualProcesses, services, drivers, resources],
  );

  const virtualVisible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const filtered = needle
      ? virtualProcesses.filter(process => `${process.title} ${process.name} ${process.pid}`.toLowerCase().includes(needle))
      : virtualProcesses;
    return sortProcesses(
      filtered,
      sortField === 'memory' ? 'memory' : sortField === 'cpu' ? 'cpu' : sortField === 'name' ? 'name' : 'pid',
    ) as Process[];
  }, [virtualProcesses, query, sortField]);

  const selectedLinux = linuxProcesses.find(process => process.pid === selectedPid) || null;
  const selectedVirtual = virtualProcesses.find(process => process.pid === selectedPid) || null;

  const signalLinux = async (signal: LinuxSignal) => {
    if (!selectedLinux || selectedLinux.protected) return;
    if (!window.confirm(`Confirmar ${signal} para ${selectedLinux.name} (PID ${selectedLinux.pid})?`)) return;
    try {
      await linuxSystemCenterClient.signal(selectedLinux, signal);
      setAssignment(null);
      await refreshLinux();
    } catch (error) {
      setLinuxError(safeSystemCenterError(error));
    }
  };

  const applyPreset = async () => {
    if (!selectedLinux || !linuxMetrics || !linuxMetrics.cgroupCapabilities.controlAvailable) return;
    if (!window.confirm(`Aplicar limite real conservador ao PID ${selectedLinux.pid}?`)) return;
    try {
      const result = await linuxSystemCenterClient.applyPolicy(selectedLinux, {
        memoryMaxBytes: 512 * 1024 * 1024,
        memoryHighBytes: 384 * 1024 * 1024,
        cpuPercent: 100,
        pidsMax: 256,
      });
      setAssignment(result.assignment);
      await refreshLinux();
    } catch (error) {
      setLinuxError(safeSystemCenterError(error));
    }
  };

  const clearPreset = async () => {
    if (!assignment) return;
    if (!window.confirm('Remover o limite cgroup aplicado por esta sessão?')) return;
    try {
      await linuxSystemCenterClient.clearPolicy(assignment.id);
      setAssignment(null);
      await refreshLinux();
    } catch (error) {
      setLinuxError(safeSystemCenterError(error));
    }
  };

  const sourceLabel = source === 'linux-real' ? 'Linux real' : source === 'host-windows' ? 'Host Windows' : 'CloudOS virtual';
  const linuxAvailable = Boolean(linuxStatus && linuxStatus.available);
  const linuxAttention = Boolean(linuxError || linuxMetricsError || linuxRowNotice);
  const cgroupCapabilities = linuxMetrics ? linuxMetrics.cgroupCapabilities : null;

  return (
    <div className="task-manager system-center" data-system-center-source={source}>
      <header className="sys-header">
        <div className="sys-title">
          <small>CloudOS Core</small>
          <strong>System Center</strong>
          <span>Fontes isoladas: Linux real, modelo virtual e Host Windows.</span>
        </div>
        <div className="sc-source-box">
          <label>Origem</label>
          <select
            value={source}
            onChange={event => {
              setSource(event.target.value as SystemCenterSource);
              setSelectedPid(null);
              setAssignment(null);
            }}
            aria-label="Origem dos dados"
          >
            <option value="linux-real">Linux real</option>
            <option value="cloudos-virtual">CloudOS virtual</option>
            <option value="host-windows">Host Windows</option>
          </select>
          <strong>{sourceLabel}</strong>
        </div>
        <div className={`sys-health sys-health--${source === 'linux-real' ? (linuxAttention ? 'attention' : 'healthy') : health.status}`}>
          <span className="sys-health__dot" />
          <div>
            <strong>{source === 'linux-real' ? (linuxAvailable ? 'WSL Core v2' : 'Linux indisponível') : sourceLabel}</strong>
            <small>
              {source === 'linux-real'
                ? `${linuxStatus && linuxStatus.distribution ? linuxStatus.distribution : 'Linux'} · ${lastUpdated ? `atualizado ${lastUpdated}` : 'aguardando atualização'}`
                : `fonte ${sourceLabel}`}
            </small>
          </div>
        </div>
      </header>

      <nav className="tm-tabs" aria-label="System Center">
        {([
          ['processes', 'Processos'],
          ['performance', 'Desempenho'],
          ['services', 'Serviços'],
          ['drivers', 'Drivers'],
        ] as Array<[Tab, string]>).map(([id, label]) => (
          <button key={id} className={`tm-tab ${activeTab === id ? 'active' : ''}`} onClick={() => setActiveTab(id)}>
            {label}
          </button>
        ))}
      </nav>

      <div className="tm-content">
        {activeTab === 'processes' && source === 'linux-real' && (
          <section className="sys-processes" data-linux-process-table="true">
            <div className="sys-toolbar sc-toolbar">
              <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar nome, PID ou argumento…" />
              <input value={userFilter} onChange={event => setUserFilter(event.target.value)} placeholder="Usuário/UID" />
              <select value={stateFilter} onChange={event => setStateFilter(event.target.value)}>
                <option value="">Todos estados</option>
                {['R', 'S', 'D', 'T', 'Z', 'I'].map(state => <option key={state}>{state}</option>)}
              </select>
              <select value={sortField} onChange={event => setSortField(event.target.value as SortField)}>
                <option value="pid">PID</option>
                <option value="cpu">CPU</option>
                <option value="memory">Memória</option>
                <option value="name">Nome</option>
                <option value="user">Usuário</option>
              </select>
              <button onClick={() => setSortDir(value => value === 'asc' ? 'desc' : 'asc')}>{sortDir === 'asc' ? '↑' : '↓'}</button>
              <button onClick={() => void refreshLinux()} disabled={linuxLoading}>{linuxLoading ? 'Atualizando…' : 'Atualizar'}</button>
              <span>{linuxProcesses.length} exibidos · {linuxTotal} encontrados</span>
            </div>

            {linuxError && (
              <div className="sc-state sc-state--error" role="alert">
                {linuxError}
                {linuxStatus && linuxStatus.fallbackAllowed && <button onClick={() => setSource('cloudos-virtual')}>Usar fallback virtual</button>}
              </div>
            )}
            {linuxRowNotice && <div className="sc-state" data-linux-normalization-notice="true">{linuxRowNotice}</div>}
            {!linuxError && linuxLoading && !linuxProcesses.length && <div className="sc-state">Carregando processos Linux reais…</div>}

            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead>
                  <tr><th>Processo</th><th>PID/PPID</th><th>Estado</th><th>Usuário</th><th>CPU</th><th>RSS</th><th>Threads</th><th>Cgroup</th></tr>
                </thead>
                <tbody>
                  {linuxProcesses.map(process => (
                    <LinuxProcessRowBoundary key={`${process.pid}-${process.startTimeTicks}`} pid={process.pid}>
                      <LinuxProcessRow process={process} selected={selectedPid === process.pid} onSelect={setSelectedPid} />
                    </LinuxProcessRowBoundary>
                  ))}
                </tbody>
              </table>
            </div>

            <footer className="tm-footer sys-process-footer">
              <div className="sys-selected-info">
                {selectedLinux ? (
                  <>
                    <strong>{selectedLinux.name} · PID {selectedLinux.pid}</strong>
                    <span>
                      {selectedLinux.protected
                        ? `Protegido: ${selectedLinux.protectedReason || 'essencial'}`
                        : `ativo há ${fmtUptime(selectedLinux.uptimeSeconds)}`}
                    </span>
                  </>
                ) : <span>Selecione um processo Linux real.</span>}
              </div>
              <div className="sc-actions">
                <button disabled={!selectedLinux || selectedLinux.protected} onClick={() => void signalLinux('SIGINT')}>SIGINT</button>
                <button disabled={!selectedLinux || selectedLinux.protected} onClick={() => void signalLinux('SIGTERM')}>SIGTERM</button>
                <button className="tm-end-task" disabled={!selectedLinux || selectedLinux.protected} onClick={() => void signalLinux('SIGKILL')}>SIGKILL</button>
              </div>
            </footer>
          </section>
        )}

        {activeTab === 'processes' && source === 'cloudos-virtual' && (
          <section className="sys-processes" data-virtual-process-table="true">
            <div className="sys-toolbar">
              <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar processo virtual…" />
              <select value={sortField} onChange={event => setSortField(event.target.value as SortField)}>
                <option value="memory">Mais memória</option><option value="cpu">Mais CPU</option><option value="pid">PID</option><option value="name">Nome</option>
              </select>
              <span>{virtualVisible.length} de {virtualProcesses.length} · CloudOS virtual</span>
            </div>
            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead><tr><th>Processo</th><th>PID</th><th>Status</th><th>CPU</th><th>Memória</th><th>PPID</th></tr></thead>
                <tbody>{virtualVisible.map(process => (
                  <tr key={process.pid} className={`tm-row ${selectedPid === process.pid ? 'selected' : ''}`} onClick={() => setSelectedPid(process.pid)}>
                    <td>{process.title || process.name}{isSystemProcess(process) && <span className="p-sys-tag">SISTEMA VIRTUAL</span>}</td>
                    <td>{process.pid}</td><td>{process.status}</td><td>{process.cpuUsage.toFixed(1)}%</td><td>{fmtVirtualMemory(process.memoryUsage)}</td><td>{process.ppid}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
            <footer className="tm-footer sys-process-footer">
              <span>Modelo virtual — PIDs não são PIDs Linux.</span>
              <button className="tm-end-task" disabled={!selectedVirtual || isSystemProcess(selectedVirtual)} onClick={() => {
                if (selectedVirtual) {
                  terminateVirtual(selectedVirtual.pid);
                  setSelectedPid(null);
                }
              }}>Finalizar virtual</button>
            </footer>
          </section>
        )}

        {activeTab === 'processes' && source === 'host-windows' && (
          <div className="sc-state" data-host-process-unavailable="true">
            Processos do Host Windows não são expostos por este lote. Selecione Linux real ou CloudOS virtual; não há mistura de PID.
          </div>
        )}

        {activeTab === 'performance' && source === 'linux-real' && (
          <section
            className="tm-performance sys-performance"
            data-cgroup-readonly={String(cgroupCapabilities ? cgroupCapabilities.readOnly : true)}
          >
            {linuxMetricsError && <div className="sc-state sc-state--error" role="alert">{linuxMetricsError}</div>}
            {!linuxMetrics && linuxLoading && <div className="sc-state">Carregando métricas Linux reais…</div>}
            <div className="sys-performance-grid">
              <article className="perf-card sys-perf-card">
                <div className="perf-header">
                  <div><small>LINUX REAL</small><div className="perf-label">Carga</div></div>
                  <div className="perf-value">{linuxMetrics ? linuxMetrics.load1.toFixed(2) : '—'}</div>
                </div>
                <div className="perf-details">
                  <div><span>1 / 5 / 15 min</span><span>{linuxMetrics ? `${linuxMetrics.load1.toFixed(2)} / ${linuxMetrics.load5.toFixed(2)} / ${linuxMetrics.load15.toFixed(2)}` : '—'}</span></div>
                  <div><span>Processos</span><span>{linuxMetrics ? linuxMetrics.processCount : '—'}</span></div>
                  <div><span>Uptime</span><span>{fmtUptime(linuxMetrics ? linuxMetrics.uptimeSeconds : 0)}</span></div>
                </div>
              </article>

              <article className="perf-card sys-perf-card">
                <div className="perf-header">
                  <div><small>MEMÓRIA LINUX</small><div className="perf-label">RAM</div></div>
                  <div className="perf-value">{linuxMetrics ? fmtBytes(Math.max(0, linuxMetrics.memoryTotalBytes - linuxMetrics.memoryAvailableBytes)) : '—'}</div>
                </div>
                <div className="perf-details">
                  <div><span>Total</span><span>{fmtBytes(linuxMetrics ? linuxMetrics.memoryTotalBytes : 0)}</span></div>
                  <div><span>Disponível</span><span>{fmtBytes(linuxMetrics ? linuxMetrics.memoryAvailableBytes : 0)}</span></div>
                </div>
              </article>

              <article className="perf-card sys-perf-card sc-cgroup-card">
                <small>CGROUPS V2</small>
                <strong>{cgroupCapabilities && cgroupCapabilities.mounted ? 'Detectado' : 'Indisponível'}</strong>
                <div className="perf-details">
                  <div><span>Caminho do core</span><code>{cgroupCapabilities && cgroupCapabilities.currentPath ? cgroupCapabilities.currentPath : '—'}</code></div>
                  <div><span>Controllers</span><span>{cgroupCapabilities && cgroupCapabilities.controllersAvailable.length ? cgroupCapabilities.controllersAvailable.join(', ') : '—'}</span></div>
                  <div><span>Delegados</span><span>{cgroupCapabilities && cgroupCapabilities.controllersDelegated.length ? cgroupCapabilities.controllersDelegated.join(', ') : '—'}</span></div>
                  <div><span>systemd</span><span>{cgroupCapabilities && cgroupCapabilities.systemd ? 'presente' : 'não detectado'}</span></div>
                  <div>
                    <span>Modo</span>
                    <span data-cgroup-control-available={String(cgroupCapabilities ? cgroupCapabilities.controlAvailable : false)}>
                      {cgroupCapabilities && cgroupCapabilities.controlAvailable ? 'controle real disponível' : 'somente leitura'}
                    </span>
                  </div>
                  <div><span>Motivo</span><span>{cgroupCapabilities && cgroupCapabilities.reason ? cgroupCapabilities.reason : 'capacidade comprovada'}</span></div>
                </div>
              </article>

              <article className="perf-card sys-perf-card sc-cgroup-card">
                <small>POLÍTICA DE RECURSOS</small>
                <strong>{assignment ? 'Limite real aplicado' : cgroupCapabilities && cgroupCapabilities.controlAvailable ? 'Controle experimental habilitado' : 'Nenhum limite aplicado'}</strong>
                <p>{assignment ? `Assignment ${assignment.id} · ${assignment.cgroupPath}` : 'A interface nunca declara limite aplicado sem confirmação do cloudos-core.'}</p>
                <div className="sc-actions">
                  {assignment
                    ? <button onClick={() => void clearPreset()}>Remover limite</button>
                    : <button disabled={!selectedLinux || !cgroupCapabilities || !cgroupCapabilities.controlAvailable} onClick={() => void applyPreset()}>Aplicar preset 512MB / 100% CPU / 256 PIDs</button>}
                </div>
              </article>
            </div>
          </section>
        )}

        {activeTab === 'performance' && source === 'cloudos-virtual' && (
          <section className="tm-performance sys-performance">
            <div className="sys-performance-grid">
              <article className="perf-card sys-perf-card"><div className="perf-header"><div><small>CLOUDOS VIRTUAL</small><div className="perf-label">CPU</div></div><div className="perf-value">{resources.cpuUsage.toFixed(1)}%</div></div><Sparkline values={cpuHistory} label="CPU virtual" /></article>
              <article className="perf-card sys-perf-card"><div className="perf-header"><div><small>MEMÓRIA VIRTUAL</small><div className="perf-label">RAM</div></div><div className="perf-value">{memoryPercent(resources).toFixed(1)}%</div></div><Sparkline values={memoryHistory} label="Memória virtual" /></article>
              <article className="perf-card sys-perf-card"><small>DISCO VIRTUAL</small><strong>{diskPercent(resources).toFixed(1)}%</strong></article>
            </div>
          </section>
        )}

        {activeTab === 'performance' && source === 'host-windows' && (
          <section className="tm-performance sys-performance" data-host-windows="true">
            {hostError ? <div className="sc-state sc-state--error">{hostError}</div> : (
              <div className="sys-performance-grid">
                <article className="perf-card sys-perf-card"><small>HOST WINDOWS</small><strong>{hostMetrics?.cpu?.brand || '—'}</strong><div className="perf-value">{hostMetrics?.cpu?.loadPercentage >= 0 ? `${hostMetrics.cpu.loadPercentage}%` : '—'}</div></article>
                <article className="perf-card sys-perf-card"><small>MEMÓRIA HOST</small><strong>{fmtBytes(hostMetrics?.memory?.used || 0)} / {fmtBytes(hostMetrics?.memory?.total || 0)}</strong></article>
              </div>
            )}
          </section>
        )}

        {activeTab === 'services' && (
          <section className="sys-inventory">
            <header><div><small>CloudOS virtual · não Linux</small><strong>{services.length} serviço(s)</strong></div><span>inventário virtual preservado</span></header>
            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead><tr><th>Serviço</th><th>Descrição</th><th>Status</th><th>PID virtual</th></tr></thead>
                <tbody>{services.map(service => (
                  <tr className="tm-row" key={service.name}>
                    <td>{service.displayName}<small className="sys-secondary">{service.name}</small></td><td>{service.description}</td><td>{service.status}</td><td>{service.pid ?? '—'}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'drivers' && (
          <section className="sys-inventory">
            <header><div><small>CloudOS virtual · não Linux</small><strong>{drivers.length} driver(s)</strong></div><span>inventário virtual preservado</span></header>
            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead><tr><th>Driver</th><th>Status</th><th>Tipo</th><th>Ordem</th><th>Dependências</th><th>Arquivo</th></tr></thead>
                <tbody>{drivers.map(driver => (
                  <tr className="tm-row" key={driver.name}>
                    <td><strong>{driver.name}</strong>{driver.errorMessage && <small className="sys-secondary">{driver.errorMessage}</small>}</td>
                    <td><span className={`sys-pill sys-pill--${driver.status}`}>{driver.status}</span></td><td>{driver.type}</td><td>{driver.loadOrder}</td><td>{driver.dependencies.length ? driver.dependencies.join(', ') : '—'}</td><td><code>{driver.path}</code></td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
