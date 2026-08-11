import kernel from '../core/kernel';
import { useUserStore } from '../stores/userStore';

/**
 * LiveMode Cloud Sync Utility
 * 
 * Envia dados do Registro e configurações para o backend hospedado na Render.
 */
class CloudSync {
  private isSyncing = false;
  private lastSyncTime = 0;
  private SYNC_COOLDOWN = 10000; // 10 segundos para não inundar o servidor

  // A URL pode ser alterada via Registro: HKEY_LOCAL_MACHINE\SYSTEM\LiveMode\ApiUrl
  private getApiUrl() {
    const regUrl = kernel.regGetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\LiveMode\\ApiUrl') as string;
    if (regUrl) return regUrl;

    // Se estiver em ambiente de produção unificado, usa a própria URL do site
    if (typeof window !== 'undefined') {
      return window.location.origin;
    }
    
    return 'http://localhost:3000';
  }

  constructor() {
    this.setupListeners();
  }

  private setupListeners() {
    kernel.on('registry:snapshot', (hives) => {
      this.debouncedSync(hives);
    });
  }

  private debouncedSync(hives: any) {
    if (this.isSyncing) return;
    
    const now = Date.now();
    if (now - this.lastSyncTime < this.SYNC_COOLDOWN) return;

    this.sync(hives);
  }

  private async sync(hives: any) {
    const { currentUser, isAuthenticated } = useUserStore.getState();
    if (!isAuthenticated || !currentUser) return;

    this.isSyncing = true;
    const apiUrl = this.getApiUrl();

    try {
      const themePath = 'HKEY_CURRENT_USER\\Software\\ObsidianOS\\Theme';
      const desktopPath = 'HKEY_CURRENT_USER\\Control Panel\\Desktop';

      const syncPayload = {
        username: currentUser.username,
        timestamp: Date.now(),
        settings: {
          theme: hives[themePath] || {},
          desktop: hives[desktopPath] || {}
        }
      };

      // CHAMADA REAL VIA FETCH
      const response = await fetch(`${apiUrl}/api/v1/sync`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${sessionStorage.getItem('obs_token')}`
        },
        body: JSON.stringify(syncPayload)
      });

      if (!response.ok) throw new Error(`HTTP Error: ${response.status}`);
      
      this.lastSyncTime = Date.now();
      kernel.log('INFO', 'CloudSync', 'Sincronização com Render concluída com sucesso.');
    } catch (err) {
      console.error('[CloudSync] Falha ao sincronizar:', err);
      kernel.log('ERROR', 'CloudSync', 'Erro ao conectar com o servidor LiveMode.');
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Autenticação real com o backend
   */
  public async loginCloud(username: string, password: string) {
    const apiUrl = this.getApiUrl();
    try {
      const response = await fetch(`${apiUrl}/api/v1/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
      });

      if (!response.ok) return null;

      const data = await response.json();
      // Salva o token de sessão do ObsidianOS
      sessionStorage.setItem('obs_token', data.token);
      return data.user;
    } catch (err) {
      console.error('[CloudSync] Erro no login remoto:', err);
      return null;
    }
  }
}

const cloudSync = new CloudSync();
export default cloudSync;
