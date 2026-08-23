// ============================================
// Open With Modal — CloudOS File Associations UI
// ============================================
import React, { useState, useEffect } from 'react';
import { create } from 'zustand';
import { type AppAssociation, getFileExtension, setUserDefaultApp } from '../../services/mimeRegistry';
import './OpenWithModal.css';

interface OpenWithModalState {
  isOpen: boolean;
  fileName: string;
  filePath: string;
  fileContent?: string;
  compatibleApps: AppAssociation[];
  onSelectApp: ((appId: string) => void) | null;
}

export const useOpenWithModal = create<OpenWithModalState>(() => ({
  isOpen: false,
  fileName: '',
  filePath: '',
  fileContent: undefined,
  compatibleApps: [],
  onSelectApp: null,
}));

export function openOpenWithModal(options: {
  fileName: string;
  filePath: string;
  fileContent?: string;
  compatibleApps: AppAssociation[];
  onSelectApp: (appId: string) => void;
}) {
  useOpenWithModal.setState({
    isOpen: true,
    fileName: options.fileName,
    filePath: options.filePath,
    fileContent: options.fileContent,
    compatibleApps: options.compatibleApps,
    onSelectApp: options.onSelectApp,
  });
}

export default function OpenWithModal() {
  const { isOpen, fileName, compatibleApps, onSelectApp } = useOpenWithModal();
  const [selectedAppId, setSelectedAppId] = useState<string>('');
  const [alwaysUse, setAlwaysUse] = useState<boolean>(false);

  useEffect(() => {
    if (compatibleApps.length > 0) {
      setSelectedAppId(compatibleApps[0].id);
    }
  }, [compatibleApps]);

  if (!isOpen) return null;

  const ext = getFileExtension(fileName);

  const handleClose = () => {
    useOpenWithModal.setState({ isOpen: false, onSelectApp: null });
  };

  const handleConfirm = () => {
    if (!selectedAppId) return;
    if (alwaysUse && ext) {
      setUserDefaultApp(ext, selectedAppId);
    }
    const callback = onSelectApp;
    handleClose();
    if (callback) callback(selectedAppId);
  };

  return (
    <div className="openwith-overlay" onClick={handleClose}>
      <div className="openwith-modal" onClick={e => e.stopPropagation()} role="dialog" aria-label="Abrir com">
        <div className="openwith-header">
          <div className="openwith-title-wrap">
            <h3>Abrir este arquivo</h3>
            <p className="openwith-filename">“{fileName}”</p>
          </div>
          <button className="openwith-close-btn" onClick={handleClose}>✕</button>
        </div>

        <div className="openwith-section-title">
          Como deseja abrir este arquivo?
        </div>

        <div className="openwith-app-list">
          {compatibleApps.map((app) => {
            const isSelected = selectedAppId === app.id;
            const isIconUrl = typeof app.icon === 'string' && (app.icon.startsWith('/') || app.icon.startsWith('http'));
            return (
              <div
                key={app.id}
                className={`openwith-app-item ${isSelected ? 'selected' : ''}`}
                onClick={() => setSelectedAppId(app.id)}
                onDoubleClick={handleConfirm}
              >
                <span className="openwith-app-icon">
                  {isIconUrl ? (
                    <img src={app.icon} alt="" style={{ width: '28px', height: '28px', objectFit: 'contain' }} />
                  ) : (
                    app.icon || '📦'
                  )}
                </span>
                <div className="openwith-app-info">
                  <strong>{app.name}</strong>
                  <small>{app.description || (app.isLinux ? 'Aplicativo Linux contido' : 'Aplicativo integrado do CloudOS')}</small>
                </div>
                {isSelected && <span className="openwith-check">✓</span>}
              </div>
            );
          })}
        </div>

        {ext && (
          <label className="openwith-always-label">
            <input
              type="checkbox"
              checked={alwaysUse}
              onChange={e => setAlwaysUse(e.target.checked)}
            />
            <span>Sempre usar este aplicativo para abrir arquivos <strong>.{ext}</strong></span>
          </label>
        )}

        <div className="openwith-actions">
          <button className="openwith-btn secondary" onClick={handleClose}>Cancelar</button>
          <button className="openwith-btn primary" onClick={handleConfirm} disabled={!selectedAppId}>
            Abrir
          </button>
        </div>
      </div>
    </div>
  );
}
