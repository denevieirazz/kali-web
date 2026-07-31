import React, { useState, useEffect, useRef, useCallback } from 'react';
import { 
  Activity, Cpu, MemoryStick, Trash2, RefreshCw, 
  Search, AlertTriangle, User, Terminal, X 
} from 'lucide-react';

const API_BASE = 'http://localhost:8080/api';

export default function TaskManagerApp({ payload, setPayload, openApp, setBg }) {
  const [processes, setProcesses] = useState([]);
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [sortField, setSortField] = useState('cpu');
  const [sortDir, setSortDir] = useState('desc');
  const [selectedPid, setSelectedPid] = useState(null);
  const [killConfirm, setKillConfirm] = useState(null);
  const [error, setError] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const intervalRef = useRef(null);

  const getHeaders = () => {
    const token = localStorage.getItem('cloudos_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };
  };

  // Busca processos e stats
  const fetchData = useCallback(async () => {
    try {
      const headers = getHeaders();
      const [procRes, statsRes] = await Promise.all([
        fetch(`${API_BASE}/processes`, { headers }),
        fetch(`${API_BASE}/processes/stats/summary`, { headers })
      ]);

      if (!procRes.ok) throw new Error('Falha ao buscar processos');
      
      const procData = await procRes.json();
      const statsData = statsRes.ok ? await statsRes.json() : null;

      if (procData.success) {
        setProcesses(procData.processes || []);
      }
      if (statsData?.success) {
        setStats(statsData.stats);
      }
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // Auto-refresh a cada 3 segundos
  useEffect(() => {
    fetchData();
    if (autoRefresh) {
      intervalRef.current = setInterval(fetchData, 3000);
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [fetchData, autoRefresh]);

  // Mata processo
  const handleKillProcess = async (pid) => {
    try {
      const res = await fetch(`${API_BASE}/processes/${pid}`, {
        method: 'DELETE',
        headers: getHeaders()
      });
      const data = await res.json();
      
      if (data.success) {
        setProcesses(prev => prev.filter(p => p.pid !== pid));
        setKillConfirm(null);
        setSelectedPid(null);
      } else {
        setError(data.error || 'Erro ao finalizar processo');
      }
    } catch (err) {
      setError(err.message);
    }
  };

  // Filtragem e ordenação
  const filteredProcesses = (processes || [])
    .filter(p => 
      p.command.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.user.toLowerCase().includes(searchTerm.toLowerCase()) ||
      String(p.pid).includes(searchTerm)
    )
    .sort((a, b) => {
      const aVal = a[sortField];
      const bVal = b[sortField];
      return sortDir === 'desc' ? bVal - aVal : aVal - bVal;
    });

  const toggleSort = (field) => {
    if (sortField === field) {
      setSortDir(prev => prev === 'desc' ? 'asc' : 'desc');
    } else {
      setSortField(field);
      setSortDir('desc');
    }
  };

  // Helper de cor para CPU/MEM
  const getResourceColor = (value) => {
    if (value >= 80) return '#f85149';
    if (value >= 50) return '#d29922';
    if (value >= 20) return '#58a6ff';
    return '#3fb950';
  };

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: '#0d1117',
      color: '#c9d1d9',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    }}>
      {/* ===== Header com Stats ===== */}
      <div style={{
        display: 'flex',
        gap: '12px',
        padding: '12px 16px',
        borderBottom: '1px solid #30363d',
        background: '#161b22',
        flexWrap: 'wrap',
        alignItems: 'center'
      }}>
        {/* CPU Load */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '6px 12px',
          background: '#21262d',
          borderRadius: '6px',
          border: '1px solid #30363d'
        }}>
          <Cpu size={16} color="#58a6ff" />
          <div>
            <div style={{ fontSize: '10px', color: '#8b949e', textTransform: 'uppercase' }}>Load Avg</div>
            <div style={{ fontSize: '13px', fontWeight: 600 }}>
              {stats?.loadAvg ? stats.loadAvg['1min'].toFixed(2) : '--'}
            </div>
          </div>
        </div>

        {/* Memória */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '6px 12px',
          background: '#21262d',
          borderRadius: '6px',
          border: '1px solid #30363d'
        }}>
          <MemoryStick size={16} color="#3fb950" />
          <div>
            <div style={{ fontSize: '10px', color: '#8b949e', textTransform: 'uppercase' }}>Memória</div>
            <div style={{ fontSize: '13px', fontWeight: 600 }}>
              {stats?.memory ? `${stats.memory.used}MB / ${stats.memory.total}MB` : '--'}
            </div>
          </div>
        </div>

        {/* Uptime */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '6px 12px',
          background: '#21262d',
          borderRadius: '6px',
          border: '1px solid #30363d'
        }}>
          <Activity size={16} color="#d29922" />
          <div>
            <div style={{ fontSize: '10px', color: '#8b949e', textTransform: 'uppercase' }}>Uptime</div>
            <div style={{ fontSize: '13px', fontWeight: 600 }}>
              {stats ? stats.uptime : '--'}
            </div>
          </div>
        </div>

        <div style={{ flex: 1 }} />

        {/* Auto-Refresh Toggle */}
        <button
          onClick={() => setAutoRefresh(prev => !prev)}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            padding: '6px 12px',
            background: autoRefresh ? '#238636' : '#21262d',
            border: '1px solid #30363d',
            borderRadius: '6px',
            color: '#c9d1d9',
            cursor: 'pointer',
            fontSize: '12px',
            fontWeight: 500
          }}
        >
          <RefreshCw size={14} className={autoRefresh ? 'spin' : ''} />
          {autoRefresh ? 'Auto' : 'Manual'}
        </button>

        <button
          onClick={fetchData}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            padding: '6px 12px',
            background: '#21262d',
            border: '1px solid #30363d',
            borderRadius: '6px',
            color: '#c9d1d9',
            cursor: 'pointer',
            fontSize: '12px'
          }}
        >
          <RefreshCw size={14} />
          Atualizar
        </button>
      </div>

      {/* ===== Barra de Busca ===== */}
      <div style={{
        padding: '8px 16px',
        borderBottom: '1px solid #30363d',
        display: 'flex',
        alignItems: 'center',
        gap: '8px'
      }}>
        <Search size={16} color="#8b949e" />
        <input
          type="text"
          placeholder="Buscar por nome, usuário ou PID..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          style={{
            flex: 1,
            background: '#0d1117',
            border: '1px solid #30363d',
            borderRadius: '6px',
            padding: '6px 10px',
            color: '#c9d1d9',
            fontSize: '13px',
            outline: 'none'
          }}
        />
        <span style={{ fontSize: '11px', color: '#8b949e' }}>
          {filteredProcesses.length} processos
        </span>
      </div>

      {/* ===== Erro ===== */}
      {error && (
        <div style={{
          margin: '8px 16px',
          padding: '8px 12px',
          background: 'rgba(248, 81, 73, 0.1)',
          border: '1px solid #f85149',
          borderRadius: '6px',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          fontSize: '12px',
          color: '#f85149'
        }}>
          <AlertTriangle size={14} />
          {error}
          <button onClick={() => setError(null)} style={{ marginLeft: 'auto', background: 'none', border: 'none', color: '#f85149', cursor: 'pointer' }}>
            <X size={14} />
          </button>
        </div>
      )}

      {/* ===== Tabela de Processos ===== */}
      <div style={{
        flex: 1,
        overflow: 'auto',
        padding: '0 16px'
      }}>
        <table style={{
          width: '100%',
          borderCollapse: 'collapse',
          fontSize: '12px'
        }}>
          <thead style={{
            position: 'sticky',
            top: 0,
            background: '#161b22',
            zIndex: 10
          }}>
            <tr style={{ borderBottom: '1px solid #30363d' }}>
              <th style={{ padding: '8px 6px', textAlign: 'left', cursor: 'pointer', color: '#8b949e' }} onClick={() => toggleSort('pid')}>
                PID {sortField === 'pid' && (sortDir === 'desc' ? '↓' : '↑')}
              </th>
              <th style={{ padding: '8px 6px', textAlign: 'left', cursor: 'pointer', color: '#8b949e' }} onClick={() => toggleSort('cpu')}>
                CPU% {sortField === 'cpu' && (sortDir === 'desc' ? '↓' : '↑')}
              </th>
              <th style={{ padding: '8px 6px', textAlign: 'left', cursor: 'pointer', color: '#8b949e' }} onClick={() => toggleSort('mem')}>
                MEM% {sortField === 'mem' && (sortDir === 'desc' ? '↓' : '↑')}
              </th>
              <th style={{ padding: '8px 6px', textAlign: 'left', color: '#8b949e' }}>
                <User size={12} style={{ verticalAlign: 'middle' }} /> Usuário
              </th>
              <th style={{ padding: '8px 6px', textAlign: 'left', color: '#8b949e' }}>
                Comando
              </th>
              <th style={{ padding: '8px 6px', textAlign: 'center', color: '#8b949e' }}>
                Ação
              </th>
            </tr>
          </thead>
          <tbody>
            {(filteredProcesses || []).map(proc => (
              <tr
                key={`${proc.pid}-${proc.command.slice(0, 10)}`}
                onClick={() => setSelectedPid(proc.pid === selectedPid ? null : proc.pid)}
                style={{
                  borderBottom: '1px solid #21262d',
                  cursor: 'pointer',
                  background: proc.pid === selectedPid ? 'rgba(88, 166, 255, 0.1)' : 'transparent',
                  transition: 'background 0.15s'
                }}
              >
                <td style={{ padding: '6px', color: '#58a6ff', fontFamily: 'monospace', fontWeight: 600 }}>
                  {proc.pid}
                </td>
                <td style={{ padding: '6px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <div style={{ width: '40px', textAlign: 'right', color: getResourceColor(proc.cpu), fontWeight: 600 }}>
                      {proc.cpu.toFixed(1)}
                    </div>
                    <div style={{ width: '50px', height: '4px', background: '#21262d', borderRadius: '2px', overflow: 'hidden' }}>
                      <div style={{
                        width: `${Math.min(proc.cpu, 100)}%`,
                        height: '100%',
                        background: getResourceColor(proc.cpu),
                        transition: 'width 0.3s'
                      }} />
                    </div>
                  </div>
                </td>
                <td style={{ padding: '6px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <div style={{ width: '40px', textAlign: 'right', color: getResourceColor(proc.mem), fontWeight: 600 }}>
                      {proc.mem.toFixed(1)}
                    </div>
                    <div style={{ width: '50px', height: '4px', background: '#21262d', borderRadius: '2px', overflow: 'hidden' }}>
                      <div style={{
                        width: `${Math.min(proc.mem, 100)}%`,
                        height: '100%',
                        background: getResourceColor(proc.mem),
                        transition: 'width 0.3s'
                      }} />
                    </div>
                  </div>
                </td>
                <td style={{ padding: '6px', color: '#8b949e' }}>
                  {proc.user}
                </td>
                <td style={{ padding: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '11px', maxWidth: '300px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {proc.command}
                </td>
                <td style={{ padding: '6px', textAlign: 'center' }}>
                  {killConfirm === proc.pid ? (
                    <div style={{ display: 'flex', gap: '4px', justifyContent: 'center' }}>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleKillProcess(proc.pid); }}
                        style={{
                          background: '#f85149',
                          border: 'none',
                          borderRadius: '4px',
                          padding: '2px 8px',
                          color: '#fff',
                          cursor: 'pointer',
                          fontSize: '10px',
                          fontWeight: 600
                        }}
                      >
                        Confirmar
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); setKillConfirm(null); }}
                        style={{
                          background: '#21262d',
                          border: '1px solid #30363d',
                          borderRadius: '4px',
                          padding: '2px 8px',
                          color: '#c9d1d9',
                          cursor: 'pointer',
                          fontSize: '10px'
                        }}
                      >
                        Cancelar
                      </button>
                    </div>
                  ) : (
                    <button
                      onClick={(e) => { e.stopPropagation(); setKillConfirm(proc.pid); }}
                      title="Finalizar processo"
                      style={{
                        background: 'none',
                        border: '1px solid #30363d',
                        borderRadius: '4px',
                        padding: '4px 6px',
                        color: '#f85149',
                        cursor: 'pointer',
                        opacity: proc.pid === selectedPid ? 1 : 0.4,
                        transition: 'opacity 0.2s'
                      }}
                    >
                      <Trash2 size={12} />
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {filteredProcesses.length === 0 && !loading && (
          <div style={{
            textAlign: 'center',
            padding: '40px',
            color: '#8b949e',
            fontSize: '13px'
          }}>
            {searchTerm ? 'Nenhum processo encontrado para a busca.' : 'Nenhum processo em execução.'}
          </div>
        )}
      </div>

      {/* ===== Footer Status ===== */}
      <div style={{
        padding: '6px 16px',
        borderTop: '1px solid #30363d',
        background: '#161b22',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        fontSize: '11px',
        color: '#8b949e'
      }}>
        <span>
          {stats ? `${stats.runningProcesses} processos ativos` : 'Carregando...'}
        </span>
        <span>
          Atualizado: {new Date().toLocaleTimeString('pt-BR')}
        </span>
      </div>

      {/* CSS para animação do spinner */}
      <style>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        .spin {
          animation: spin 1s linear infinite;
        }
      `}</style>
    </div>
  );
}
