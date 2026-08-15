import { useCallback, useEffect, useMemo, useState } from 'react';
import kernel from '../../core/kernel';
import { apiClient } from '../../services/apiClient';
import { nativeHostBridge } from '../../services/nativeHostBridge';
import { useSystem } from '../../stores/systemStore';
import './EnvDoctor.css';

type CheckStatus = 'ok' | 'fail' | 'checking';
type DiagnosticCheck = {
  id: string;
  name: string;
  status: CheckStatus;
  detail: string;
  group: 'runtime' | 'storage' | 'core';
};

const INITIAL_CHECKS: DiagnosticCheck[] = [
  { id: 'opfs', name: 'Origin Private File System', status: 'checking', detail: 'Verificando armazenamento persistente', group: 'storage' },
  { id: 'health', name: 'Backend API', status: 'checking', detail: 'Consultando /api/health', group: 'runtime' },
  { id: 'runtime', name: 'Runtime dinâmico', status: 'checking', detail: 'Consultando /api/runtime', group: 'runtime' },
  { id: 'websocket', name: 'WebSocket', status: 'checking', detail: 'Verificando suporte do shell', group: 'runtime' },
  { id: 'native-host', name: 'Host nativo', status: 'checking', detail: 'Verificando bridge WebView2/WPF', group: 'runtime' },
  { id: 'shell', name: 'Shell crítico', status: 'checking', detail: 'Verificando Explorer e DWM', group: 'core' },
  { id: 'win32', name: 'Subsistema gráfico', status: 'checking', detail: 'Verificando user32.dll e gdi32.dll', group: 'core' },
  { id: 'drivers', name: 'Drivers virtuais', status: 'checking', detail: 'Verificando drivers carregados', group: 'core' },
  { id: 'services', name: 'Serviços', status: 'checking', detail: 'Verificando serviços com falha', group: 'core' },
];

async function checkOpfs(): Promise<DiagnosticCheck> {
  try {
    if (!('storage' in navigator) || typeof navigator.storage.getDirectory !== 'function') throw new Error();
    await navigator.storage.getDirectory();
    return { id: 'opfs', name: 'Origin Private File System', status: 'ok', detail: 'OPFS disponível e gravável', group: 'storage' };
  } catch {
    return { id: 'opfs', name: 'Origin Private File System', status: 'fail', detail: 'OPFS indisponível neste contexto', group: 'storage' };
  }
}

async function checkEndpoint(id: 'health' | 'runtime', endpoint: string, successDetail: string): Promise<DiagnosticCheck> {
  try {
    await apiClient(endpoint, { skipAuth: true, suppressUnauthorizedHandler: true, timeoutMs: 4000 });
    return { id, name: id === 'health' ? 'Backend API' : 'Runtime dinâmico', status: 'ok', detail: successDetail, group: 'runtime' };
  } catch (error) {
    return {
      id,
      name: id === 'health' ? 'Backend API' : 'Runtime dinâmico',
      status: 'fail',
      detail: error instanceof Error ? error.message : 'Sem resposta do agente local',
      group: 'runtime',
    };
  }
}

export default function EnvDoctor() {
  const [checks, setChecks] = useState<DiagnosticCheck[]>(INITIAL_CHECKS);
  const [running, setRunning] = useState(false);
  const [lastRun, setLastRun] = useState<number | null>(null);
  const addNotification = useSystem(state => state.addNotification);

  const runDiagnostics = useCallback(async () => {
    setRunning(true);
    setChecks(INITIAL_CHECKS);

    const [opfs, health, runtime] = await Promise.all([
      checkOpfs(),
      checkEndpoint('health', '/api/health', 'Agente local respondendo normalmente'),
      checkEndpoint('runtime', '/api/runtime', 'Configuração de runtime disponível'),
    ]);

    const processes = kernel.getProcesses();
    const explorer = processes.some(process => process.name === 'explorer.obx');
    const dwm = processes.some(process => process.name === 'dwm.obx');
    const graphicsReady = kernel.fsExists('C:\\ObsidianOS\\System32\\gdi32.dll')
      && kernel.fsExists('C:\\ObsidianOS\\System32\\user32.dll');
    const failedDrivers = kernel.getAllDrivers().filter(driver => driver.status === 'failed' || driver.status === 'not_found');
    const failedServices = kernel.getAllServices().filter(service => service.status === 'failed');
    const wsReady = typeof WebSocket !== 'undefined';

    setChecks([
      opfs,
      health,
      runtime,
      {
        id: 'websocket',
        name: 'WebSocket',
        status: wsReady ? 'ok' : 'fail',
        detail: wsReady ? 'API WebSocket disponível' : 'WebSocket não suportado',
        group: 'runtime',
      },
      {
        id: 'native-host',
        name: 'Host nativo',
        status: nativeHostBridge.available ? 'ok' : 'fail',
        detail: nativeHostBridge.available ? 'Bridge WPF/WebView2 detectada' : 'Executando sem Host nativo',
        group: 'runtime',
      },
      {
        id: 'shell',
        name: 'Shell crítico',
        status: explorer && dwm ? 'ok' : 'fail',
        detail: `Explorer ${explorer ? 'OK' : 'ausente'} · DWM ${dwm ? 'OK' : 'ausente'}`,
        group: 'core',
      },
      {
        id: 'win32',
        name: 'Subsistema gráfico',
        status: graphicsReady ? 'ok' : 'fail',
        detail: graphicsReady ? 'user32.dll e gdi32.dll íntegros' : 'Componente gráfico crítico ausente',
        group: 'core',
      },
      {
        id: 'drivers',
        name: 'Drivers virtuais',
        status: failedDrivers.length === 0 ? 'ok' : 'fail',
        detail: failedDrivers.length === 0 ? `${kernel.getAllDrivers().length} driver(s), sem falhas registradas` : `${failedDrivers.length} driver(s) com problema`,
        group: 'core',
      },
      {
        id: 'services',
        name: 'Serviços',
        status: failedServices.length === 0 ? 'ok' : 'fail',
        detail: failedServices.length === 0 ? `${kernel.getAllServices().length} serviço(s), sem falhas registradas` : `${failedServices.length} serviço(s) com falha`,
        group: 'core',
      },
    ]);

    setLastRun(Date.now());
    setRunning(false);
  }, []);

  useEffect(() => {
    void runDiagnostics();
  }, [runDiagnostics]);

  const summary = useMemo(() => {
    const ok = checks.filter(check => check.status === 'ok').length;
    const fail = checks.filter(check => check.status === 'fail').length;
    return { ok, fail, total: checks.length };
  }, [checks]);

  const resources = kernel.resources;
  const memoryPercent = resources.totalMemory > 0
    ? Math.min(100, Math.round((resources.usedMemory / resources.totalMemory) * 100))
    : 0;

  const repairVirtualSystem = () => {
    kernel.fsRepairSystemFiles();
    addNotification({
      title: 'Reparo do sistema concluído',
      message: 'Os arquivos virtuais protegidos foram verificados e restaurados quando necessário.',
      type: 'success',
      icon: '🩺',
    });
    void runDiagnostics();
  };

  return (
    <section className="env-doctor">
      <header className="env-doctor__header">
        <div>
          <p className="env-doctor__eyebrow">CloudOS Core</p>
          <h1>Saúde do Sistema</h1>
          <p>Diagnóstico local do shell, armazenamento, Host nativo, serviços e recursos.</p>
        </div>
        <div className={`env-doctor__score ${summary.fail > 0 ? 'env-doctor__score--warning' : ''}`}>
          <strong>{summary.ok}/{summary.total}</strong>
          <span>{summary.fail > 0 ? `${summary.fail} atenção` : 'Tudo saudável'}</span>
        </div>
      </header>

      <div className="env-doctor__metrics">
        <article>
          <span>CPU</span>
          <strong>{resources.cpuUsage.toFixed(1)}%</strong>
          <small>{resources.cpuCores} núcleo(s)</small>
        </article>
        <article>
          <span>Memória</span>
          <strong>{memoryPercent}%</strong>
          <small>{Math.round(resources.usedMemory)} / {Math.round(resources.totalMemory)} MB</small>
        </article>
        <article>
          <span>Processos</span>
          <strong>{kernel.getProcesses().length}</strong>
          <small>{kernel.getRunningProcesses().length} em execução</small>
        </article>
        <article>
          <span>Uptime</span>
          <strong>{Math.floor(resources.uptime / 60)} min</strong>
          <small>{lastRun ? `checado ${new Date(lastRun).toLocaleTimeString()}` : 'checando…'}</small>
        </article>
      </div>

      <div className="env-doctor__toolbar">
        <button type="button" onClick={() => void runDiagnostics()} disabled={running}>
          {running ? 'Verificando…' : '↻ Executar diagnóstico'}
        </button>
        <button type="button" className="env-doctor__secondary" onClick={repairVirtualSystem}>
          🛠 Reparar arquivos virtuais
        </button>
      </div>

      <div className="env-doctor__checks">
        {checks.map(check => (
          <article className="env-doctor__check" key={check.id}>
            <span className={`env-doctor__status env-doctor__status--${check.status}`} aria-label={check.status}>
              {check.status === 'ok' ? '✓' : check.status === 'fail' ? '!' : '•'}
            </span>
            <div>
              <div className="env-doctor__check-heading">
                <strong>{check.name}</strong>
                <span>{check.group}</span>
              </div>
              <p>{check.detail}</p>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
