import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import { isNativeShellWebView } from './native-shell/nativeBridge';

async function bootstrap() {
  const nativeSurface = isNativeShellWebView();
  if (!nativeSurface) {
    await Promise.all([
      import('./native/themeSync'),
      import('./native/responsiveShell.css'),
      import('./native/nativeHotfix.css'),
    ]);
  }

  const module = nativeSurface
    ? await import('./native-shell/NativeShellSurface')
    : await import('./App');
  const RootSurface = module.default;

  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <RootSurface />
    </StrictMode>,
  );
}

void bootstrap();
