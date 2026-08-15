import { memo, Suspense } from 'react';
import { getAppComponent } from '../../core/appRegistry';
import { useWindowManager } from '../../stores/windowManager';
import Window from './Window';

const RenderedWindow = memo(function RenderedWindow({
  windowId,
  appId,
}: {
  windowId: string;
  appId: string;
}) {
  const AppComponent = getAppComponent(appId);

  return (
    <Window windowId={windowId}>
      <Suspense
        fallback={(
          <div className="cloudos-window-loading" role="status" aria-live="polite">
            <span className="cloudos-window-loading-spinner" aria-hidden="true" />
            <span>Carregando aplicativo…</span>
          </div>
        )}
      >
        <AppComponent windowId={windowId} />
      </Suspense>
    </Window>
  );
});

export default function WindowRenderer() {
  const windows = useWindowManager(state => state.windows);

  return (
    <>
      {windows.map(window => (
        <RenderedWindow key={window.id} windowId={window.id} appId={window.appId} />
      ))}
    </>
  );
}
