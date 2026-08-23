// ============================================
// CloudOS Download Manager Modal
// ============================================
import React from 'react';
import { useDownloadManager, type DownloadItem } from '../../stores/downloadManager';
import { openFile } from '../../services/fileLauncher';
import { getFileIconForExtension } from '../../services/mimeRegistry';
import './DownloadManagerModal.css';

export default function DownloadManagerModal() {
  const { isModalOpen, downloads, closeDownloadModal, clearCompleted, removeDownload } = useDownloadManager();

  if (!isModalOpen) return null;

  const handleOpenFile = (item: DownloadItem) => {
    openFile({
      filePath: item.filePath,
      fileName: item.name,
    });
  };

  const handleOpenFolder = (item: DownloadItem) => {
    const dir = item.filePath.split('\\').slice(0, -1).join('\\');
    openFile({
      filePath: dir,
      fileName: 'Downloads',
      targetAppId: 'file-explorer'
    });
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="dlm-overlay" onClick={closeDownloadModal}>
      <div className="dlm-modal" onClick={e => e.stopPropagation()} role="dialog" aria-label="Gerenciador de Downloads">
        <header className="dlm-header">
          <div className="dlm-title-wrap">
            <span className="dlm-header-icon">⬇️</span>
            <div>
              <h3>Gerenciador de Downloads</h3>
              <small>{downloads.length} arquivo{downloads.length === 1 ? '' : 's'} na fila / histórico</small>
            </div>
          </div>
          <div className="dlm-header-actions">
            {downloads.some(d => d.status === 'completed') && (
              <button className="dlm-btn-text" onClick={clearCompleted}>Limpar concluídos</button>
            )}
            <button className="dlm-close-btn" onClick={closeDownloadModal}>✕</button>
          </div>
        </header>

        <main className="dlm-list">
          {downloads.length === 0 ? (
            <div className="dlm-empty">
              <span>📥</span>
              <p>Nenhum download recente.</p>
              <small>Arquivos baixados pelo navegador ou apps aparecerão aqui automaticamente.</small>
            </div>
          ) : (
            downloads.map(item => {
              const icon = getFileIconForExtension(item.name);
              return (
                <div key={item.id} className={`dlm-item ${item.status}`}>
                  <span className="dlm-item-icon">{icon}</span>
                  <div className="dlm-item-details">
                    <div className="dlm-item-name-row">
                      <strong className="dlm-item-name" title={item.filePath}>{item.name}</strong>
                      <span className="dlm-item-size">{formatSize(item.size)}</span>
                    </div>
                    {item.status === 'downloading' && (
                      <div className="dlm-progress-bar">
                        <div className="dlm-progress-fill" style={{ width: `${item.progress}%` }} />
                      </div>
                    )}
                    <div className="dlm-item-sub">
                      <span className={`dlm-badge ${item.status}`}>
                        {item.status === 'completed' ? '✓ Concluído' : item.status === 'downloading' ? `${item.progress}% Baixando...` : 'Falha'}
                      </span>
                      <span className="dlm-item-time">{new Date(item.startedAt).toLocaleTimeString()}</span>
                    </div>
                  </div>
                  <div className="dlm-item-actions">
                    {item.status === 'completed' && (
                      <>
                        <button className="dlm-action-btn primary" onClick={() => handleOpenFile(item)} title="Abrir arquivo">
                          Abrir
                        </button>
                        <button className="dlm-action-btn" onClick={() => handleOpenFolder(item)} title="Abrir na pasta">
                          📁
                        </button>
                      </>
                    )}
                    <button className="dlm-action-btn danger" onClick={() => removeDownload(item.id)} title="Remover da lista">
                      ✕
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </main>
      </div>
    </div>
  );
}
