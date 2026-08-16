import { useEffect, useMemo, useState } from 'react';
import { classifyPreview } from '../../core/filePreviewPolicy.js';
import { formatBytes } from './opfsFileService';
import './CloudOSFilesPreview.css';

const HASH_LIMIT = 25 * 1024 * 1024;

export type FilePreviewEntry = {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  size: number;
  modified: number;
  originalName?: string;
  originalPath?: string[];
  deletedAt?: number;
  source?: 'opfs' | 'windows' | 'wsl';
  mode?: number;
  uid?: number;
  gid?: number;
  symlink?: boolean;
};

async function sha256(file: File) {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

function modeText(mode: number | undefined) {
  if (!Number.isSafeInteger(mode) || mode === undefined || mode < 0) return '';
  return `0${mode.toString(8).padStart(3, '0')}`;
}

function sourceText(source: FilePreviewEntry['source']) {
  if (source === 'wsl') return 'Linux real (WSL)';
  if (source === 'windows') return 'Windows selecionado';
  return 'CloudOS local (OPFS)';
}

export default function FilePreviewPanel({
  entry,
  file,
  loading,
  onClose,
  onEdit,
  onDownload,
}: {
  entry: FilePreviewEntry | null;
  file: File | null;
  loading: boolean;
  onClose: () => void;
  onEdit: () => void;
  onDownload: () => void;
}) {
  const [text, setText] = useState('');
  const [objectUrl, setObjectUrl] = useState('');
  const [hash, setHash] = useState('');
  const [previewError, setPreviewError] = useState('');

  const preview = useMemo(
    () => file ? classifyPreview({ name: entry?.name ?? file.name, type: file.type, size: file.size }) : null,
    [entry?.name, file],
  );

  useEffect(() => {
    let cancelled = false;
    let url = '';
    setText('');
    setObjectUrl('');
    setHash('');
    setPreviewError('');

    if (!file || !preview?.allowed) return;

    if (preview.kind === 'text') {
      void file.text().then(value => {
        if (!cancelled) setText(value);
      }).catch(() => {
        if (!cancelled) setPreviewError('Não foi possível ler o conteúdo como texto.');
      });
    } else {
      url = URL.createObjectURL(file);
      setObjectUrl(url);
    }

    if (file.size <= HASH_LIMIT && crypto.subtle) {
      void sha256(file).then(value => {
        if (!cancelled) setHash(value);
      }).catch(() => undefined);
    }

    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [file, preview?.allowed, preview?.kind]);

  if (!entry) {
    return (
      <aside className="cf-preview cf-preview--empty" aria-label="Preview de arquivo">
        <span>◫</span>
        <strong>Preview</strong>
        <small>Selecione um arquivo para visualizar conteúdo e propriedades.</small>
      </aside>
    );
  }

  const displayName = entry.originalName || entry.name;
  const isSymlink = entry.kind === 'symlink' || entry.symlink === true;

  return (
    <aside className="cf-preview" aria-label={`Preview de ${displayName}`}>
      <header className="cf-preview__header">
        <div>
          <small>{isSymlink ? 'Link simbólico' : entry.kind === 'directory' ? 'Pasta' : 'Arquivo'}</small>
          <strong title={displayName}>{displayName}</strong>
        </div>
        <button type="button" onClick={onClose} aria-label="Fechar preview">×</button>
      </header>

      <div className="cf-preview__surface">
        {loading ? (
          <div className="cf-preview__placeholder"><span className="cf-spinner" />Carregando preview…</div>
        ) : isSymlink ? (
          <div className="cf-preview__placeholder"><span>🔗</span>Link simbólico não é seguido pelo CloudOS Files.</div>
        ) : entry.kind === 'directory' ? (
          <div className="cf-preview__placeholder"><span className="cf-preview__folder">📁</span>Abra a pasta para visualizar seu conteúdo.</div>
        ) : !file ? (
          <div className="cf-preview__placeholder">Não foi possível carregar o arquivo.</div>
        ) : !preview?.allowed ? (
          <div className="cf-preview__placeholder"><span>📦</span>{preview?.reason || 'Preview indisponível.'}</div>
        ) : previewError ? (
          <div className="cf-preview__placeholder">⚠️ {previewError}</div>
        ) : preview.kind === 'text' ? (
          <pre className="cf-preview__text" tabIndex={0}>{text}</pre>
        ) : preview.kind === 'image' && objectUrl ? (
          <img className="cf-preview__image" src={objectUrl} alt={displayName} />
        ) : preview.kind === 'audio' && objectUrl ? (
          <audio className="cf-preview__media" src={objectUrl} controls preload="metadata" />
        ) : preview.kind === 'video' && objectUrl ? (
          <video className="cf-preview__video" src={objectUrl} controls preload="metadata" />
        ) : preview.kind === 'pdf' && objectUrl ? (
          <iframe className="cf-preview__pdf" src={objectUrl} title={`PDF ${displayName}`} sandbox="" />
        ) : (
          <div className="cf-preview__placeholder">Preparando preview…</div>
        )}
      </div>

      <dl className="cf-preview__meta">
        <div><dt>Origem</dt><dd>{sourceText(entry.source)}</dd></div>
        <div><dt>Tamanho</dt><dd>{entry.kind === 'file' ? formatBytes(entry.size) : '—'}</dd></div>
        <div><dt>Modificado</dt><dd>{entry.modified ? new Date(entry.modified).toLocaleString() : '—'}</dd></div>
        {entry.source === 'wsl' && modeText(entry.mode) && <div><dt>Modo POSIX</dt><dd>{modeText(entry.mode)}</dd></div>}
        {entry.source === 'wsl' && Number.isSafeInteger(entry.uid) && <div><dt>UID / GID</dt><dd>{entry.uid} / {entry.gid}</dd></div>}
        {entry.originalPath && <div><dt>Caminho original</dt><dd title={entry.originalPath.join('/')}>{entry.originalPath.join('/') || '/'}</dd></div>}
        {entry.deletedAt && <div><dt>Excluído</dt><dd>{new Date(entry.deletedAt).toLocaleString()}</dd></div>}
        {file?.type && <div><dt>Tipo</dt><dd>{file.type}</dd></div>}
        {hash && <div className="cf-preview__hash"><dt>SHA-256</dt><dd title={hash}>{hash}</dd></div>}
      </dl>

      {entry.kind === 'file' && !isSymlink && (
        <footer className="cf-preview__actions">
          {preview?.kind === 'text' && <button type="button" onClick={onEdit}>Editar texto</button>}
          <button type="button" onClick={onDownload}>Baixar cópia</button>
        </footer>
      )}
    </aside>
  );
}
