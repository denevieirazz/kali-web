import { useEffect, useState } from 'react';
import { nativeHostBridge, type NativeSession } from '../services/nativeHostBridge';

export function useNativeSessions() {
  const [sessions, setSessions] = useState<NativeSession[]>([]);

  useEffect(() => {
    if (!nativeHostBridge.available) return;
    let active = true;
    const unsubscribe = nativeHostBridge.onSessionsChanged(next => {
      if (active) setSessions(next);
    });
    nativeHostBridge.connect()
      .then(() => nativeHostBridge.listSessions())
      .then(result => { if (active) setSessions(result.sessions); })
      .catch(() => {});
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  return sessions;
}
