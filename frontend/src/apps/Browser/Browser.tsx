// ============================================
// CloudOS Browser App — Design Glassmorphism
// ============================================
import { useState, useRef, useEffect } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import './Browser.css';

interface Bookmark {
  title: string;
  url: string;
}

// Lista de origens e padrões conhecidos que funcionam de forma segura em iframe
const KNOWN_EMBEDDABLE_DOMAINS = [
  'wikipedia.org',
  'wikimedia.org',
  'duckduckgo.com',
  'bing.com',
  'archive.org',
  'openstreetmap.org',
];

const DEFAULT_HOME_URL = 'https://www.wikipedia.org';

export default function BrowserApp({ windowId }: { windowId: string }) {
  const [url, setUrl] = useState(DEFAULT_HOME_URL);
  const [inputUrl, setInputUrl] = useState(DEFAULT_HOME_URL);
  const [isLoading, setIsLoading] = useState(false);
  const [isExternalOnly, setIsExternalOnly] = useState(false);
  const [history, setHistory] = useState<string[]>([DEFAULT_HOME_URL]);
  const [historyIndex, setHistoryIndex] = useState(0);
  const [showHistoryModal, setShowHistoryModal] = useState(false);
  const [showBookmarks, setShowBookmarks] = useState(false);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([
    { title: 'DuckDuckGo Search', url: 'https://html.duckduckgo.com/html/' },
    { title: 'Wikipedia', url: 'https://www.wikipedia.org' },
    { title: 'OpenStreetMap', url: 'https://www.openstreetmap.org' },
  ]);

  const iframeRef = useRef<HTMLIFrameElement>(null);
  const timeoutRef = useRef<number | null>(null);
  const updateWindowTitle = useWindowManager((s) => s.updateWindowTitle);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  // Normalização e Validação de URL
  const normalizeUrl = (rawInput: string): { finalUrl: string; forceExternal: boolean } => {
    const clean = rawInput.trim();
    if (!clean) return { finalUrl: DEFAULT_HOME_URL, forceExternal: false };

    let finalUrl = clean;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      if (clean.includes('.') && !clean.includes(' ')) {
        finalUrl = 'https://' + clean;
      } else {
        finalUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(clean)}`;
      }
    }

    // Identificar sites que sabidamente bloqueiam iframe (X-Frame-Options / CSP)
    const lower = finalUrl.toLowerCase();
    const isKnownEmbeddable = KNOWN_EMBEDDABLE_DOMAINS.some((domain) => lower.includes(domain));
    const isLocal = lower.includes('localhost') || lower.includes('127.0.0.1');

    const forceExternal = !isKnownEmbeddable && !isLocal;
    return { finalUrl, forceExternal };
  };

  const navigateTo = (targetInput: string) => {
    const { finalUrl, forceExternal } = normalizeUrl(targetInput);

    setInputUrl(finalUrl);
    setUrl(finalUrl);
    setIsExternalOnly(forceExternal);
    setIsLoading(true);

    if (history[historyIndex] !== finalUrl) {
      const newHistory = [...history.slice(0, historyIndex + 1), finalUrl];
      setHistory(newHistory);
      setHistoryIndex(newHistory.length - 1);
    }

    const domainTitle = finalUrl.replace(/^https?:\/\//, '').split('/')[0];
    updateWindowTitle(windowId, `${domainTitle} - Navegador CloudOS`);

    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = window.setTimeout(() => setIsLoading(false), 800);
  };

  const goBack = () => {
    if (historyIndex > 0) {
      const newIdx = historyIndex - 1;
      setHistoryIndex(newIdx);
      const target = history[newIdx];
      setInputUrl(target);
      setUrl(target);
      const { forceExternal } = normalizeUrl(target);
      setIsExternalOnly(forceExternal);
    }
  };

  const goForward = () => {
    if (historyIndex < history.length - 1) {
      const newIdx = historyIndex + 1;
      setHistoryIndex(newIdx);
      const target = history[newIdx];
      setInputUrl(target);
      setUrl(target);
      const { forceExternal } = normalizeUrl(target);
      setIsExternalOnly(forceExternal);
    }
  };

  const toggleBookmark = () => {
    const exists = bookmarks.some((b) => b.url === url);
    if (exists) {
      setBookmarks(bookmarks.filter((b) => b.url !== url));
    } else {
      const domainTitle = url.replace(/^https?:\/\//, '').split('/')[0];
      setBookmarks([...bookmarks, { title: domainTitle, url }]);
    }
  };

  const openInNativeBrowser = () => {
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="cloudos-browser">
      {/* Navigation Toolbar */}
      <div className="browser-toolbar">
        <button className="browser-btn" onClick={goBack} disabled={historyIndex <= 0} title="Voltar">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M15 18l-6-6 6-6" />
          </svg>
        </button>
        <button
          className="browser-btn"
          onClick={goForward}
          disabled={historyIndex >= history.length - 1}
          title="Avançar"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M9 18l6-6-6-6" />
          </svg>
        </button>
        <button className="browser-btn" onClick={() => navigateTo(url)} title="Atualizar">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <polyline points="23 4 23 10 17 10" />
            <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10" />
          </svg>
        </button>
        <button className="browser-btn" onClick={() => navigateTo(DEFAULT_HOME_URL)} title="Início">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
          </svg>
        </button>

        {/* Address Input */}
        <div className="browser-url-container">
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            className="search-icon"
          >
            <circle cx="11" cy="11" r="7" />
            <path d="M21 21l-4.35-4.35" />
          </svg>
          <input
            type="text"
            className="browser-url-input"
            value={inputUrl}
            onChange={(e) => setInputUrl(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') navigateTo(inputUrl);
            }}
            placeholder="Pesquisar com DuckDuckGo ou digitar URL (ex: wikipedia.org)"
          />
          {isLoading && <div className="browser-spinner" />}
        </div>

        {/* Action Buttons */}
        <button
          className={`browser-btn ${bookmarks.some((b) => b.url === url) ? 'active-bookmark' : ''}`}
          onClick={toggleBookmark}
          title="Favoritos"
        >
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill={bookmarks.some((b) => b.url === url) ? '#f59e0b' : 'none'}
            stroke="currentColor"
            strokeWidth="2"
          >
            <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
          </svg>
        </button>

        <button
          className="browser-btn"
          onClick={() => setShowBookmarks(!showBookmarks)}
          title="Ver Favoritos"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
          </svg>
        </button>

        <button
          className="browser-btn"
          onClick={() => setShowHistoryModal(!showHistoryModal)}
          title="Histórico"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="12" cy="12" r="10" />
            <polyline points="12 6 12 12 16 14" />
          </svg>
        </button>

        <button
          className="browser-btn highlight-external"
          onClick={openInNativeBrowser}
          title="Abrir em nova guia do navegador real"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
            <polyline points="15 3 21 3 21 9" />
            <line x1="10" y1="14" x2="21" y2="3" />
          </svg>
        </button>
      </div>

      {/* Favorites Dropdown Bar */}
      {showBookmarks && (
        <div className="browser-bookmarks-bar">
          <span className="bar-label">Favoritos:</span>
          {bookmarks.map((bm, idx) => (
            <button key={idx} className="bookmark-chip" onClick={() => navigateTo(bm.url)}>
              {bm.title}
            </button>
          ))}
        </div>
      )}

      {/* History Modal Overlay */}
      {showHistoryModal && (
        <div className="browser-history-modal">
          <div className="modal-header">
            <span>📜 Histórico Local</span>
            <button onClick={() => setShowHistoryModal(false)}>✕</button>
          </div>
          <div className="modal-body">
            {history.map((hUrl, i) => (
              <div
                key={i}
                className={`history-item ${i === historyIndex ? 'active' : ''}`}
                onClick={() => {
                  navigateTo(hUrl);
                  setShowHistoryModal(false);
                }}
              >
                <span className="history-num">{i + 1}.</span>
                <span className="history-url">{hUrl}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* View Content Area */}
      <div className="browser-content-area">
        {isExternalOnly ? (
          <div className="external-notice-card">
            <div className="notice-icon">🔒</div>
            <h3 className="notice-title">Este site exige abertura em janela externa</h3>
            <p className="notice-description">
              A política de segurança deste endereço (<code className="url-code">{url}</code>) impede o
              carregamento interno via iframe (proteção contra clickjacking).
            </p>
            <div className="notice-actions">
              <button className="btn-open-external" onClick={openInNativeBrowser}>
                🌐 Abrir site no navegador real
              </button>
              <button className="btn-fallback-home" onClick={() => navigateTo(DEFAULT_HOME_URL)}>
                🏠 Voltar à busca interna
              </button>
            </div>
          </div>
        ) : (
          <iframe
            ref={iframeRef}
            src={url}
            className="browser-iframe"
            sandbox="allow-same-origin allow-scripts allow-popups allow-forms"
            title="CloudOS Internal Browser"
            onLoad={() => setIsLoading(false)}
          />
        )}
      </div>
    </div>
  );
}
