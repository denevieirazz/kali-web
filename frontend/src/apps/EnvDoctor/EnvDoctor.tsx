import { useState, useEffect } from 'react';
import { apiClient } from '../../services/apiClient';

export default function EnvDoctor({ windowId }: { windowId?: string }) {
  const [checks, setChecks] = useState<Array<{ name: string; status: 'ok' | 'fail' | 'checking'; detail: string }>>([
    { name: 'OPFS (Origin Private File System)', status: 'checking', detail: 'Verificando navigator.storage' },
    { name: 'Backend API Health (/api/health)', status: 'checking', detail: 'Testando conexão HTTP com backend' },
    { name: 'Runtime Config (/api/runtime)', status: 'checking', detail: 'Lendo portas dinâmicas' },
    { name: 'WebSocket Support', status: 'checking', detail: 'Validando construtor WebSocket' }
  ]);

  useEffect(() => {
    async function runDiagnostics() {
      // 1. OPFS
      let opfsOk = false;
      try {
        if ('storage' in navigator && 'getDirectory' in navigator.storage) {
          await navigator.storage.getDirectory();
          opfsOk = true;
        }
      } catch (e) {}

      // 2. Health
      let healthOk = false;
      try {
        await apiClient('/api/health', { skipAuth: true });
        healthOk = true;
      } catch (e) {}

      // 3. Runtime
      let runtimeOk = false;
      try {
        await apiClient('/api/runtime', { skipAuth: true });
        runtimeOk = true;
      } catch (e) {}

      // 4. WebSocket
      const wsOk = typeof window !== 'undefined' && 'WebSocket' in window;

      setChecks([
        { name: 'OPFS (Origin Private File System)', status: opfsOk ? 'ok' : 'fail', detail: opfsOk ? 'Disponível e ativo no navegador' : 'Indisponível neste contexto' },
        { name: 'Backend API Health (/api/health)', status: healthOk ? 'ok' : 'fail', detail: healthOk ? 'Respondendo HTTP 200 OK' : 'Falha na conexão HTTP' },
        { name: 'Runtime Config (/api/runtime)', status: runtimeOk ? 'ok' : 'fail', detail: runtimeOk ? 'Porta dinâmica configurada' : 'Sem resposta do backend' },
        { name: 'WebSocket Support', status: wsOk ? 'ok' : 'fail', detail: wsOk ? 'Suportado pelo navegador' : 'Indisponível' }
      ]);
    }

    runDiagnostics();
  }, []);

  return (
    <div style={{ height: '100%', width: '100%', display: 'flex', flexDirection: 'column', background: '#0a0a0f', color: '#ede9fe', padding: '20px', boxSizing: 'border-box' }}>
      <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: '#10b981' }}>🩺 Environment Doctor — Diagnóstico do Sistema</h3>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {checks.map(c => (
          <div key={c.name} style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: '10px', padding: '14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontWeight: 600, fontSize: '14px' }}>{c.name}</div>
              <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>{c.detail}</div>
            </div>
            <div style={{ fontSize: '18px' }}>
              {c.status === 'ok' ? '✅' : c.status === 'fail' ? '❌' : '⏳'}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
