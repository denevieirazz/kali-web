import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { API_BASE } from '../config';

const CATEGORY_ICONS = {
  'Reconhecimento': '🛰️',
  'Exploração':     '💥',
  'Brute Force':    '🔨',
  'Criptografia':   '🔐',
  'Sniffing':       '📡',
  'Web':            '🌐',
  'Rede':           '🔌',
  'Wireless':       '📶',
  'OSINT':          '🔍',
  'Base':           '⚙️'
};

export function EnvironmentDoctorApp() {
  const [loading, setLoading] = useState(true);
  const [scanning, setScanning] = useState(false);
  const [data, setData] = useState(null);
  const [installing, setInstalling] = useState({});
  const [installStatus, setInstallStatus] = useState({});
  const [updating, setUpdating] = useState(false);
  const [installingAll, setInstallingAll] = useState(false);
  const [error, setError] = useState(null);
  const [lastScan, setLastScan] = useState(null);

  const getToken = () => localStorage.getItem('cloudos_token');

  const runDiagnostic = useCallback(async () => {
    setScanning(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/environment/check`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      if (!res.ok) throw new Error('Falha no diagnóstico');
      const result = await res.json();
      setData(result);
      setLastScan(new Date());
    } catch (err) {
      setError(err.message);
    } finally {
      setScanning(false);
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    runDiagnostic();
  }, [runDiagnostic]);

  const handleInstall = async (toolName) => {
    setInstalling(prev => ({ ...prev, [toolName]: true }));
    setInstallStatus(prev => ({ ...prev, [toolName]: 'loading' }));
    try {
      const res = await fetch(`${API_BASE}/api/environment/install/${toolName}`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const result = await res.json();
      if (result.success) {
        setInstallStatus(prev => ({ ...prev, [toolName]: 'success' }));
        setData(prev => {
          if (!prev) return prev;
          const newInstalled = prev.summary.installed + 1;
          const newMissing = prev.summary.missing - 1;
          return {
            ...prev,
            tools: (prev.tools || []).map(t =>
              t.name === toolName ? { ...t, installed: true } : t
            ),
            summary: {
              ...prev.summary,
              installed: newInstalled,
              missing: newMissing,
              healthScore: Math.round((newInstalled / prev.summary.total) * 100)
            }
          };
        });
      } else {
        setInstallStatus(prev => ({ ...prev, [toolName]: 'error' }));
      }
    } catch (err) {
      setInstallStatus(prev => ({ ...prev, [toolName]: 'error' }));
    } finally {
      setInstalling(prev => ({ ...prev, [toolName]: false }));
    }
  };

  const handleInstallAllMissing = async () => {
    setInstallingAll(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/environment/install-all-missing`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const result = await res.json();
      if (result.success) {
        await runDiagnostic();
      } else {
        setError('Falha ao instalar ferramentas');
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setInstallingAll(false);
    }
  };

  const handleUpdate = async () => {
    setUpdating(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/api/environment/update`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const result = await res.json();
      if (result.success) {
        setTimeout(() => runDiagnostic(), 500);
      } else {
        setError('Falha ao atualizar sistema');
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setUpdating(false);
    }
  };

  // Agrupar ferramentas por categoria
  const groupedTools = useMemo(() => {
    if (!data?.tools) return {};
    return (data.tools || []).reduce((acc, tool) => {
      if (!acc[tool.category]) acc[tool.category] = [];
      acc[tool.category].push(tool);
      return acc;
    }, {});
  }, [data]);

  const getHealthColor = (score) => {
    if (score >= 80) return '#3fb950';
    if (score >= 50) return '#d29922';
    return '#f85149';
  };

  const getUsageColor = (percentStr) => {
    const num = parseInt(percentStr);
    if (isNaN(num)) return '#58a6ff';
    if (num >= 85) return '#f85149';
    if (num >= 70) return '#d29922';
    return '#3fb950';
  };

  const formatMemory = (mb) => {
    if (!mb || isNaN(mb)) return 'N/A';
    if (mb >= 1024) return `${(mb / 1024).toFixed(1)}GB`;
    return `${mb}MB`;
  };

  // Gauge de Health Score (SVG circular)
  const HealthGauge = ({ score }) => {
    const radius = 45;
    const circumference = 2 * Math.PI * radius;
    const offset = circumference - (score / 100) * circumference;
    const color = getHealthColor(score);

    return (
      <svg width="120" height="120" viewBox="0 0 120 120" style={{ flexShrink: 0 }}>
        <circle cx="60" cy="60" r={radius} fill="none" stroke="#30363d" strokeWidth="8" />
        <circle
          cx="60" cy="60" r={radius}
          fill="none"
          stroke={color}
          strokeWidth="8"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          strokeLinecap="round"
          transform="rotate(-90 60 60)"
          style={{ transition: 'stroke-dashoffset 0.8s ease, stroke 0.3s ease' }}
        />
        <text x="60" y="58" textAnchor="middle" fill={color} fontSize="22" fontWeight="bold" fontFamily="monospace">
          {score}%
        </text>
        <text x="60" y="76" textAnchor="middle" fill="#8b949e" fontSize="9" fontFamily="monospace">
          HEALTH
        </text>
      </svg>
    );
  };

  // Barra de uso de recurso
  const ResourceBar = ({ label, used, total, percent, color }) => (
    <div style={{ flex: 1, minWidth: '200px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
        <span style={{ color: '#8b949e', fontSize: '12px', fontFamily: 'monospace' }}>{label}</span>
        <span style={{ color: '#c9d1d9', fontSize: '12px', fontFamily: 'monospace' }}>
          {used} / {total} ({percent})
        </span>
      </div>
      <div style={{
        height: '8px',
        background: '#21262d',
        borderRadius: '4px',
        overflow: 'hidden',
        border: '1px solid #30363d'
      }}>
        <div style={{
          height: '100%',
          width: percent,
          background: color,
          borderRadius: '4px',
          transition: 'width 0.6s ease, background 0.3s ease'
        }} />
      </div>
    </div>
  );

  if (loading) {
    return (
      <div style={styles.container}>
        <div style={styles.loadingBox}>
          <div style={{ fontSize: '48px', marginBottom: '16px' }}>🩺</div>
          <div style={{ color: '#58a6ff', fontFamily: 'monospace', fontSize: '14px' }}>
            Diagnosticando ambiente tático...
          </div>
          <div style={styles.loadingBar} />
        </div>
      </div>
    );
  }

  const diskPercent = data?.disk?.usePercent || '0%';
  const diskColor = getUsageColor(diskPercent);
  const memPercent = data?.memory ? Math.round((data.memory.used / data.memory.total) * 100) + '%' : '0%';
  const memColor = getUsageColor(memPercent);

  return (
    <div style={styles.container}>
      {/* HEADER */}
      <div style={styles.header}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ fontSize: '32px' }}>🩺</div>
          <div>
            <h2 style={styles.title}>Environment Doctor</h2>
            <p style={styles.subtitle}>
              {lastScan
                ? `Último diagnóstico: ${lastScan.toLocaleTimeString('pt-BR')}`
                : 'Aguardando diagnóstico...'}
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', gap: '8px' }}>
          <button
            onClick={runDiagnostic}
            disabled={scanning}
            style={{
              ...styles.btn,
              ...(scanning ? styles.btnDisabled : styles.btnPrimary)
            }}
          >
            {scanning ? '⏳ Escaneando...' : '🔍 Rodar Diagnóstico'}
          </button>
          <button
            onClick={handleUpdate}
            disabled={updating}
            style={{
              ...styles.btn,
              ...(updating ? styles.btnDisabled : styles.btnSecondary)
            }}
          >
            {updating ? '⏳ Atualizando...' : '📦 Atualizar Sistema'}
          </button>
          <button
            onClick={handleInstallAllMissing}
            disabled={installingAll || data?.summary?.missing === 0}
            style={{
              ...styles.btn,
              ...(installingAll || data?.summary?.missing === 0 ? styles.btnDisabled : styles.btnDanger)
            }}
          >
            {installingAll ? '⏳ Instalando...' : `⚡ Instalar ${data?.summary?.missing || 0} Faltantes`}
          </button>
        </div>
      </div>

      {/* ERRO */}
      {error && (
        <div style={styles.errorBanner}>
          ⚠️ {error}
        </div>
      )}

      {/* PAINEL SUPERIOR: Gauge + System Info + Resources */}
      <div style={styles.topPanel}>
        {/* Health Score Gauge */}
        <div style={styles.gaugeCard}>
          <HealthGauge score={data?.summary?.healthScore || 0} />
          <div style={{ textAlign: 'center', marginTop: '8px' }}>
            <span style={{ color: '#8b949e', fontSize: '11px', fontFamily: 'monospace' }}>
              {data?.summary?.installed || 0}/{data?.summary?.total || 0} ferramentas
            </span>
          </div>
        </div>

        {/* System Info */}
        <div style={styles.sysInfoCard}>
          <div style={styles.sysInfoTitle}>⚙️ SISTEMA</div>
          <div style={styles.sysInfoGrid}>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysInfoLabel}>Kernel</span>
              <span style={styles.sysInfoValue}>{data?.system?.kernel || 'N/A'}</span>
            </div>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysInfoLabel}>Distro</span>
              <span style={styles.sysInfoValue}>{data?.system?.distro || 'N/A'}</span>
            </div>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysInfoLabel}>Uptime</span>
              <span style={styles.sysInfoValue}>{data?.system?.uptime || 'N/A'}</span>
            </div>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysInfoLabel}>CPUs</span>
              <span style={styles.sysInfoValue}>{data?.system?.cpus || 'N/A'}</span>
            </div>
          </div>
        </div>

        {/* Resources */}
        <div style={styles.resourceCard}>
          <div style={styles.sysInfoTitle}>📊 RECURSOS</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginTop: '12px' }}>
            <ResourceBar
              label="Disco WSL2"
              used={data?.disk?.used || 'N/A'}
              total={data?.disk?.size || 'N/A'}
              percent={diskPercent}
              color={diskColor}
            />
            <ResourceBar
              label="Memória RAM"
              used={formatMemory(data?.memory?.used)}
              total={formatMemory(data?.memory?.total)}
              percent={memPercent}
              color={memColor}
            />
          </div>
        </div>
      </div>

      {/* TOOL GRID */}
      <div style={styles.toolsSection}>
        {Object.entries(groupedTools).map(([category, tools]) => {
          const catInstalled = tools.filter(t => t.installed).length;
          const catTotal = tools.length;
          const catColor = catInstalled === catTotal
            ? '#3fb950'
            : catInstalled === 0
              ? '#f85149'
              : '#d29922';

          return (
            <div key={category} style={styles.categoryBlock}>
              <div style={styles.categoryHeader}>
                <span style={{ fontSize: '16px' }}>
                  {CATEGORY_ICONS[category] || '🔧'}
                </span>
                <span style={styles.categoryName}>{category}</span>
                <span style={{
                  ...styles.categoryBadge,
                  color: catColor,
                  borderColor: catColor
                }}>
                  {catInstalled}/{catTotal}
                </span>
              </div>

              <div style={styles.toolGrid}>
                {(tools || []).map(tool => {
                  const isInstalling = installing[tool.name];
                  const status = installStatus[tool.name];

                  return (
                    <div
                      key={tool.name}
                      style={{
                        ...styles.toolCard,
                        borderColor: tool.installed ? '#238636' : status === 'error' ? '#f85149' : '#30363d'
                      }}
                    >
                      <div style={styles.toolCardHeader}>
                        <span style={{
                          fontSize: '16px',
                          fontFamily: 'monospace',
                          fontWeight: 'bold',
                          color: tool.installed ? '#3fb950' : '#c9d1d9'
                        }}>
                          {tool.installed ? '✅' : '❌'} {tool.name}
                        </span>
                      </div>

                      <p style={styles.toolDesc}>{tool.description}</p>

                      <div style={styles.toolFooter}>
                        {tool.installed ? (
                          <span style={styles.installedBadge}>INSTALADO</span>
                        ) : isInstalling ? (
                          <span style={styles.installingBadge}>
                            <span style={styles.spinner} /> INSTALANDO...
                          </span>
                        ) : status === 'success' ? (
                          <span style={styles.installedBadge}>✓ OK</span>
                        ) : status === 'error' ? (
                          <button
                            onClick={() => handleInstall(tool.name)}
                            style={styles.btnRetry}
                          >
                            ↻ Tentar Novamente
                          </button>
                        ) : (
                          <button
                            onClick={() => handleInstall(tool.name)}
                            style={styles.btnInstall}
                          >
                            ⬇ Instalar
                          </button>
                        )}

                        <span style={styles.pkgName}>{tool.package}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Design System
const styles = {
  container: {
    padding: '20px',
    height: '100%',
    overflowY: 'auto',
    background: '#0d1117',
    fontFamily: 'monospace'
  },
  loadingBox: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    gap: '12px'
  },
  loadingBar: {
    width: '200px',
    height: '4px',
    background: '#30363d',
    borderRadius: '2px',
    overflow: 'hidden',
    position: 'relative'
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '20px',
    flexWrap: 'wrap',
    gap: '12px'
  },
  title: {
    color: '#58a6ff',
    fontSize: '22px',
    margin: '0',
    fontWeight: 'bold'
  },
  subtitle: {
    color: '#8b949e',
    fontSize: '12px',
    margin: '2px 0 0 0'
  },
  btn: {
    padding: '8px 14px',
    borderRadius: '6px',
    fontSize: '12px',
    fontFamily: 'monospace',
    fontWeight: 'bold',
    cursor: 'pointer',
    border: '1px solid',
    transition: 'all 0.2s ease',
    whiteSpace: 'nowrap'
  },
  btnPrimary: {
    background: 'rgba(88, 166, 255, 0.15)',
    color: '#58a6ff',
    borderColor: '#58a6ff'
  },
  btnSecondary: {
    background: 'rgba(139, 148, 158, 0.15)',
    color: '#c9d1d9',
    borderColor: '#8b949e'
  },
  btnDanger: {
    background: 'rgba(248, 81, 73, 0.15)',
    color: '#f85149',
    borderColor: '#f85149'
  },
  btnDisabled: {
    background: '#21262d',
    color: '#484f58',
    borderColor: '#30363d',
    cursor: 'not-allowed'
  },
  errorBanner: {
    background: 'rgba(248, 81, 73, 0.1)',
    border: '1px solid #f85149',
    color: '#f85149',
    padding: '10px 16px',
    borderRadius: '6px',
    marginBottom: '16px',
    fontSize: '13px',
    fontFamily: 'monospace'
  },
  topPanel: {
    display: 'flex',
    gap: '16px',
    marginBottom: '24px',
    flexWrap: 'wrap'
  },
  gaugeCard: {
    background: 'rgba(22, 27, 34, 0.8)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '16px',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: '160px'
  },
  sysInfoCard: {
    background: 'rgba(22, 27, 34, 0.8)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '16px',
    flex: '1',
    minWidth: '260px'
  },
  resourceCard: {
    background: 'rgba(22, 27, 34, 0.8)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '16px',
    flex: '1',
    minWidth: '260px'
  },
  sysInfoTitle: {
    color: '#8b949e',
    fontSize: '11px',
    fontWeight: 'bold',
    letterSpacing: '1px',
    marginBottom: '12px'
  },
  sysInfoGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '10px'
  },
  sysInfoItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: '2px'
  },
  sysInfoLabel: {
    color: '#8b949e',
    fontSize: '10px'
  },
  sysInfoValue: {
    color: '#c9d1d9',
    fontSize: '13px',
    fontWeight: 'bold'
  },
  toolsSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: '20px'
  },
  categoryBlock: {
    background: 'rgba(22, 27, 34, 0.6)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '16px'
  },
  categoryHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '12px',
    paddingBottom: '10px',
    borderBottom: '1px solid #30363d'
  },
  categoryName: {
    color: '#c9d1d9',
    fontSize: '14px',
    fontWeight: 'bold',
    fontFamily: 'monospace',
    letterSpacing: '0.5px'
  },
  categoryBadge: {
    marginLeft: 'auto',
    fontSize: '11px',
    fontFamily: 'monospace',
    fontWeight: 'bold',
    padding: '2px 8px',
    borderRadius: '4px',
    border: '1px solid'
  },
  toolGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
    gap: '10px'
  },
  toolCard: {
    background: 'rgba(13, 17, 23, 0.6)',
    border: '1px solid #30363d',
    borderRadius: '8px',
    padding: '12px',
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    transition: 'border-color 0.2s ease'
  },
  toolCardHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  toolDesc: {
    color: '#8b949e',
    fontSize: '11px',
    margin: '0',
    flex: '1'
  },
  toolFooter: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '8px'
  },
  installedBadge: {
    background: 'rgba(63, 185, 80, 0.15)',
    color: '#3fb950',
    fontSize: '10px',
    fontWeight: 'bold',
    padding: '4px 8px',
    borderRadius: '4px',
    fontFamily: 'monospace'
  },
  installingBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    color: '#58a6ff',
    fontSize: '10px',
    fontWeight: 'bold',
    fontFamily: 'monospace'
  },
  spinner: {
    display: 'inline-block',
    width: '10px',
    height: '10px',
    border: '2px solid #30363d',
    borderTopColor: '#58a6ff',
    borderRadius: '50%',
    animation: 'spin 0.8s linear infinite'
  },
  btnInstall: {
    background: 'rgba(88, 166, 255, 0.15)',
    color: '#58a6ff',
    border: '1px solid #58a6ff',
    borderRadius: '4px',
    padding: '4px 10px',
    fontSize: '11px',
    fontFamily: 'monospace',
    fontWeight: 'bold',
    cursor: 'pointer',
    transition: 'all 0.2s ease'
  },
  btnRetry: {
    background: 'rgba(210, 153, 34, 0.15)',
    color: '#d29922',
    border: '1px solid #d29922',
    borderRadius: '4px',
    padding: '4px 10px',
    fontSize: '11px',
    fontFamily: 'monospace',
    fontWeight: 'bold',
    cursor: 'pointer'
  },
  pkgName: {
    color: '#484f58',
    fontSize: '9px',
    fontFamily: 'monospace',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    maxWidth: '80px'
  }
};

export default EnvironmentDoctorApp;
