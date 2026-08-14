import { useEffect, useRef, useState } from 'react';
import { nativeHostBridge } from '../../services/nativeHostBridge';
import { useProcessManager } from '../../stores/processManager';
import { useWindowManager } from '../../stores/windowManager';
import './Browser.css';

export default function BrowserApp({ windowId }: { windowId: string }) {
  const [state, setState] = useState<'opening' | 'unavailable' | 'error'>('opening');
  const [message, setMessage] = useState('Abrindo o Navegador CloudOS…');
  const started = useRef(false);
  const getProcessByWindowId = useProcessManager((s) => s.getProcessByWindowId);
  const terminateProcess = useProcessManager((s) => s.terminateProcess);
  const closeWindow = useWindowManager((s) => s.closeWindow);

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    if (!nativeHostBridge.available) {
      setState('unavailable');
      setMessage('O Navegador CloudOS requer o Host nativo.');
      return;
    }

    let cancelled = false;
    void nativeHostBridge.openBrowser()
      .then((result) => {
        if (cancelled || !result.opened) return;
        const process = getProcessByWindowId(windowId);
        if (process) terminateProcess(process.pid);
        else closeWindow(windowId);
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        setState('error');
        setMessage(error instanceof Error ? error.message : 'O navegador nativo não pôde ser aberto.');
      });

    return () => {
      cancelled = true;
    };
  }, [closeWindow, getProcessByWindowId, terminateProcess, windowId]);

  return (
    <div className="cloudos-browser-launcher" role="status" aria-live="polite">
      <div className="browser-launcher-card">
        <div className="browser-launcher-icon" aria-hidden="true">◎</div>
        <h2>Navegador CloudOS</h2>
        <p>{message}</p>
        {state === 'opening' && <div className="browser-launcher-spinner" aria-label="Abrindo" />}
        {state !== 'opening' && (
          <small>
            Sites externos não são carregados por iframe nem enviados ao navegador padrão do Windows.
          </small>
        )}
      </div>
    </div>
  );
}
