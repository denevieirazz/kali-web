import { useState, useEffect } from 'react';
import { apiClient } from '../../services/apiClient';

export default function SystemMonitor({ windowId }: { windowId?: string }) {
  const [metrics, setMetrics] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    const fetchMetrics = async () => {
      try {
        const data = await apiClient('/api/system/metrics');
        if (mounted && data) {
          setMetrics(data);
          setLoading(false);
        }
      } catch (e) {
        if (mounted) setLoading(false);
      }
    };

    fetchMetrics();
    const interval = setInterval(fetchMetrics, 3000);
    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, []);

  return (
    <div style={{ height: '100%', width: '100%', display: 'flex', flexDirection: 'column', background: '#090618', color: '#ede9fe', padding: '24px', boxSizing: 'border-box', fontFamily: 'Inter, system-ui, sans-serif', overflowY: 'auto' }}>
      <div style={{ marginBottom: '20px' }}>
        <h3 style={{ margin: '0 0 6px 0', fontSize: '20px', fontWeight: 700, color: '#f8fafc' }}>
          📊 System Monitor — Métricas do Host em Tempo Real
        </h3>
        <p style={{ margin: 0, fontSize: '13px', color: '#94a3b8' }}>
          Monitoramento contínuo da CPU, memória RAM e subsistema operacional.
        </p>
      </div>

      {loading ? (
        <div style={{ padding: '32px', textAlign: 'center', color: '#c4b5fd' }}>
          <div className="spinner" style={{ margin: '0 auto 12px auto', width: '24px', height: '24px', border: '3px solid rgba(168,85,247,0.3)', borderTopColor: '#a855f7', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} />
          <span>Coletando métricas em tempo real...</span>
        </div>
      ) : metrics ? (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
          {/* Card CPU */}
          <div style={{ background: 'rgba(255, 255, 255, 0.03)', border: '1px solid rgba(168, 85, 247, 0.25)', borderRadius: '16px', padding: '20px', backdropFilter: 'blur(16px)', boxShadow: '0 8px 24px rgba(0,0,0,0.3)' }}>
            <div style={{ fontSize: '14px', fontWeight: 700, color: '#f1f5f9', marginBottom: '4px' }}>Processador (CPU)</div>
            <div style={{ fontSize: '13px', color: '#94a3b8' }}>{metrics.cpu?.brand} ({metrics.cpu?.cores} Núcleos)</div>
            <div style={{ fontSize: '32px', fontWeight: 800, color: '#38bdf8', marginTop: '16px', letterSpacing: '-0.5px' }}>
              {metrics.cpu?.loadPercentage >= 0 ? `${metrics.cpu.loadPercentage}% Uso` : 'Ativo'}
            </div>
            <div style={{ width: '100%', height: '6px', background: 'rgba(255,255,255,0.08)', borderRadius: '3px', marginTop: '12px', overflow: 'hidden' }}>
              <div style={{ width: `${Math.min(100, Math.max(5, metrics.cpu?.loadPercentage || 25))}%`, height: '100%', background: 'linear-gradient(90deg, #38bdf8, #818cf8)', borderRadius: '3px', transition: 'width 0.5s ease' }} />
            </div>
          </div>

          {/* Card Memória */}
          <div style={{ background: 'rgba(255, 255, 255, 0.03)', border: '1px solid rgba(168, 85, 247, 0.25)', borderRadius: '16px', padding: '20px', backdropFilter: 'blur(16px)', boxShadow: '0 8px 24px rgba(0,0,0,0.3)' }}>
            <div style={{ fontSize: '14px', fontWeight: 700, color: '#f1f5f9', marginBottom: '4px' }}>Memória RAM</div>
            <div style={{ fontSize: '13px', color: '#94a3b8' }}>
              {(metrics.memory?.used / 1024 / 1024 / 1024).toFixed(1)} GB / {(metrics.memory?.total / 1024 / 1024 / 1024).toFixed(1)} GB
            </div>
            <div style={{ fontSize: '32px', fontWeight: 800, color: '#10b981', marginTop: '16px', letterSpacing: '-0.5px' }}>
              {metrics.memory?.usagePercentage}% Uso
            </div>
            <div style={{ width: '100%', height: '6px', background: 'rgba(255,255,255,0.08)', borderRadius: '3px', marginTop: '12px', overflow: 'hidden' }}>
              <div style={{ width: `${Math.min(100, Math.max(5, metrics.memory?.usagePercentage || 40))}%`, height: '100%', background: 'linear-gradient(90deg, #10b981, #34d399)', borderRadius: '3px', transition: 'width 0.5s ease' }} />
            </div>
          </div>

          {/* Card Sistema Operacional */}
          <div style={{ gridColumn: '1/-1', background: 'rgba(255, 255, 255, 0.03)', border: '1px solid rgba(168, 85, 247, 0.25)', borderRadius: '16px', padding: '20px', backdropFilter: 'blur(16px)', boxShadow: '0 8px 24px rgba(0,0,0,0.3)' }}>
            <div style={{ fontSize: '14px', fontWeight: 700, color: '#f1f5f9', marginBottom: '6px' }}>Sistema Operacional Host</div>
            <div style={{ fontSize: '13px', color: '#cbd5e1', lineHeight: '1.6' }}>
              Plataforma: <b>{metrics.os?.platform}</b> | Arquitetura: <b>x64</b> | Tempo Ativo: <b>{Math.round(metrics.os?.uptimeSeconds / 60)} minutos</b>
            </div>
          </div>
        </div>
      ) : (
        <div style={{ padding: '20px', background: 'rgba(239, 68, 68, 0.12)', border: '1px solid rgba(239, 68, 68, 0.3)', borderRadius: '12px', color: '#fca5a5' }}>
          ⚠️ Métricas não disponíveis no momento. Faça login na LockScreen para autenticar as chamadas da API.
        </div>
      )}
    </div>
  );
}
