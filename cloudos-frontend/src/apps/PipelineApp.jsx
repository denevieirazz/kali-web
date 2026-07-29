import { useState, useRef } from 'react';
import { Play, Loader, Zap } from 'lucide-react';

export const PipelineApp = () => {
  const [domain, setDomain] = useState('example.com');
  const [output, setOutput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const outputRef = useRef(null);

  const handleRun = async () => {
    if (!domain) return;
    const token = localStorage.getItem('cloudos_token');
    setOutput(''); setIsRunning(true);
    try {
      const response = await fetch('http://localhost:8080/api/pipeline/recon', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token ? `Bearer ${token}` : ''
        },
        body: JSON.stringify({ domain })
      });

      if (response.status === 403 || response.status === 401) {
        setOutput("Sessão expirada ou não autorizada. Por favor, faça login novamente.");
        setIsRunning(false);
        return;
      }

      if (!response.ok) {
        const errorText = await response.text();
        setOutput(`Erro (${response.status}): ${errorText}`);
        setIsRunning(false);
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setOutput(prev => prev + decoder.decode(value));
        if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight;
      }
    } catch (e) {
      setOutput("Erro ao conectar com o backend.");
    }
    setIsRunning(false);
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div className="p-4 border-b border-gray-800 bg-[#161b22] flex justify-between items-center" style={{ padding: '16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
            <Zap size={18} className="text-yellow-400" style={{ color: '#facc15' }} /> Pipeline: Recon Automático
          </h2>
          <p className="text-xs text-gray-500" style={{ fontSize: '12px', color: '#8b949e', margin: '4px 0 0 0' }}>Roda Subfinder ➔ Httpx ➔ Nmap em sequência automática.</p>
        </div>
      </div>
      
      <div className="p-4 flex gap-4 border-b border-gray-800" style={{ padding: '16px', display: 'flex', gap: '16px', borderBottom: '1px solid #30363d' }}>
        <input value={domain} onChange={(e) => setDomain(e.target.value)} placeholder="dominio.com" className="flex-1 bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm outline-none text-white" style={{ flex: 1, background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
        <button onClick={handleRun} disabled={isRunning} className="bg-green-600 hover:bg-green-700 px-6 py-2 rounded text-sm font-bold flex items-center gap-1 text-white" style={{ background: '#16a34a', color: 'white', padding: '8px 24px', borderRadius: '6px', fontSize: '13px', fontWeight: 'bold', border: 'none', cursor: isRunning ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}>
          {isRunning ? <Loader size={16} className="animate-spin" /> : <Play size={16} />} Iniciar Automação
        </button>
      </div>

      <div ref={outputRef} className="flex-1 p-4 overflow-y-auto font-mono text-xs text-green-400 whitespace-pre-wrap" style={{ flex: 1, padding: '16px', overflowY: 'auto', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', whiteSpace: 'pre-wrap' }}>
        {output || <span className="text-gray-600" style={{ color: '#6e7681' }}>Digite o domínio e clique em Iniciar. O CloudOS fará o resto.</span>}
      </div>
    </div>
  );
};
