import React, { useState, useCallback } from 'react';
import { API_BASE } from '../config';

export function MsfvenomApp() {
  const [payload, setPayload] = useState('windows/meterpreter/reverse_tcp');
  const [lhost, setLhost] = useState('192.168.0.100');
  const [lport, setLport] = useState('4444');
  const [format, setFormat] = useState('exe');
  
  const [generating, setGenerating] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);

  const getToken = () => localStorage.getItem('cloudos_token');

  const handleGenerate = useCallback(async () => {
    setGenerating(true);
    setError(null);
    setResult(null);

    try {
      const res = await fetch(`${API_BASE}/api/msfvenom/generate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ payload, lhost, lport, format })
      });
      
      const data = await res.json();
      if (data.success) {
        setResult(data);
      } else {
        setError(data.error || 'Erro desconhecido');
      }
    } catch (err) {
      setError('Falha de comunicação com o backend');
    } finally {
      setGenerating(false);
    }
  }, [payload, lhost, lport, format]);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h2 style={styles.title}>🧪 Payload Generator</h2>
        <p style={styles.subtitle}>Crie payloads do Metasploit (msfvenom) sem usar o terminal</p>
      </div>

      <div style={styles.panel}>
        <div style={styles.formGroup}>
          <label style={styles.label}>Payload (Arquitetura e Tipo)</label>
          <select style={styles.select} value={payload} onChange={(e) => setPayload(e.target.value)} disabled={generating}>
            <option value="windows/meterpreter/reverse_tcp">Windows Meterpreter (TCP)</option>
            <option value="windows/meterpreter/reverse_https">Windows Meterpreter (HTTPS)</option>
            <option value="windows/x64/meterpreter/reverse_tcp">Windows x64 Meterpreter (TCP)</option>
            <option value="linux/x86/meterpreter/reverse_tcp">Linux x86 Meterpreter (TCP)</option>
            <option value="php/meterpreter/reverse_tcp">PHP Meterpreter (TCP)</option>
            <option value="python/meterpreter/reverse_tcp">Python Meterpreter (TCP)</option>
            <option value="java/jsp_shell_reverse_tcp">Java JSP Reverse Shell</option>
          </select>
        </div>

        <div style={styles.row}>
          <div style={styles.formGroup}>
            <label style={styles.label}>LHOST (Seu IP de Escuta)</label>
            <input style={styles.input} value={lhost} onChange={(e) => setLhost(e.target.value)} disabled={generating} placeholder="Ex: 192.168.1.10" />
          </div>
          <div style={styles.formGroup}>
            <label style={styles.label}>LPORT (Porta de Escuta)</label>
            <input style={styles.input} value={lport} onChange={(e) => setLport(e.target.value)} disabled={generating} placeholder="Ex: 4444" />
          </div>
        </div>

        <div style={styles.formGroup}>
          <label style={styles.label}>Formato do Arquivo</label>
          <div style={styles.btnGroup}>
            {['exe', 'raw', 'py', 'ps1', 'jar', 'war', 'php'].map(f => (
              <button 
                key={f} 
                style={format === f ? styles.formatBtnActive : styles.formatBtn}
                onClick={() => setFormat(f)}
                disabled={generating}
              >
                .{f}
              </button>
            ))}
          </div>
        </div>

        <button 
          style={{ ...styles.btnGenerate, ...(generating ? styles.btnDisabled : {}) }}
          onClick={handleGenerate}
          disabled={generating}
        >
          {generating ? '⏳ Gerando Binário no Kali...' : '💥 Gerar Payload'}
        </button>
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {generating && (
        <div style={styles.loadingBox}>
          <div style={styles.spinner} />
          <div style={styles.loadingText}>O msfvenom está empacotando o exploit. Isso pode levar alguns segundos.</div>
        </div>
      )}

      {!generating && result && (
        <div style={styles.resultCard}>
          <div style={{ fontSize: '32px', marginBottom: '8px' }}>✅</div>
          <div style={{ fontSize: '18px', fontWeight: 'bold', color: '#3fb950', marginBottom: '16px' }}>
            Payload Gerado com Sucesso!
          </div>
          <a 
            href={`${API_BASE}${result.downloadUrl}`} 
            download 
            style={styles.btnDownload}
          >
            ⬇ Baixar Arquivo Gerado
          </a>
        </div>
      )}
    </div>
  );
}

const styles = {
  container: { padding: '20px', height: '100%', overflowY: 'auto', background: '#0d1117', fontFamily: 'sans-serif' },
  header: { marginBottom: '20px', borderBottom: '1px solid #30363d', paddingBottom: '16px' },
  title: { color: '#58a6ff', fontSize: '20px', margin: '0 0 4px 0' },
  subtitle: { color: '#8b949e', fontSize: '12px', margin: 0 },
  panel: { background: '#161b22', padding: '20px', borderRadius: '8px', border: '1px solid #30363d', marginBottom: '20px' },
  formGroup: { marginBottom: '16px', flex: 1 },
  row: { display: 'flex', gap: '16px' },
  label: { display: 'block', color: '#8b949e', fontSize: '12px', marginBottom: '6px', fontWeight: 'bold' },
  select: { width: '100%', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box' },
  input: { width: '100%', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box' },
  btnGroup: { display: 'flex', gap: '8px', flexWrap: 'wrap' },
  formatBtn: { padding: '8px 16px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#8b949e', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px' },
  formatBtnActive: { padding: '8px 16px', background: 'rgba(88, 166, 255, 0.2)', border: '1px solid #58a6ff', borderRadius: '6px', color: '#58a6ff', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px', fontWeight: 'bold' },
  btnGenerate: { width: '100%', padding: '12px', background: '#238636', color: '#fff', border: '1px solid #2ea043', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', gap: '12px' },
  spinner: { width: '32px', height: '32px', border: '3px solid #30363d', borderTopColor: '#58a6ff', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#58a6ff', fontSize: '14px' },
  resultCard: { background: '#161b22', border: '1px solid #3fb950', borderRadius: '8px', padding: '24px', textAlign: 'center' },
  btnDownload: { display: 'inline-block', marginTop: '8px', padding: '12px 24px', background: '#238636', color: '#fff', border: '1px solid #2ea043', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px', textDecoration: 'none' }
};

export default MsfvenomApp;
