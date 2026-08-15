import { useEffect, useMemo, useState } from 'react';
import kernel from '../../core/kernel';
import {
  appendHistory,
  diskPercent,
  healthSummary,
  isSystemProcess,
  memoryPercent,
  sortProcesses,
} from '../../core/systemCenterMetrics.js';
import { useProcessManager } from '../../stores/processManager';
import type { Process } from '../../types';
import './TaskManager.css';

type Tab = 'processes' | 'performance' | 'services' | 'drivers';
type SortField = 'memory' | 'cpu' | 'pid' | 'name';

const formatMemory = (value: number) => {
  if (!Number.isFinite(value) || value <= 0) return '0 MB';
  return value >= 1024 ? `${(value / 1024).toFixed(1)} GB` : `${Math.round(value)} MB`;
};

const formatDisk = (value: number) => {
  if (!Number.isFinite(value) || value <= 0) return '0 GB';
  return `${(value / 1024).toFixed(value < 10240 ? 1 : 0)} GB`;
};

function formatUptime(value: number) {
  const seconds = Math.max(0, Math.floor(Number(value) || 0));
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}min`;
  return `${minutes}min ${seconds % 60}s`;
}

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

export default function TaskManagerApp({}: { windowId: string }) {
  const [activeTab, setActiveTab] = useState<Tab>('processes');
  const [selectedPid, setSelectedPid] = useState<number | null>(null);
  const [sortField, setSortField] = useState<SortField>('memory');
  const [query, setQuery] = useState('');
  const [resources, setResources] = useState(() => ({ ...kernel.resources }));
  const [services, setServices] = useState(() => kernel.getAllServices());
  const [drivers, setDrivers] = useState(() => kernel.getAllDrivers());
  const [cpuHistory, setCpuHistory] = useState<number[]>(() => [kernel.resources.cpuUsage]);
  const [memoryHistory, setMemoryHistory] = useState<number[]>(() => [memoryPercent(kernel.resources)]);

  const processes = useProcessManager(state => state.processes);
  const terminateProcess = useProcessManager(state => state.terminateProcess);

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

  const health = useMemo(
    () => healthSummary({ processes, services, drivers, resources }),
    [drivers, processes, resources, services],
  );

  const visibleProcesses = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase();
    const filtered = needle
      ? processes.filter(process => `${process.title} ${process.name} ${process.pid}`.toLocaleLowerCase().includes(needle))
      : processes;
    return sortProcesses(filtered, sortField) as Process[];
  }, [processes, query, sortField]);

  const selectedProcess = processes.find(process => process.pid === selectedPid) ?? null;
  const selectedIsSystem = selectedProcess ? isSystemProcess(selectedProcess) : false;
  const memory = memoryPercent(resources);
  const disk = diskPercent(resources);
  const largestProcess = sortProcesses(processes, 'memory')[0] as Process | undefined;

  const endSelectedTask = () => {
    if (!selectedProcess || isSystemProcess(selectedProcess)) return;
    terminateProcess(selectedProcess.pid);
    setSelectedPid(null);
  };

  return (
    <div className="task-manager system-center">
      <header className="sys-header">
        <div className="sys-title">
          <small>CloudOS Core</small>
          <strong>System Center</strong>
          <span>Processos, desempenho, serviços e drivers expostos pelo kernel virtual.</span>
        </div>
        <div className={`sys-health sys-health--${health.status}`}>
          <span className="sys-health__dot" aria-hidden="true" />
          <div>
            <strong>{health.status === 'healthy' ? 'Sistema saudável' : 'Atenção necessária'}</strong>
            <small>{health.alerts[0] ?? `${processes.length} processo(s) monitorado(s)`}</small>
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
        {activeTab === 'processes' && (
          <section className="sys-processes">
            <div className="sys-toolbar">
              <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar processo ou PID…" aria-label="Pesquisar processos" />
              <select value={sortField} onChange={event => setSortField(event.target.value as SortField)} aria-label="Ordenar processos">
                <option value="memory">Mais memória</option>
                <option value="cpu">Mais CPU</option>
                <option value="pid">PID</option>
                <option value="name">Nome</option>
              </select>
              <span>{visibleProcesses.length} de {processes.length}</span>
            </div>

            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead>
                  <tr><th>Processo</th><th>PID</th><th>Status</th><th>CPU</th><th>Memória</th><th>Prioridade</th><th>PPID</th></tr>
                </thead>
                <tbody>
                  {visibleProcesses.map(process => (
                    <tr key={process.pid} className={`tm-row ${selectedPid === process.pid ? 'selected' : ''}`} onClick={() => setSelectedPid(process.pid)}>
                      <td><span className="tm-proc-icon">{process.icon}</span>{process.title || process.name}{isSystemProcess(process) && <span className="p-sys-tag">SISTEMA</span>}</td>
                      <td>{process.pid}</td>
                      <td><span className={`tm-status ${process.status}`}>{process.status}</span></td>
                      <td>{process.cpuUsage.toFixed(1)}%</td>
                      <td>{formatMemory(process.memoryUsage)}</td>
                      <td>{process.priority}</td>
                      <td>{process.ppid}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <footer className="tm-footer sys-process-footer">
              <div className="sys-selected-info">
                {selectedProcess ? (
                  <>
                    <strong>{selectedProcess.title || selectedProcess.name}</strong>
                    <span>PID {selectedProcess.pid} · ativo há {formatUptime((Date.now() - selectedProcess.startTime) / 1000)}{selectedIsSystem ? ' · protegido' : ''}</span>
                  </>
                ) : <span>Selecione um processo para ver as ações disponíveis.</span>}
              </div>
              <button className="tm-end-task" onClick={endSelectedTask} disabled={!selectedProcess || selectedIsSystem}>Finalizar tarefa</button>
            </footer>
          </section>
        )}

        {activeTab === 'performance' && (
          <section className="tm-performance sys-performance">
            <div className="sys-performance-grid">
              <article className="perf-card sys-perf-card">
                <div className="perf-header"><div><small>PROCESSADOR</small><div className="perf-label">CPU</div></div><div className="perf-value">{resources.cpuUsage.toFixed(1)}%</div></div>
                <Sparkline values={cpuHistory} label="Histórico de CPU" />
                <div className="perf-details">
                  <div><span>Núcleos</span><span>{resources.cpuCores}</span></div>
                  <div><span>Uptime</span><span>{formatUptime(resources.uptime)}</span></div>
                  <div><span>Processos</span><span>{processes.length}</span></div>
                  <div><span>Suspensos</span><span>{health.suspended}</span></div>
                </div>
              </article>

              <article className="perf-card sys-perf-card">
                <div className="perf-header"><div><small>MEMÓRIA</small><div className="perf-label">RAM</div></div><div className="perf-value">{memory.toFixed(1)}%</div></div>
                <Sparkline values={memoryHistory} label="Histórico de memória" />
                <div className="perf-details">
                  <div><span>Em uso</span><span>{formatMemory(resources.usedMemory)}</span></div>
                  <div><span>Total</span><span>{formatMemory(resources.totalMemory)}</span></div>
                  <div><span>Livre</span><span>{formatMemory(Math.max(0, resources.totalMemory - resources.usedMemory))}</span></div>
                  <div><span>Maior processo</span><span>{formatMemory(largestProcess?.memoryUsage ?? 0)}</span></div>
                </div>
              </article>

              <article className="perf-card sys-perf-card sys-perf-card--compact">
                <div className="perf-header"><div><small>ARMAZENAMENTO VIRTUAL</small><div className="perf-label">Disco</div></div><div className="perf-value">{disk.toFixed(1)}%</div></div>
                <div className="sys-progress"><span style={{ width: `${disk}%` }} /></div>
                <div className="perf-details">
                  <div><span>Em uso</span><span>{formatDisk(resources.usedDisk)}</span></div>
                  <div><span>Total</span><span>{formatDisk(resources.totalDisk)}</span></div>
                  <div><span>Rede</span><span>{resources.networkUp ? 'Disponível' : 'Indisponível'}</span></div>
                </div>
              </article>

              <article className={`perf-card sys-perf-card sys-health-card sys-health-card--${health.status}`}>
                <small>INTEGRIDADE</small>
                <strong>{health.status === 'healthy' ? 'Nenhuma condição crítica observável' : health.alerts.join(' · ')}</strong>
                <div className="sys-health-grid">
                  <span>Serviços com falha <b>{health.failedServices}</b></span>
                  <span>Drivers com falha <b>{health.failedDrivers}</b></span>
                </div>
              </article>
            </div>
          </section>
        )}

        {activeTab === 'services' && (
          <section className="sys-inventory">
            <header><div><small>Service Control Manager virtual</small><strong>{services.length} serviço(s)</strong></div><span>{health.failedServices} com falha</span></header>
            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead><tr><th>Serviço</th><th>Descrição</th><th>Status</th><th>Inicialização</th><th>PID</th><th>Reinícios</th></tr></thead>
                <tbody>{services.map(service => (
                  <tr className="tm-row" key={service.name}>
                    <td><strong>{service.displayName}</strong><small className="sys-secondary">{service.name}</small></td>
                    <td>{service.description}</td>
                    <td><span className={`sys-pill sys-pill--${service.status}`}>{service.status}</span></td>
                    <td>{service.startType}</td>
                    <td>{service.pid ?? '—'}</td>
                    <td>{service.restartCount}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'drivers' && (
          <section className="sys-inventory">
            <header><div><small>Driver Manager virtual</small><strong>{drivers.length} driver(s)</strong></div><span>{health.failedDrivers} com problema</span></header>
            <div className="sys-table-wrap">
              <table className="tm-table">
                <thead><tr><th>Driver</th><th>Status</th><th>Tipo</th><th>Ordem</th><th>Dependências</th><th>Arquivo</th></tr></thead>
                <tbody>{drivers.map(driver => (
                  <tr className="tm-row" key={driver.name}>
                    <td><strong>{driver.name}</strong>{driver.errorMessage && <small className="sys-secondary">{driver.errorMessage}</small>}</td>
                    <td><span className={`sys-pill sys-pill--${driver.status}`}>{driver.status}</span></td>
                    <td>{driver.type}</td>
                    <td>{driver.loadOrder}</td>
                    <td>{driver.dependencies.length ? driver.dependencies.join(', ') : '—'}</td>
                    <td><code>{driver.path}</code></td>
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
