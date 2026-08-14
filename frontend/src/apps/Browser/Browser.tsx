import { useCallback, useEffect, useRef, useState } from 'react';
import { NativeHostError, nativeHostBridge } from '../../services/nativeHostBridge';
import { useProcessManager } from '../../stores/processManager';
import { useWindowManager } from '../../stores/windowManager';
import './Browser.css';

type LauncherState = 'opening' | 'unavailable' | 'error';

export default function BrowserApp({ windowId }: { windowId: string }) {
  const [state, setState] = useState<LauncherState>('opening');
  const [message, setMessage] = useState('Abrindo o Navegador CloudOS…');
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const started = useRef(false);
  const launching = useRef(false);
  const attempt = useRef(0);
  const getProcessByWindowId = useProcessManager((s) => s.getProcessByWindowId);
  const terminateProcess = useProcessManager((s) => s.terminateProcess);
  const closeWindow = useWindowManager((s) => s.closeWindow);

  const closeLauncher = useCallback(() => {
    const process = getProcessByWindowId(windowId);
    if (process) terminateProcess(process.pid);
    else closeWindow(windowId);
  }, [closeWindow, getProcessByWindowId, terminateProcess, windowId]);

  const launchBrowser = useCallback(async () => {
    if (launching.current) return;
    launching.current = true;
    const currentAttempt = ++attempt.current;
    setState('opening');
    setMessage('Abrindo o Navegador CloudOS…');
    setErrorCode(null);

    if (!nativeHostBridge.available) {
      launching.current = false;
      setState('unavailable');
      setErrorCode('NATIVE_HOST_UNAVAILABLE');
      setMessage('O Navegador CloudOS requer o Host nativo.');
      return;
    }

    try {
      const result = await nativeHostBridge.openBrowser();
      if (currentAttempt !== attempt.current) return;
      if (result.opened && result.windowVisible === true) closeLauncher();
    } catch (error: unknown) {
      if (currentAttempt !== attempt.current) return;
      const nativeError = error instanceof NativeHostError ? error : null;
      setState('error');
      setErrorCode(nativeError?.code || 'BROWSER_OPEN_FAILED');
      setMessage(error instanceof Error ? error.message : 'O navegador nativo não pôde ser aberto.');
    } finally {
      if (currentAttempt === attempt.current) launching.current = false;
    }
  }, [closeLauncher]);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void launchBrowser();
  }, [launchBrowser]);

  return (
    <div className="cloudos-browser-launcher" role="status" aria-live="polite">
      <div className="browser-launcher-card">
        <div className="browser-launcher-icon" aria-hidden="true">◎</div>
        <h2>Navegador CloudOS</h2>
        {errorCode && <code className="browser-launcher-error-code">{errorCode}</code>}
        <p>{message}</p>
        {state === 'opening' && <div className="browser-launcher-spinner" aria-label="Abrindo" />}
        {state === 'error' && (
          <button className="browser-launcher-retry" type="button" onClick={() => void launchBrowser()}>
            Tentar novamente
          </button>
        )}
        {state !== 'opening' && (
          <small>
            Sites externos não são carregados por iframe nem enviados ao navegador padrão do Windows.
          </small>
        )}
      </div>
    </div>
  );
}
