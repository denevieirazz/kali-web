import { useState, useEffect } from 'react';
import { useProcessManager } from '../../stores/processManager';
import kernel from '../../core/kernel';
import './TaskManager.css';

export default function TaskManagerApp({}: { windowId: string }) {
  const { processes, terminateProcess } = useProcessManager();
  const [res, setRes] = useState(kernel.resources);
  const [selectedPid, setSelectedPid] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'processes' | 'performance' | 'details'>('processes');
  const [cpuHistory, setCpuHistory] = useState<number[]>(new Array(60).fill(0));
  const [memHistory, setMemHistory] = useState<number[]>(new Array(60).fill(0));
  const [showWarning, setShowWarning] = useState<number | null>(null);
  const [showRunTask, setShowRunTask] = useState(false);
  const [runTaskCmd, setRunTaskCmd] = useState('');

  // Performance Monitoring Loop — 1 sample/second para o histórico (60s de janela)
  useEffect(() => {
    let lastCpuSample = 0;
    let lastMemSample = 0;

    const unsubCpu = kernel.on('cpuChange', (info) => {
      setRes(prev => ({ ...prev, cpuUsage: info.cpuUsage }));
      const now = Date.now();
      if (now - lastCpuSample >= 1000) {
        lastCpuSample = now;
        setCpuHistory(prev => [...prev.slice(1), info.cpuUsage]);
      }
    });

    const unsubMem = kernel.on('memoryChange', (info) => {
      setRes(prev => ({ ...prev, usedMemory: info.usedMemory, totalMemory: info.totalMemory }));
      const now = Date.now();
      if (now - lastMemSample >= 1000) {
        lastMemSample = now;
        setMemHistory(prev => [...prev.slice(1), info.usedMemory]);
      }
    });

    return () => { unsubCpu(); unsubMem(); };
  }, []);

  const handleEndTask = (pid: number) => {
    const proc = processes.find(p => p.pid === pid);
    if (!proc) return;

    if (pid < 10 && showWarning !== pid) {
      setShowWarning(pid);
      return;
    }

    terminateProcess(pid);
    setSelectedPid(null);
    setShowWarning(null);
  };

  const handleRunTask = () => {
    if (!runTaskCmd) return;
    // Command execution logic
    const name = runTaskCmd.toLowerCase().trim();
    if (name === 'explorer.obx' || name === 'explorer') {
      useProcessManager.getState().createProcess('explorer.obx', 'Windows Explorer', '📁');
    } else if (name === 'regedit' || name === 'regedit.obx') {
       // Ideally we'd trigger the window opening here.
       // For now, let's just create the process.
       useProcessManager.getState().createProcess('regedit.obx', 'Editor do Registro', '🧊');
    }
    setRunTaskCmd('');
    setShowRunTask(false);
  };

  const renderGraph = (data: number[], max: number, color: string) => {
    const w = 300, h = 80;
    const points = data.map((val, i) => {
      const x = (i / (data.length - 1)) * w;
      const y = h - (val / max) * h;
      return `${x},${y}`;
    }).join(' ');
    
    return (
      <svg width={w} height={h} className="perf-graph">
        <defs>
          <linearGradient id={`grad-${color}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.3"/>
            <stop offset="100%" stopColor={color} stopOpacity="0.05"/>
          </linearGradient>
        </defs>
        <rect width={w} height={h} fill="rgba(255,255,255,0.02)" rx="4"/>
        {/* Grid */}
        {[0.25, 0.5, 0.75].map(r => (
          <line key={r} x1="0" y1={h * r} x2={w} y2={h * r} stroke="rgba(255,255,255,0.06)" strokeDasharray="2"/>
        ))}
        <polygon points={`0,${h} ${points} ${w},${h}`} fill={`url(#grad-${color})`}/>
        <polyline points={points} fill="none" stroke={color} strokeWidth="1.5"/>
      </svg>
    );
  };

  return (
    <div className="task-manager">
      {/* Menu Bar */}
      <div className="tm-menubar">
        <button onClick={() => setShowRunTask(true)}>Arquivo</button>
        <button>Opções</button>
        <button>Exibir</button>
      </div>

      {/* Tabs */}
      <div className="tm-tabs">
        <button className={`tm-tab ${activeTab === 'processes' ? 'active' : ''}`} onClick={() => setActiveTab('processes')}>Processos</button>
        <button className={`tm-tab ${activeTab === 'performance' ? 'active' : ''}`} onClick={() => setActiveTab('performance')}>Desempenho</button>
        <button className={`tm-tab ${activeTab === 'details' ? 'active' : ''}`} onClick={() => setActiveTab('details')}>Detalhes</button>
      </div>

      {/* Content */}
      {activeTab === 'processes' && (
        <div className="tm-content">
          <table className="tm-table">
            <thead>
              <tr>
                <th>Nome</th>
                <th>Status</th>
                <th>CPU</th>
                <th>Memória</th>
              </tr>
            </thead>
            <tbody>
              {processes.map(p => (
                <tr
                  key={p.pid}
                  className={`tm-row ${selectedPid === p.pid ? 'selected' : ''}`}
                  onClick={() => setSelectedPid(p.pid)}
                >
                  <td>
                    <span className="tm-proc-icon">{p.icon}</span>
                    <span className="proc-name-text">{p.name} {p.pid < 10 && <span className="p-sys-tag">Sistema</span>}</span>
                  </td>
                  <td>
                    <span className={`tm-status ${p.status}`}>{p.status === 'running' ? 'Em execução' : p.status === 'suspended' ? 'Suspenso' : 'Parado'}</span>
                  </td>
                  <td>{p.cpuUsage.toFixed(1)}%</td>
                  <td>{p.memoryUsage.toFixed(1)} MB</td>
                </tr>
              ))}
            </tbody>
          </table>
          
          <div className="tm-footer">
            <button
              className="tm-end-task"
              disabled={selectedPid === null}
              onClick={() => selectedPid !== null && handleEndTask(selectedPid)}
            >
              Finalizar tarefa
            </button>
          </div>
        </div>
      )}

      {/* Run Task Modal */}
      {showRunTask && (
        <div className="tm-modal-overlay">
          <div className="tm-modal">
            <div className="tm-modal-header">Criar nova tarefa</div>
            <div className="tm-modal-body">
              <p>Digite o nome do programa que você deseja abrir.</p>
              <input 
                type="text" 
                autoFocus 
                value={runTaskCmd} 
                onChange={e => setRunTaskCmd(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleRunTask()}
              />
            </div>
            <div className="tm-modal-footer">
              <button onClick={handleRunTask}>OK</button>
              <button onClick={() => setShowRunTask(false)}>Cancelar</button>
            </div>
          </div>
        </div>
      )}

      {/* Warning Modal */}
      {showWarning !== null && (
        <div className="tm-modal-overlay">
          <div className="tm-modal warning">
            <div className="tm-modal-header">Deseja finalizar o processo de sistema?</div>
            <div className="tm-modal-body">
              <p>Finalizar o processo <b>{processes.find(p => p.pid === showWarning)?.name}</b> fará com que o sistema operacional se torne instável ou pare de funcionar, resultando em perda de dados não salvos.</p>
              <p>Deseja continuar?</p>
            </div>
            <div className="tm-modal-footer">
              <button className="danger" onClick={() => handleEndTask(showWarning!)}>Finalizar Processo</button>
              <button onClick={() => setShowWarning(null)}>Cancelar</button>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'performance' && (
        <div className="tm-performance">
          <div className="perf-card">
            <div className="perf-header">
              <span className="perf-label">CPU</span>
              <span className="perf-value">{res.cpuUsage.toFixed(1)}%</span>
            </div>
            {renderGraph(cpuHistory, 100, '#6366f1')}
            <div className="perf-details">
              <div><span>Utilização</span><span>{res.cpuUsage.toFixed(1)}%</span></div>
              <div><span>Processos</span><span>{processes.length}</span></div>
              <div><span>Threads</span><span>{processes.length * 4}</span></div>
              <div><span>Velocidade</span><span>3.60 GHz</span></div>
            </div>
          </div>
          
          <div className="perf-card">
            <div className="perf-header">
              <span className="perf-label">Memória</span>
              <span className="perf-value">{res.usedMemory.toFixed(0)} MB</span>
            </div>
            {renderGraph(memHistory, res.totalMemory, '#22c55e')}
            <div className="perf-details">
              <div><span>Em uso</span><span>{res.usedMemory.toFixed(0)} MB</span></div>
              <div><span>Disponível</span><span>{(res.totalMemory - res.usedMemory).toFixed(0)} MB</span></div>
              <div><span>Total</span><span>{res.totalMemory.toLocaleString()} MB</span></div>
              <div><span>Commitada</span><span>{(res.usedMemory * 1.2).toFixed(0)} MB</span></div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'details' && (
        <div className="tm-content">
          <table className="tm-table">
            <thead>
              <tr>
                <th>Nome</th>
                <th>PID</th>
                <th>Status</th>
                <th>CPU</th>
                <th>Memória</th>
              </tr>
            </thead>
            <tbody>
              {processes.map(p => (
                <tr key={p.pid} className="tm-row">
                  <td>{p.name}</td>
                  <td>{p.pid}</td>
                  <td>{p.status}</td>
                  <td>{p.cpuUsage.toFixed(1)}%</td>
                  <td>{p.memoryUsage.toFixed(1)} MB</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
