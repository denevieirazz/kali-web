import React, { useState, useEffect, useCallback } from 'react';
import { ShieldAlert, Plus, Trash2, Upload, FileLock2, Hash } from 'lucide-react';

const API_BASE = 'http://localhost:8080/api';

export function FindingsManagerApp({ payload, setPayload, openApp, setBg }) {
  const [findings, setFindings] = useState([]);
  const [selectedFinding, setSelectedFinding] = useState(null);
  const [evidence, setEvidence] = useState([]);
  const [showModal, setShowModal] = useState(false);
  const [newFinding, setNewFinding] = useState({ title: '', severity: 'Média', description: '' });

  const getHeaders = () => {
    const token = localStorage.getItem('cloudos_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };
  };

  const fetchFindings = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/findings`, { headers: getHeaders() });
      const data = await res.json();
      if (data.success) setFindings(data.findings || []);
    } catch (e) {
      console.error("Erro ao buscar findings:", e);
    }
  }, []);

  useEffect(() => { fetchFindings(); }, [fetchFindings]);

  const selectFinding = async (finding) => {
    setSelectedFinding(finding);
    try {
      const res = await fetch(`${API_BASE}/findings/${finding.id}/evidence`, { headers: getHeaders() });
      const data = await res.json();
      if (data.success) setEvidence(data.evidence || []);
    } catch (e) {
      console.error("Erro ao buscar evidências:", e);
    }
  };

  const handleCreateFinding = async () => {
    if (!newFinding.title) return;
    try {
      const res = await fetch(`${API_BASE}/findings`, {
        method: 'POST',
        headers: getHeaders(),
        body: JSON.stringify(newFinding)
      });
      const data = await res.json();
      if (data.success) {
        setShowModal(false);
        setNewFinding({ title: '', severity: 'Média', description: '' });
        fetchFindings();
      }
    } catch (e) {
      console.error("Erro ao criar finding:", e);
    }
  };

  const handleUploadEvidence = async (e) => {
    const file = e.target.files[0];
    if (!file || !selectedFinding) return;

    const reader = new FileReader();
    reader.onload = async (event) => {
      const base64Data = event.target.result;
      try {
        const res = await fetch(`${API_BASE}/findings/${selectedFinding.id}/evidence`, {
          method: 'POST',
          headers: getHeaders(),
          body: JSON.stringify({ filename: file.name, base64Data })
        });
        const data = await res.json();
        if (data.success) {
          selectFinding(selectedFinding);
        }
      } catch (e) {
        console.error("Erro ao enviar evidência:", e);
      }
    };
    reader.readAsDataURL(file);
  };

  const getSeverityColor = (sev) => {
    const map = { 'Crítica': '#f85149', 'Alta': '#ff7b72', 'Média': '#d29922', 'Baixa': '#58a6ff' };
    return map[sev] || '#8b949e';
  };

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9', fontFamily: 'sans-serif' }}>
      
      {/* Coluna Esquerda: Lista de Findings */}
      <div style={{ width: '350px', borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '12px', background: '#161b22', borderBottom: '1px solid #30363d', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ margin: 0, fontSize: '14px' }}>Vulnerabilidades</h3>
          <button onClick={() => setShowModal(true)} style={{ background: '#238636', border: 'none', borderRadius: '6px', padding: '4px 8px', color: 'white', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Plus size={14} /> Nova
          </button>
        </div>
        <div style={{ flex: 1, overflowY: 'auto' }}>
          {(findings || []).map(f => (
            <div key={f.id} onClick={() => selectFinding(f)} style={{
              padding: '12px', borderBottom: '1px solid #21262d', cursor: 'pointer',
              background: selectedFinding?.id === f.id ? '#161b22' : 'transparent'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: getSeverityColor(f.severity), color: '#fff', fontWeight: 'bold' }}>
                  {f.severity}
                </span>
              </div>
              <div style={{ fontSize: '13px', fontWeight: 500 }}>{f.title}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Coluna Direita: Detalhes e Evidências */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        {selectedFinding ? (
          <>
            <div style={{ padding: '16px', background: '#161b22', borderBottom: '1px solid #30363d' }}>
              <h2 style={{ margin: '0 0 8px 0', fontSize: '18px' }}>{selectedFinding.title}</h2>
              <div style={{ fontSize: '13px', color: '#8b949e' }}>{selectedFinding.description}</div>
            </div>
            
            <div style={{ padding: '16px', flex: 1, overflowY: 'auto' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                <h4 style={{ margin: 0, display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <FileLock2 size={16} color="#3fb950" /> Evidências (Cadeia de Custódia)
                </h4>
                <label style={{ background: '#21262d', border: '1px solid #30363d', borderRadius: '6px', padding: '6px 12px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px' }}>
                  <Upload size={12} /> Anexar Prova
                  <input type="file" onChange={handleUploadEvidence} style={{ display: 'none' }} />
                </label>
              </div>

              {(evidence || []).map(ev => (
                <div key={ev.id} style={{
                  background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px',
                  padding: '12px', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '12px'
                }}>
                  <Hash size={20} color="#58a6ff" />
                  <div>
                    <div style={{ fontSize: '13px', fontWeight: 500 }}>{ev.filename}</div>
                    <div style={{ fontSize: '10px', color: '#8b949e', fontFamily: 'monospace' }}>
                      SHA256: {ev.sha256}
                    </div>
                    <div style={{ fontSize: '10px', color: '#3fb950' }}>
                      Coletado em: {new Date(ev.created_at || Date.now()).toLocaleString('pt-BR')}
                    </div>
                  </div>
                </div>
              ))}
              
              {evidence.length === 0 && (
                <div style={{ textAlign: 'center', color: '#484f58', marginTop: '40px', fontSize: '13px' }}>
                  Nenhuma evidência anexada ainda.
                </div>
              )}
            </div>
          </>
        ) : (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#484f58', flexDirection: 'column' }}>
            <ShieldAlert size={48} />
            <span style={{ marginTop: '12px' }}>Selecione ou crie uma vulnerabilidade</span>
          </div>
        )}
      </div>

      {/* Modal de Nova Falha */}
      {showModal && (
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '24px', width: '400px' }}>
            <h3 style={{ marginTop: 0 }}>Registrar Vulnerabilidade</h3>
            <input placeholder="Título" value={newFinding.title} onChange={e => setNewFinding({...newFinding, title: e.target.value})} style={inputStyle} />
            <select value={newFinding.severity} onChange={e => setNewFinding({...newFinding, severity: e.target.value})} style={inputStyle}>
              <option>Crítica</option><option>Alta</option><option>Média</option><option>Baixa</option>
            </select>
            <textarea placeholder="Descrição técnica" value={newFinding.description} onChange={e => setNewFinding({...newFinding, description: e.target.value})} style={{...inputStyle, height: '80px', resize: 'none'}}></textarea>
            <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
              <button onClick={() => setShowModal(false)} style={{ background: '#21262d', border: 'none', padding: '8px 16px', color: '#c9d1d9', borderRadius: '6px', cursor: 'pointer' }}>Cancelar</button>
              <button onClick={handleCreateFinding} style={{ background: '#238636', border: 'none', padding: '8px 16px', color: '#fff', borderRadius: '6px', cursor: 'pointer' }}>Salvar</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const inputStyle = {
  width: '100%', boxSizing: 'border-box', marginBottom: '12px', padding: '8px',
  background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontSize: '13px'
};

export default FindingsManagerApp;
