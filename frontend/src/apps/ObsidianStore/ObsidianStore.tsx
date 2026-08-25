import { useState, useEffect, useMemo, useCallback } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { apiClient } from '../../services/apiClient';
import { FiSearch, FiCheck, FiStar, FiDownload, FiTrash2, FiPlay, FiRefreshCw, FiAlertCircle } from 'react-icons/fi';
import './ObsidianStore.css';

export interface LinuxPackage {
  id: string;
  name: string;
  packageName: string;
  command: string;
  category: string;
  description: string;
  icon: string;
  isPopular: boolean;
  desktopId: string;
  installed: boolean;
}

const CATEGORIES = [
  { id: 'all', label: 'Todos os Apps' },
  { id: 'popular', label: '★ Destaques' },
  { id: 'installed', label: '✓ Instalados' },
  { id: 'favorites', label: '♥ Favoritos' },
  { id: 'internet', label: 'Internet' },
  { id: 'development', label: 'Desenvolvimento' },
  { id: 'graphics', label: 'Gráficos' },
  { id: 'multimedia', label: 'Multimídia' },
  { id: 'office', label: 'Escritório' },
  { id: 'utilities', label: 'Utilitários' },
  { id: 'security', label: 'Segurança' },
];

// Package installation includes repository refresh + download + dpkg/rpm work.
// Keep this above the backend package-manager ceiling so the browser never aborts first.
const PACKAGE_INSTALL_TIMEOUT_MS = 180_000;

export default function ObsidianStore() {
  const [packages, setPackages] = useState<LinuxPackage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [query, setQuery] = useState('');
  const [installingId, setInstallingId] = useState<string | null>(null);
  const [uninstallingId, setUninstallingId] = useState<string | null>(null);
  const [actionLog, setActionLog] = useState<{ id: string; name: string; status: string; log?: string } | null>(null);

  const [favorites, setFavorites] = useState<Set<string>>(() => {
    try {
      const stored = localStorage.getItem('cloudos.store.favorites');
      return stored ? new Set(JSON.parse(stored)) : new Set(['firefox', 'code']);
    } catch {
      return new Set(['firefox', 'code']);
    }
  });

  const openWindow = useWindowManager((s) => s.openWindow);
  const createProcess = useProcessManager((s) => s.createProcess);

  const fetchPackages = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await apiClient<{ packages: LinuxPackage[]; operational: boolean; error?: string }>(
        '/api/linux-runtime/packages',
        { timeoutMs: 30000 }
      );
      if (res?.packages) {
        setPackages(res.packages);
      }
    } catch (err: any) {
      setError(err?.message || 'Erro ao carregar catálogo de aplicativos Linux.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPackages();
  }, [fetchPackages]);

  const toggleFavorite = (id: string) => {
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      try {
        localStorage.setItem('cloudos.store.favorites', JSON.stringify([...next]));
      } catch {}
      return next;
    });
  };

  const handleInstall = async (pkg: LinuxPackage) => {
    const startedAt = Date.now();
    setInstallingId(pkg.id);
    setActionLog({ id: pkg.id, name: pkg.name, status: 'Instalando via repositórios oficiais...' });
    try {
      const res = await apiClient<{ success: boolean; log: string }>(`/api/linux-runtime/packages/${pkg.id}/install`, {
        method: 'POST',
        body: JSON.stringify({}),
        timeoutMs: PACKAGE_INSTALL_TIMEOUT_MS,
      });
      const elapsedSeconds = ((Date.now() - startedAt) / 1000).toFixed(1);
      setActionLog({ id: pkg.id, name: pkg.name, status: `Instalação concluída com sucesso em ${elapsedSeconds}s!`, log: res?.log });
      await fetchPackages();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent('cloudos:apps-changed'));
      }
    } catch (err: any) {
      const msg = err?.message || 'Falha ao instalar pacote.';
      setActionLog({ id: pkg.id, name: pkg.name, status: `Erro na instalação: ${msg}` });
    } finally {
      setInstallingId(null);
    }
  };

  const handleUninstall = async (pkg: LinuxPackage) => {
    if (!confirm(`Tem certeza que deseja remover ${pkg.name}?`)) return;
    setUninstallingId(pkg.id);
    setActionLog({ id: pkg.id, name: pkg.name, status: 'Removendo pacote...' });
    try {
      const res = await apiClient<{ success: boolean; log: string }>(`/api/linux-runtime/packages/${pkg.id}/uninstall`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      setActionLog({ id: pkg.id, name: pkg.name, status: 'Aplicativo removido.', log: res?.log });
      await fetchPackages();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent('cloudos:apps-changed'));
      }
    } catch (err: any) {
      const msg = err?.message || 'Falha ao remover pacote.';
      setActionLog({ id: pkg.id, name: pkg.name, status: `Erro ao remover: ${msg}` });
    } finally {
      setUninstallingId(null);
    }
  };

  const handleLaunch = (pkg: LinuxPackage) => {
    const pid = createProcess('linux-app-runner', pkg.name, pkg.icon);
    openWindow({
      title: pkg.name,
      icon: pkg.icon,
      appId: 'linux-app-runner',
      width: 1020,
      height: 680,
      minWidth: 480,
      minHeight: 320,
      isResizable: true,
      processId: pid,
      params: { appId: pkg.id, app: pkg.id, title: pkg.name, icon: pkg.icon },
    });
  };

  const filteredPackages = useMemo(() => {
    return packages.filter((pkg) => {
      // Category filter
      if (selectedCategory === 'popular' && !pkg.isPopular) return false;
      if (selectedCategory === 'installed' && !pkg.installed) return false;
      if (selectedCategory === 'favorites' && !favorites.has(pkg.id)) return false;
      if (!['all', 'popular', 'installed', 'favorites'].includes(selectedCategory) && pkg.category !== selectedCategory) {
        return false;
      }
      // Query filter
      if (query.trim()) {
        const q = query.trim().toLowerCase();
        const matchesName = pkg.name.toLowerCase().includes(q);
        const matchesPkg = pkg.packageName.toLowerCase().includes(q);
        const matchesDesc = pkg.description.toLowerCase().includes(q);
        if (!matchesName && !matchesPkg && !matchesDesc) return false;
      }
      return true;
    });
  }, [packages, selectedCategory, favorites, query]);

  return (
    <div className="obsidian-store">
      <div className="store-header">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <div>
            <div className="store-title">Linux App Center</div>
            <div style={{ color: '#94a3b8', fontSize: '14px' }}>
              Instale, gerencie e execute aplicativos gráficos nativos Linux no CloudOS.
            </div>
          </div>
          <button
            onClick={fetchPackages}
            disabled={loading}
            style={{
              background: 'rgba(255,255,255,0.08)',
              border: '1px solid rgba(255,255,255,0.15)',
              color: '#fff',
              padding: '8px 14px',
              borderRadius: '8px',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              fontSize: '13px'
            }}
          >
            <FiRefreshCw className={loading ? 'spin' : ''} /> Atualizar Catálogo
          </button>
        </div>

        <div className="store-search-container">
          <FiSearch className="store-search-icon" />
          <input
            type="text"
            className="store-search-input"
            placeholder="Pesquisar aplicativos (ex: Firefox, VS Code, GIMP, VLC)..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
      </div>

      <div className="store-categories">
        {CATEGORIES.map((cat) => (
          <button
            key={cat.id}
            className={`category-pill ${selectedCategory === cat.id ? 'active' : ''}`}
            onClick={() => setSelectedCategory(cat.id)}
          >
            {cat.label}
          </button>
        ))}
      </div>

      {actionLog && (
        <div style={{ margin: '0 32px 16px 32px', padding: '12px 16px', background: 'rgba(99, 102, 241, 0.15)', border: '1px solid rgba(99, 102, 241, 0.3)', borderRadius: '8px', fontSize: '13px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span><strong>{actionLog.name}:</strong> {actionLog.status}</span>
            <button onClick={() => setActionLog(null)} style={{ background: 'transparent', border: 'none', color: '#94a3b8', cursor: 'pointer' }}>✕</button>
          </div>
        </div>
      )}

      <div className="store-content">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#94a3b8' }}>
            <FiRefreshCw className="spin" style={{ fontSize: '28px', marginBottom: '12px' }} />
            <div>Consultando status de pacotes na distribuição Linux...</div>
          </div>
        ) : error ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#f87171' }}>
            <FiAlertCircle style={{ fontSize: '32px', marginBottom: '8px' }} />
            <div>{error}</div>
            <button onClick={fetchPackages} style={{ marginTop: '16px', padding: '8px 16px', borderRadius: '6px', background: '#4f46e5', color: '#fff', border: 'none', cursor: 'pointer' }}>Tentar Novamente</button>
          </div>
        ) : filteredPackages.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#94a3b8' }}>
            Nenhum aplicativo encontrado para os filtros selecionados.
          </div>
        ) : (
          <div className="app-grid">
            {filteredPackages.map((pkg) => {
              const isFav = favorites.has(pkg.id);
              const isBusy = installingId === pkg.id || uninstallingId === pkg.id;

              return (
                <div key={pkg.id} className="app-card">
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <div style={{ display: 'flex', gap: '14px', alignItems: 'center' }}>
                      <div style={{ fontSize: '32px', width: '48px', height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(255,255,255,0.06)', borderRadius: '12px', overflow: 'hidden' }}>
                        {typeof pkg.icon === 'string' && (pkg.icon.startsWith('/') || pkg.icon.startsWith('http')) ? (
                          <img src={pkg.icon} alt="" style={{ width: '32px', height: '32px', objectFit: 'contain' }} onError={(e) => { (e.target as HTMLElement).style.display = 'none'; }} />
                        ) : (
                          pkg.icon || '📦'
                        )}
                      </div>
                      <div>
                        <div style={{ fontWeight: 600, fontSize: '16px', color: '#fff' }}>{pkg.name}</div>
                        <div style={{ fontSize: '12px', color: '#94a3b8' }}>{pkg.packageName}</div>
                      </div>
                    </div>
                    <button
                      onClick={() => toggleFavorite(pkg.id)}
                      style={{
                        background: 'transparent',
                        border: 'none',
                        color: isFav ? '#fbbf24' : '#64748b',
                        cursor: 'pointer',
                        fontSize: '18px',
                        padding: '4px'
                      }}
                      title={isFav ? 'Remover dos favoritos' : 'Adicionar aos favoritos'}
                    >
                      <FiStar fill={isFav ? '#fbbf24' : 'none'} />
                    </button>
                  </div>

                  <div style={{ fontSize: '13px', color: '#cbd5e1', lineHeight: '1.4', minHeight: '36px' }}>
                    {pkg.description}
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 'auto', paddingTop: '12px', borderTop: '1px solid rgba(255,255,255,0.06)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: pkg.installed ? '#4ade80' : '#94a3b8' }}>
                      {pkg.installed ? <><FiCheck /> Instalado</> : <span>Disponível</span>}
                    </div>

                    <div style={{ display: 'flex', gap: '8px' }}>
                      {pkg.installed ? (
                        <>
                          <button
                            className="store-btn-launch"
                            onClick={() => handleLaunch(pkg)}
                            style={{
                              background: '#22c55e',
                              color: '#000',
                              fontWeight: 600,
                              border: 'none',
                              padding: '6px 14px',
                              borderRadius: '6px',
                              cursor: 'pointer',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '6px',
                              fontSize: '13px'
                            }}
                          >
                            <FiPlay /> Abrir
                          </button>
                          <button
                            disabled={isBusy}
                            onClick={() => handleUninstall(pkg)}
                            style={{
                              background: 'rgba(239, 68, 68, 0.15)',
                              color: '#f87171',
                              border: '1px solid rgba(239, 68, 68, 0.3)',
                              padding: '6px 10px',
                              borderRadius: '6px',
                              cursor: isBusy ? 'wait' : 'pointer',
                              fontSize: '13px'
                            }}
                            title="Desinstalar pacote"
                          >
                            <FiTrash2 />
                          </button>
                        </>
                      ) : (
                        <button
                          disabled={isBusy}
                          onClick={() => handleInstall(pkg)}
                          style={{
                            background: '#4f46e5',
                            color: '#fff',
                            fontWeight: 600,
                            border: 'none',
                            padding: '6px 14px',
                            borderRadius: '6px',
                            cursor: isBusy ? 'wait' : 'pointer',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '6px',
                            fontSize: '13px'
                          }}
                        >
                          <FiDownload /> {installingId === pkg.id ? 'Instalando...' : 'Instalar'}
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}