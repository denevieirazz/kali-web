import { useEffect } from 'react';
import { refreshUnifiedAppRegistry } from '../services/systemHubClient';
import type { BootPhase } from '../stores/systemStore';

const VISIBLE_SYNC_INTERVAL_MS = 30_000;

/**
 * Keeps the source-aware Windows + Linux app registry current while the CloudOS desktop
 * remains open. The backend owns the expensive discovery cache/TTL; this hook only asks
 * for a forced snapshot once per desktop entry and cache-aware snapshots afterwards.
 */
export function useUnifiedAppCatalogSync(bootPhase: BootPhase, isAuthenticated: boolean) {
  useEffect(() => {
    if (bootPhase !== 'desktop' || !isAuthenticated) return undefined;

    let disposed = false;
    let refreshInFlight = false;

    const syncCatalog = async (force = false) => {
      if (disposed || refreshInFlight) return;
      refreshInFlight = true;
      try {
        await refreshUnifiedAppRegistry(force);
      } catch {
        // Discovery is additive to the shell. A transient local scanner failure must not
        // tear down the desktop or fabricate a stale app as launchable.
      } finally {
        refreshInFlight = false;
      }
    };

    const syncWhenVisible = () => {
      if (document.visibilityState === 'visible') void syncCatalog(false);
    };

    void syncCatalog(true);
    document.addEventListener('visibilitychange', syncWhenVisible);
    window.addEventListener('focus', syncWhenVisible);
    const interval = window.setInterval(syncWhenVisible, VISIBLE_SYNC_INTERVAL_MS);

    return () => {
      disposed = true;
      document.removeEventListener('visibilitychange', syncWhenVisible);
      window.removeEventListener('focus', syncWhenVisible);
      window.clearInterval(interval);
    };
  }, [bootPhase, isAuthenticated]);
}
