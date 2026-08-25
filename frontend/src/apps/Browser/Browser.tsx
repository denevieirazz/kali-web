import { useCallback, useEffect, useRef, useState } from 'react';
import { nativeHostBridge } from '../../services/nativeHostBridge';
import { useProcessManager } from '../../stores/processManager';
import { useWindowManager } from '../../stores/windowManager';
import LinuxAppWindow from '../LinuxAppWindow/LinuxAppWindow';
import {
  browserLauncherFailure,
  browserLauncherOpening,
  browserLauncherSuccess,
} from './browserLauncherState.js';
import './Browser.css';

const HOST_REQUIRED_CODE = 'NATIVE_HOST_UNAVAILABLE';

export default function BrowserApp({ windowId }: { windowId: string }) {
  if (!nativeHostBridge.available) {
    return <LinuxAppWindow windowId={windowId} params={{ appId: 'firefox', title: 'Mozilla Firefox', icon: '🦊' }} />;
  }

  const [launcher, setLauncher] = useState(browserLauncherOpening);
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
    setLauncher(browserLauncherOpening());

    if (!nativeHostBridge.available) {
      launching.current = false;
      setLauncher({
        status: 'error',
        code: HOST_REQUIRED_CODE,
        message: 'Este recurso exige o modo Full. Feche esta sessão e execute “Iniciar CloudOS.cmd Full”.',
        shouldClose: false,
      });
      return;
    }

    try {
      const result = await nativeHostBridge.openBrowser();
      if (currentAttempt !== attempt.current) return;
      const next = browserLauncherSuccess(result);
      setLauncher(next);
      if (next.shouldClose) closeLauncher();
    } catch (error: unknown) {
      if (currentAttempt !== attempt.current) return;
      setLauncher(browserLauncherFailure(error));
    } finally {
      if (currentAttempt === attempt.current) launching.current = false;
    }
  }, [closeLauncher]);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void launchBrowser();
  }, [launchBrowser]);

  const hostUnavailable = launcher.code === HOST_REQUIRED_CODE;

  return (
    <div
      className="cloudos-browser-launcher"
      role="status"
      aria-live="polite"
      data-browser-capability={hostUnavailable ? 'requires-full' : launcher.status}
      data-browser-error-code={launcher.code || ''}
    >
      <div className="browser-launcher-card">
        <div className="browser-launcher-icon" aria-hidden="true">◎</div>
        <h2>Navegador CloudOS</h2>
        <p>{launcher.message}</p>
        {launcher.status === 'opening' && <div className="browser-launcher-spinner" aria-label="Abrindo" />}
        {launcher.status === 'error' && !hostUnavailable && (
          <button className="browser-launcher-retry" type="button" onClick={() => void launchBrowser()}>
            Tentar novamente
          </button>
        )}
        {hostUnavailable && (
          <button className="browser-launcher-retry" type="button" onClick={closeLauncher}>
            Fechar
          </button>
        )}
        {launcher.status !== 'opening' && (
          <small>
            Sites externos não são carregados por iframe nem enviados ao navegador padrão do Windows.
          </small>
        )}
      </div>
    </div>
  );
}
