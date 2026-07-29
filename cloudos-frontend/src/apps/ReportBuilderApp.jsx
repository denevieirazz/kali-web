import { useState } from 'react';
import { FileText, Plus, Trash2, Download, Eye } from 'lucide-react';
import { useCloudOS } from '../store/CloudOSContext';

export const ReportBuilderApp = () => {
  const { activeProject } = useCloudOS();
  const [projectName, setProjectName] = useState(activeProject?.name || 'Novo Cliente');
  const [execSummary, setExecSummary] = useState('Durante o teste de intrusão, foram identificadas vulnerabilidades críticas que permitem...');
  const [findings, setFindings] = useState([{ title: 'SQL Injection no parâmetro id', severity: 'Crítica', desc: 'A aplicação não sanitiza a entrada de dados...', evidence: 'sqlmap -u http://alvo.com?id=1 --dbs' }]);

  const addFinding = () => setFindings([...findings, { title: '', severity: 'Média', desc: '', evidence: '' }]);
  const updateFinding = (i, field, val) => {
    const newFindings = [...findings];
    newFindings[i][field] = val;
    setFindings(newFindings);
  };
  const removeFinding = (i) => setFindings(findings.filter((_, idx) => idx !== i));

  const generateMarkdown = () => {
    let md = `# Relatório de Teste de Intrusão - ${projectName}\n\n`;
    md += `**Data:** ${new Date().toLocaleDateString('pt-BR')}\n\n`;
    md += `## 1. Resumo Executivo\n${execSummary}\n\n`;
    md += `## 2. Achados de Vulnerabilidades\n`;
    findings.forEach((f, i) => {
      md += `### 2.${i + 1} ${f.title || 'Vulnerabilidade'} (Severidade: ${f.severity})\n`;
      md += `**Descrição:** ${f.desc}\n\n`;
      md += `**Evidência (Comando/Output):**\n\`\`\`bash\n${f.evidence}\n\`\`\`\n\n`;
    });
    md += `## 3. Recomendações\n- Sanitizar todas as entradas de usuário.\n- Atualizar bibliotecas desatualizadas.\n`;
    return md;
  };

  const handleDownload = () => {
    const md = generateMarkdown();
    const blob = new Blob([md], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Relatorio_${projectName.replace(/\s/g, '_')}.md`;
    a.click();
  };

  return (
    <div className="flex h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      {/* Formulário (Esquerda) */}
      <div className="w-1/2 p-6 overflow-y-auto border-r border-gray-800" style={{ width: '50%', padding: '24px', overflowY: 'auto', borderRight: '1px solid #30363d' }}>
        <div className="flex justify-between items-center mb-6" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
            <FileText size={18} /> Report Builder
          </h2>
          <button onClick={handleDownload} className="bg-blue-600 hover:bg-blue-700 px-3 py-1.5 rounded text-xs font-bold flex items-center gap-1 text-white" style={{ background: '#2563eb', color: 'white', padding: '6px 12px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Download size={14} /> Exportar .MD
          </button>
        </div>

        <div className="space-y-4" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div>
            <label className="text-xs text-gray-500 block mb-1" style={{ fontSize: '12px', color: '#8b949e', display: 'block', marginBottom: '4px' }}>Nome do Projeto/Cliente</label>
            <input value={projectName} onChange={(e) => setProjectName(e.target.value)} className="w-full bg-[#161b22] border border-gray-700 rounded px-3 py-2 text-sm outline-none text-white" style={{ width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
          </div>
          <div>
            <label className="text-xs text-gray-500 block mb-1" style={{ fontSize: '12px', color: '#8b949e', display: 'block', marginBottom: '4px' }}>Resumo Executivo</label>
            <textarea value={execSummary} onChange={(e) => setExecSummary(e.target.value)} rows="4" className="w-full bg-[#161b22] border border-gray-700 rounded px-3 py-2 text-sm outline-none text-white" style={{ width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }}></textarea>
          </div>

          <div className="border-t border-gray-800 pt-4" style={{ borderTop: '1px solid #30363d', paddingTop: '16px' }}>
            <h3 className="text-sm font-bold text-white mb-3" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', marginBottom: '12px' }}>Vulnerabilidades Encontradas</h3>
            {findings.map((f, i) => (
              <div key={i} className="bg-[#161b22] p-4 rounded-lg mb-4 border border-gray-800" style={{ background: '#161b22', padding: '16px', borderRadius: '8px', marginBottom: '16px', border: '1px solid #30363d' }}>
                <div className="flex justify-between mb-2" style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', gap: '8px' }}>
                  <input value={f.title} onChange={(e) => updateFinding(i, 'title', e.target.value)} placeholder="Título da Vuln" className="flex-1 bg-transparent border-b border-gray-700 text-sm outline-none text-white" style={{ flex: 1, background: 'transparent', border: 'none', borderBottom: '1px solid #30363d', fontSize: '13px', color: 'white', outline: 'none' }} />
                  <select value={f.severity} onChange={(e) => updateFinding(i, 'severity', e.target.value)} className="bg-gray-800 border border-gray-700 rounded px-2 text-xs outline-none text-white" style={{ background: '#21262d', border: '1px solid #30363d', borderRadius: '4px', padding: '4px 8px', fontSize: '12px', color: 'white', outline: 'none' }}>
                    <option>Crítica</option><option>Alta</option><option>Média</option><option>Baixa</option>
                  </select>
                  <button onClick={() => removeFinding(i)} className="text-red-500 hover:text-red-400" style={{ background: 'transparent', border: 'none', color: '#f87171', cursor: 'pointer' }}><Trash2 size={14} /></button>
                </div>
                <textarea value={f.desc} onChange={(e) => updateFinding(i, 'desc', e.target.value)} placeholder="Descrição técnica..." rows="2" className="w-full bg-black/30 border border-gray-800 rounded px-2 py-1 text-xs mb-2 outline-none text-white" style={{ width: '100%', background: 'rgba(0,0,0,0.3)', border: '1px solid #30363d', borderRadius: '4px', padding: '6px 8px', fontSize: '12px', color: 'white', marginBottom: '8px', outline: 'none' }}></textarea>
                <textarea value={f.evidence} onChange={(e) => updateFinding(i, 'evidence', e.target.value)} placeholder="Evidência (comando/output)" rows="3" className="w-full bg-black/30 border border-gray-800 rounded px-2 py-1 text-xs font-mono text-green-400 outline-none" style={{ width: '100%', background: 'rgba(0,0,0,0.3)', border: '1px solid #30363d', borderRadius: '4px', padding: '6px 8px', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', outline: 'none' }}></textarea>
              </div>
            ))}
            <button onClick={addFinding} className="bg-gray-800 hover:bg-gray-700 px-3 py-2 rounded text-xs flex items-center gap-1 text-white" style={{ background: '#21262d', color: 'white', padding: '6px 12px', borderRadius: '6px', fontSize: '12px', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}><Plus size={14} /> Adicionar Vulnerabilidade</button>
          </div>
        </div>
      </div>

      {/* Preview Markdown (Direita) */}
      <div className="w-1/2 p-6 overflow-y-auto bg-black/30" style={{ width: '50%', padding: '24px', overflowY: 'auto', background: 'rgba(0,0,0,0.3)' }}>
        <h3 className="text-xs text-gray-500 mb-4 flex items-center gap-1" style={{ fontSize: '12px', color: '#8b949e', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '4px' }}><Eye size={12} /> PREVIEW (Markdown Renderizado)</h3>
        <div className="font-mono text-xs text-gray-400 whitespace-pre-wrap" style={{ fontFamily: 'monospace', fontSize: '12px', color: '#c9d1d9', whiteSpace: 'pre-wrap' }}>
          {generateMarkdown()}
        </div>
      </div>
    </div>
  );
};
