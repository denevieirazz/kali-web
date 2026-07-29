import { useState } from 'react';
import { Send, ArrowRightLeft } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const RepeaterApp = () => {
  const [tab, setTab] = useState('repeater');
  const [rawReq, setRawReq] = useState('GET / HTTP/1.1\nHost: localhost:8090\n\n');
  const [response, setResponse] = useState('');
  const [loading, setLoading] = useState(false);

  // Decoder vars
  const [inputText, setInputText] = useState('');
  const [outputText, setOutputText] = useState('');

  const handleSend = async () => {
    setLoading(true);
    try {
      const res = await fetch(`${API_BASE}/api/repeater/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
        body: JSON.stringify({ rawRequest: rawReq })
      });
      const data = await res.json();
      setResponse(data.response || data.error);
    } catch (e) { setResponse("Erro de conexão."); }
    setLoading(false);
  };

  const handleDecode = (action) => {
    try {
      if (action === 'b64_enc') setOutputText(btoa(inputText));
      if (action === 'b64_dec') setOutputText(atob(inputText));
      if (action === 'url_enc') setOutputText(encodeURIComponent(inputText));
      if (action === 'url_dec') setOutputText(decodeURIComponent(inputText));
    } catch (e) { setOutputText("Erro ao decodificar."); }
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div className="flex border-b border-gray-800 bg-[#161b22]" style={{ display: 'flex', borderBottom: '1px solid #30363d', background: '#161b22' }}>
        <button onClick={() => setTab('repeater')} className={`px-4 py-2 text-sm font-medium ${tab === 'repeater' ? 'text-blue-400 border-b-2 border-blue-500' : 'text-gray-500'}`} style={{ padding: '8px 16px', fontSize: '14px', border: 'none', background: 'transparent', cursor: 'pointer', color: tab === 'repeater' ? '#60a5fa' : '#8b949e', borderBottom: tab === 'repeater' ? '2px solid #3b82f6' : 'none' }}>HTTP Repeater</button>
        <button onClick={() => setTab('decoder')} className={`px-4 py-2 text-sm font-medium ${tab === 'decoder' ? 'text-blue-400 border-b-2 border-blue-500' : 'text-gray-500'}`} style={{ padding: '8px 16px', fontSize: '14px', border: 'none', background: 'transparent', cursor: 'pointer', color: tab === 'decoder' ? '#60a5fa' : '#8b949e', borderBottom: tab === 'decoder' ? '2px solid #3b82f6' : 'none' }}>CyberChef (Decoder)</button>
      </div>

      {tab === 'repeater' && (
        <div className="flex-1 flex flex-col p-4 gap-4" style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '16px', gap: '16px' }}>
          <div className="flex justify-between items-center" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h2 className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: 0 }}>Raw Request</h2>
            <button onClick={handleSend} disabled={loading} className="bg-blue-600 hover:bg-blue-700 px-4 py-1.5 rounded text-xs font-bold flex items-center gap-1 text-white" style={{ background: '#2563eb', color: 'white', padding: '6px 16px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: loading ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <Send size={12} /> {loading ? 'Enviando...' : 'Enviar'}
            </button>
          </div>
          <textarea value={rawReq} onChange={(e) => setRawReq(e.target.value)} className="flex-1 bg-black/50 border border-gray-800 rounded p-2 font-mono text-xs text-green-400 outline-none resize-none" style={{ flex: 1, background: 'rgba(0,0,0,0.5)', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', outline: 'none', resize: 'none' }} />
          
          <h2 className="text-sm font-bold text-white mt-2" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: '8px 0 0 0' }}>Response</h2>
          <textarea value={response} readOnly className="flex-1 bg-black/50 border border-gray-800 rounded p-2 font-mono text-xs text-gray-400 outline-none resize-none" style={{ flex: 1, background: 'rgba(0,0,0,0.5)', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: '#8b949e', outline: 'none', resize: 'none' }} />
        </div>
      )}

      {tab === 'decoder' && (
        <div className="flex-1 flex flex-col p-4 gap-4" style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '16px', gap: '16px' }}>
          <div className="flex gap-2 flex-wrap" style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            <button onClick={() => handleDecode('b64_enc')} className="bg-gray-800 hover:bg-gray-700 px-3 py-1 rounded text-xs text-white" style={{ background: '#30363d', color: 'white', padding: '6px 12px', borderRadius: '4px', fontSize: '12px', border: 'none', cursor: 'pointer' }}>Base64 Encode</button>
            <button onClick={() => handleDecode('b64_dec')} className="bg-gray-800 hover:bg-gray-700 px-3 py-1 rounded text-xs text-white" style={{ background: '#30363d', color: 'white', padding: '6px 12px', borderRadius: '4px', fontSize: '12px', border: 'none', cursor: 'pointer' }}>Base64 Decode</button>
            <button onClick={() => handleDecode('url_enc')} className="bg-gray-800 hover:bg-gray-700 px-3 py-1 rounded text-xs text-white" style={{ background: '#30363d', color: 'white', padding: '6px 12px', borderRadius: '4px', fontSize: '12px', border: 'none', cursor: 'pointer' }}>URL Encode</button>
            <button onClick={() => handleDecode('url_dec')} className="bg-gray-800 hover:bg-gray-700 px-3 py-1 rounded text-xs text-white" style={{ background: '#30363d', color: 'white', padding: '6px 12px', borderRadius: '4px', fontSize: '12px', border: 'none', cursor: 'pointer' }}>URL Decode</button>
          </div>
          <textarea value={inputText} onChange={(e) => setInputText(e.target.value)} placeholder="Cole o texto aqui..." className="flex-1 bg-black/50 border border-gray-800 rounded p-2 font-mono text-xs text-green-400 outline-none resize-none" style={{ flex: 1, background: 'rgba(0,0,0,0.5)', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', outline: 'none', resize: 'none' }} />
          <div className="flex justify-center" style={{ display: 'flex', justifyContent: 'center' }}><ArrowRightLeft size={16} className="text-gray-600" style={{ color: '#484f58' }} /></div>
          <textarea value={outputText} readOnly className="flex-1 bg-black/50 border border-gray-800 rounded p-2 font-mono text-xs text-blue-400 outline-none resize-none" style={{ flex: 1, background: 'rgba(0,0,0,0.5)', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: '#60a5fa', outline: 'none', resize: 'none' }} />
        </div>
      )}
    </div>
  );
};
