import { useEffect, useRef } from 'react';

const STORAGE_KEY = 'cloudos_window_state';

export function useWindowPersistence(windows, setWindows) {
  const isLoaded = useRef(false);
  const saveTimeout = useRef(null);

  // 1. Carregar estado salvo na montagem inicial
  useEffect(() => {
    if (isLoaded.current) return;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const parsedState = JSON.parse(saved);
        if (Array.isArray(parsedState) && parsedState.length > 0) {
          setWindows(parsedState);
        }
      }
    } catch (error) {
      console.error('[CloudOS] Falha ao carregar estado de janelas:', error);
    } finally {
      isLoaded.current = true;
    }
  }, [setWindows]);

  // 2. Salvar estado com Debounce
  useEffect(() => {
    if (!isLoaded.current) return;

    if (saveTimeout.current) clearTimeout(saveTimeout.current);

    saveTimeout.current = setTimeout(() => {
      try {
        const stateToSave = windows.map(w => ({
          id: w.id,
          appId: w.appId,
          x: w.x,
          y: w.y,
          w: w.w,
          h: w.h,
          z: w.z,
          payload: w.payload || null
        }));
        localStorage.setItem(STORAGE_KEY, JSON.stringify(stateToSave));
      } catch (error) {
        console.error('[CloudOS] Falha ao salvar janelas:', error);
      }
    }, 500);

    return () => {
      if (saveTimeout.current) clearTimeout(saveTimeout.current);
    };
  }, [windows]);

  // 3. Listener para salvar antes de fechar a aba
  useEffect(() => {
    const handleBeforeUnload = () => {
      try {
        const stateToSave = windows.map(w => ({
          id: w.id,
          appId: w.appId,
          x: w.x,
          y: w.y,
          w: w.w,
          h: w.h,
          z: w.z,
          payload: w.payload || null
        }));
        localStorage.setItem(STORAGE_KEY, JSON.stringify(stateToSave));
      } catch (e) {}
    };
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [windows]);
}
