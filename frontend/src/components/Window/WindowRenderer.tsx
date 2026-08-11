// ============================================
// Window Renderer - Renders all open windows
// ============================================
import { Suspense } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { getAppComponent } from '../../core/appRegistry';
import Window from './Window';

export default function WindowRenderer() {
  const windows = useWindowManager(s => s.windows);

  return (
    <>
      {windows.map(win => {
        const AppComponent = getAppComponent(win.appId);

        return (
          <Window key={win.id} windowId={win.id}>
            <Suspense fallback={null}>
              <AppComponent windowId={win.id} />
            </Suspense>
          </Window>
        );
      })}
    </>
  );
}
