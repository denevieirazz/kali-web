import React, { useState, useEffect, useCallback } from 'react';
import { API_BASE } from '../config';

export function DashboardApp({ openApp }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  const getToken = () => localStorage.getItem('cloudos_token');

  const fetchSummary = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/api/dashboard/summary`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const result = await res.json();
      setData(result);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSummary();
    const interval = setInterval(fetchSummary, 15000); // Atualiza a cada 15s
    return () => clearInterval(interval);
  }, [fetchSummary]);

  // Atalhos rápidos para leigos
  const quickActions = [
    { id: 'metasploit', icon: '⚡', name: 'Metasploit', desc: 'Lançar exploits e ataques', color: '#58a6ff' },
    { id: 'doctor', icon: '🩺', name: 'Doctor', desc: 'Verificar saúde do sistema', color: '#3fb950' },
    { id: 'findings', icon: '🛡️', name: 'Vulnerabilidades', desc: 'Cadastrar falhas encontradas', color: '#d29922' },
    { id: 'report', icon: '📄', name: 'Relatórios', desc: 'Gerar documento final', color: '#bc8cff' },
    { id: 'networkmanager', icon: '🌐', name: 'Rede', desc: 'Controlar serviços e portas', color: '#f85149' },
    { id: 'terminal', icon: '💻', name: 'Terminal', desc: 'Acesso direto ao Kali Linux', color: '#8b949e' }
  ];

  if (loading && !data) {
    return <div style={styles.loading}>Carregando painel tático...</div>;
  }

  const findings = data?.findings || { critical: 0, high: 0, medium: 0, low: 0, total: 0 };

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h1 style={styles.title}>🎯 Command Center</h1>
        <span style={styles.subtitle}>Visão geral e acesso rápido às operações</span>
      </div>

      {/* MÉTRICAS SUPERIORES */}
      <div style={styles.metricsRow}>
        
        {/* Card de Vulnerabilidades */}
        <div style={styles.metricCard} onClick={() => openApp?.('findings')}>
          <div style={styles.metricTitle}>🛡️ Vulnerabilidades</div>
          <div style={styles.metricValue}>{findings.total}</div>
          <div style={styles.metricDetails}>
            <span style={{ ...styles.badge, background: 'rgba(248,81,73,0.2)', color: '#f85149' }}>Crit: {findings.critical}</span>
            <span style={{ ...styles.badge, background: 'rgba(210,153,34,0.2)', color: '#d29922' }}>Alta: {findings.high}</span>
            <span style={{ ...styles.badge, background: 'rgba(88,166,255,0.2)', color: '#58a6ff' }}>Méd: {findings.medium}</span>
            <span style={{ ...styles.badge, background: 'rgba(139,148,158,0.2)', color: '#8b949e' }}>Baixa: {findings.low}</span>
          </div>
        </div>

        {/* Card de Sistema */}
        <div style={styles.metricCard}>
          <div style={styles.metricTitle}>⚙️ Sistema Kali</div>
          <div style={styles.sysInfoGrid}>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysLabel}>Memória RAM</span>
              <span style={styles.sysValue}>{data?.system?.memory || 'N/A'}</span>
            </div>
            <div style={styles.sysInfoItem}>
              <span style={styles.sysLabel}>Disco WSL2</span>
              <span style={styles.sysValue}>{data?.system?.disk || 'N/A'}</span>
            </div>
          </div>
        </div>

        {/* Card Metasploit */}
        <div style={styles.metricCard}>
          <div style={styles.metricTitle}>⚡ Metasploit RPC</div>
          <div style={styles.msfStatus}>
            <div style={{
              ...styles.statusDot,
              background: data?.msfStatus === 'online' ? '#3fb950' : '#484f58',
              boxShadow: data?.msfStatus === 'online' ? '0 0 10px #3fb950' : 'none'
            }} />
            <span style={{ color: data?.msfStatus === 'online' ? '#3fb950' : '#8b949e' }}>
              {data?.msfStatus === 'online' ? 'ONLINE E PRONTO' : 'DESLIGADO'}
            </span>
          </div>
          {data?.msfStatus !== 'online' && (
            <button style={styles.btnAction} onClick={() => openApp?.('metasploit')}>
              Iniciar Daemon
            </button>
          )}
        </div>
      </div>

      {/* ATALHOS RÁPIDOS */}
      <div style={styles.sectionTitle}>🚀 Ações Rápidas</div>
      <div style={styles.quickGrid}>
        {quickActions.map(action => (
          <div 
            key={action.id} 
            style={styles.quickCard}
            onClick={() => openApp?.(action.id)}
          >
            <div style={{ fontSize: '32px', marginBottom: '10px' }}>{action.icon}</div>
            <div style={{ color: action.color, fontSize: '14px', fontWeight: 'bold', fontFamily: 'monospace' }}>
              {action.name}
            </div>
            <div style={{ color: '#8b949e', fontSize: '11px', marginTop: '4px', textAlign: 'center' }}>
              {action.desc}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// Design System (Glassmorphism)
const styles = {
  container: {
    padding: '24px',
    height: '100%',
    overflowY: 'auto',
    background: '#0d1117',
    fontFamily: 'sans-serif'
  },
  loading: {
    display: 'flex',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#58a6ff',
    fontSize: '16px'
  },
  header: {
    marginBottom: '24px',
    borderBottom: '1px solid #30363d',
    paddingBottom: '16px'
  },
  title: {
    color: '#58a6ff',
    fontSize: '24px',
    margin: '0 0 4px 0'
  },
  subtitle: {
    color: '#8b949e',
    fontSize: '12px'
  },
  metricsRow: {
    display: 'flex',
    gap: '16px',
    marginBottom: '32px',
    flexWrap: 'wrap'
  },
  metricCard: {
    flex: '1',
    minWidth: '250px',
    background: 'rgba(22, 27, 34, 0.8)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '20px',
    cursor: 'pointer',
    transition: 'border-color 0.2s, transform 0.2s',
  },
  metricTitle: {
    color: '#8b949e',
    fontSize: '12px',
    fontWeight: 'bold',
    marginBottom: '12px',
    letterSpacing: '1px'
  },
  metricValue: {
    color: '#c9d1d9',
    fontSize: '36px',
    fontWeight: 'bold',
    marginBottom: '12px'
  },
  metricDetails: {
    display: 'flex',
    gap: '6px',
    flexWrap: 'wrap'
  },
  badge: {
    padding: '4px 8px',
    borderRadius: '4px',
    fontSize: '10px',
    fontWeight: 'bold'
  },
  sysInfoGrid: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px'
  },
  sysInfoItem: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderBottom: '1px solid #30363d',
    paddingBottom: '8px'
  },
  sysLabel: {
    color: '#8b949e',
    fontSize: '12px'
  },
  sysValue: {
    color: '#c9d1d9',
    fontSize: '14px',
    fontWeight: 'bold'
  },
  msfStatus: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    marginBottom: '12px',
    fontSize: '14px',
    fontWeight: 'bold'
  },
  statusDot: {
    width: '12px',
    height: '12px',
    borderRadius: '50%'
  },
  btnAction: {
    background: 'rgba(88, 166, 255, 0.15)',
    color: '#58a6ff',
    border: '1px solid #58a6ff',
    padding: '8px 12px',
    borderRadius: '6px',
    cursor: 'pointer',
    fontSize: '12px',
    fontFamily: 'sans-serif',
    fontWeight: 'bold',
    width: '100%'
  },
  sectionTitle: {
    color: '#8b949e',
    fontSize: '14px',
    fontWeight: 'bold',
    marginBottom: '16px',
    letterSpacing: '1px'
  },
  quickGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))',
    gap: '16px'
  },
  quickCard: {
    background: 'rgba(22, 27, 34, 0.6)',
    backdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '20px',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
  }
};

export default DashboardApp;
