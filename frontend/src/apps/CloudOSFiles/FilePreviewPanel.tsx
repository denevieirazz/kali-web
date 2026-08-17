import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { classifyPreview } from '../../core/filePreviewPolicy.js';
import { normalizeViewerZoom, stepViewerZoom } from '../../core/workflowCore.js';
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
  if (source === 'wsl') return 'Linux · Home';
  if (source === 'windows') return 'Windows · pasta autorizada';
  return 'OPFS · CloudOS';
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
  const [zoomMode, setZoomMode] = useState<'fit' | 'manual'>('fit');
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const dragRef = useRef<{ pointerId: number; startX: number; startY: number; originX: number; originY: number } | null>(null);

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
    setZoomMode('fit');
    setZoom(1);
    setPan({ x: 0, y: 0 });
    setDragging(false);
    dragRef.current = null;

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

  const fitImage = useCallback(() => {
    setZoomMode('fit');
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, []);

  const originalImage = useCallback(() => {
    setZoomMode('manual');
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, []);

  const adjustZoom = useCallback((direction: number) => {
    setZoomMode('manual');
    setZoom(current => stepViewerZoom(current, direction));
  }, []);

  const onImageKeyDown = useCallback((event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === '+' || event.key === '=') { event.preventDefault(); adjustZoom(1); }
    else if (event.key === '-') { event.preventDefault(); adjustZoom(-1); }
    else if (event.key === '0') { event.preventDefault(); fitImage(); }
  }, [adjustZoom, fitImage]);

  const onPointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (zoomMode !== 'manual') return;
    dragRef.current = { pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, originX: pan.x, originY: pan.y };
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(true);
  }, [pan.x, pan.y, zoomMode]);

  const onPointerMove = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    setPan({ x: drag.originX + event.clientX - drag.startX, y: drag.originY + event.clientY - drag.startY });
  }, []);

  const endPointer = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (dragRef.current?.pointerId === event.pointerId) dragRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    setDragging(false);
  }, []);

  if (!entry) {
    return (
      <aside className="cf-preview cf-preview--empty" aria-label="Viewer de arquivo">
        <span>◫</span>
        <strong>Viewer</strong>
        <small>Selecione um arquivo para visualizar conteúdo e propriedades.</small>
      </aside>
    );
  }

  const displayName = entry.originalName || entry.name;
  const isSymlink = entry.kind === 'symlink' || entry.symlink === true;

  return (
    <aside className="cf-preview" aria-label={`Viewer de ${displayName}`}>
      <header className="cf-preview__header">
        <div>
          <small>{isSymlink ? 'Link simbólico' : entry.kind === 'directory' ? 'Pasta' : 'Arquivo'}</small>
          <strong title={displayName}>{displayName}</strong>
        </div>
        <button type="button" onClick={onClose} aria-label="Fechar viewer">×</button>
      </header>

      <div className="cf-preview__surface">
        {loading ? (
          <div className="cf-preview__placeholder"><span className="cf-spinner" />Carregando viewer…</div>
        ) : isSymlink ? (
          <div className="cf-preview__placeholder"><span>🔗</span>Link simbólico não é seguido nem aberto pelo CloudOS Files.</div>
        ) : entry.kind === 'directory' ? (
          <div className="cf-preview__placeholder"><span className="cf-preview__folder">📁</span>Abra a pasta para visualizar seu conteúdo.</div>
        ) : !file ? (
          <div className="cf-preview__placeholder"><span>ℹ️</span>Informações do arquivo. Abertura automática não é permitida para este tipo.</div>
        ) : !preview?.allowed ? (
          <div className="cf-preview__placeholder"><span>📦</span>{preview?.reason || 'Viewer indisponível.'}</div>
        ) : previewError ? (
          <div className="cf-preview__placeholder">⚠️ {previewError}</div>
        ) : preview.kind === 'text' ? (
          <pre className="cf-preview__text" tabIndex={0}>{text}</pre>
        ) : preview.kind === 'image' && objectUrl ? (
          <div className="cf-image-viewer">
            <div className="cf-image-viewer__toolbar" aria-label="Controles de imagem"><button type="button" onClick={() => adjustZoom(-1)} aria-label="Diminuir zoom">−</button><span>{zoomMode === 'fit' ? 'Fit' : `${Math.round(normalizeViewerZoom(zoom) * 100)}%`}</span><button type="button" onClick={() => adjustZoom(1)} aria-label="Aumentar zoom">＋</button><button type="button" onClick={fitImage}>Fit</button><button type="button" onClick={originalImage}>1:1</button></div>
            <div className={`cf-image-viewer__stage ${dragging ? 'is-dragging' : ''}`} tabIndex={0} onKeyDown={onImageKeyDown} onWheel={event => { event.preventDefault(); adjustZoom(event.deltaY > 0 ? -1 : 1); }} onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={endPointer} onPointerCancel={endPointer}>
              <img className={`cf-preview__image ${zoomMode === 'fit' ? 'is-fit' : 'is-manual'}`} src={objectUrl} alt={displayName} draggable={false} style={zoomMode === 'manual' ? { transform: `translate(${pan.x}px, ${pan.y}px) scale(${normalizeViewerZoom(zoom)})` } : undefined} />
            </div>
            <small className="cf-image-viewer__hint">Wheel ou +/−: zoom · arraste: pan · 0: Fit</small>
          </div>
        ) : preview.kind === 'audio' && objectUrl ? (
          <audio className="cf-preview__media" src={objectUrl} controls preload="metadata" />
        ) : preview.kind === 'video' && objectUrl ? (
          <video className="cf-preview__video" src={objectUrl} controls preload="metadata" />
        ) : preview.kind === 'pdf' && objectUrl ? (
          <iframe className="cf-preview__pdf" src={objectUrl} title={`PDF ${displayName}`} sandbox="" />
        ) : (
          <div className="cf-preview__placeholder">Preparando viewer…</div>
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
