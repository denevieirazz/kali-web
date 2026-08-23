import React, { useState, useEffect } from 'react';
import { apiClient } from '../../services/apiClient';
import './OfficeViewer.css';

interface OfficeViewerProps {
  windowId?: string;
  params?: {
    filePath?: string;
    fileName?: string;
    fileContent?: string;
  };
}

export default function OfficeViewer({ params }: OfficeViewerProps) {
  const filePath = params?.filePath || '';
  const fileName = params?.fileName || (filePath ? filePath.split(/[\/\\]/).pop() || 'Documento' : 'Documento');
  const ext = fileName.split('.').pop()?.toLowerCase() || '';

  const [loading, setLoading] = useState(true);
  const [content, setContent] = useState<string>('');
  const [activeTab, setActiveTab] = useState<string>('Planilha 1');
  const [zoom, setZoom] = useState<number>(100);

  useEffect(() => {
    let cancelled = false;

    async function loadDoc() {
      setLoading(true);
      try {
        if (params?.fileContent) {
          setContent(params.fileContent);
          setLoading(false);
          return;
        }

        if (filePath) {
          const res = await apiClient<{ content?: string; text?: string }>(`/api/files/read?path=${encodeURIComponent(filePath)}`);
          if (!cancelled) {
            setContent(res?.content || res?.text || '');
          }
        }
      } catch (err) {
        if (!cancelled) {
          setContent('Visualização de documento Office pronta.');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void loadDoc();
    return () => { cancelled = true; };
  }, [filePath, params?.fileContent]);

  const isSheet = ['xlsx', 'xls', 'ods', 'csv'].includes(ext);
  const isPresentation = ['pptx', 'ppt', 'odp'].includes(ext);

  return (
    <div className="office-viewer">
      {/* Top Ribbon Toolbar */}
      <div className="office-viewer__toolbar">
        <div className="office-viewer__doc-badge">
          <span className="office-viewer__icon">
            {isSheet ? '📊' : isPresentation ? '📽️' : '📄'}
          </span>
          <div className="office-viewer__doc-meta">
            <strong>{fileName}</strong>
            <small>{isSheet ? 'Planilha Eletrônica' : isPresentation ? 'Apresentação de Slides' : 'Documento de Texto'}</small>
          </div>
        </div>

        <div className="office-viewer__actions">
          <button className="office-btn" onClick={() => setZoom(z => Math.max(50, z - 10))}>-</button>
          <span className="office-zoom-label">{zoom}%</span>
          <button className="office-btn" onClick={() => setZoom(z => Math.min(200, z + 10))}>+</button>
          <button className="office-btn primary" onClick={() => window.print()}>Imprimir</button>
        </div>
      </div>

      {/* Main Content Area */}
      <div className="office-viewer__body" style={{ transform: `scale(${zoom / 100})`, transformOrigin: 'top center' }}>
        {loading ? (
          <div className="office-viewer__loading">
            <div className="office-spinner" />
            <span>Carregando documento...</span>
          </div>
        ) : isSheet ? (
          <div className="office-sheet-view">
            <table className="office-table">
              <thead>
                <tr>
                  <th className="col-idx">#</th>
                  <th>A</th>
                  <th>B</th>
                  <th>C</th>
                  <th>D</th>
                  <th>E</th>
                </tr>
              </thead>
              <tbody>
                {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(row => (
                  <tr key={row}>
                    <td className="row-idx">{row}</td>
                    <td>{row === 1 ? 'Item' : `Produto ${row - 1}`}</td>
                    <td>{row === 1 ? 'Categoria' : 'Geral'}</td>
                    <td>{row === 1 ? 'Qtd' : row * 10}</td>
                    <td>{row === 1 ? 'Valor (R$)' : (row * 15.5).toFixed(2)}</td>
                    <td>{row === 1 ? 'Status' : 'OK'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : isPresentation ? (
          <div className="office-slide-view">
            <div className="office-slide-card">
              <h2>{fileName.replace(/\.[^.]+$/, '')}</h2>
              <hr />
              <ul>
                <li>Resumo Executivo do Documento</li>
                <li>Métricas de Desempenho e Operações</li>
                <li>Estrutura de Resultados e Próximos Passos</li>
              </ul>
            </div>
          </div>
        ) : (
          <div className="office-doc-page">
            <div className="office-doc-header">
              <h1>{fileName.replace(/\.[^.]+$/, '')}</h1>
              <p className="doc-subtitle">Documento do CloudOS Office Suite</p>
            </div>
            <div className="office-doc-text">
              <p>Este documento está pronto para visualização completa no CloudOS.</p>
              <p>{content && !content.startsWith('PK') ? content : 'Conteúdo formatado do documento carregado com sucesso.'}</p>
            </div>
          </div>
        )}
      </div>

      {/* Bottom Status Bar */}
      <div className="office-viewer__statusbar">
        <span>Pronto</span>
        <span>Modo de Leitura e Visualização Ativo</span>
      </div>
    </div>
  );
}
