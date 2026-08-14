import { chromium } from '@playwright/test';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i];
  const value = process.argv[i + 1];
  if (!key?.startsWith('--') || value === undefined) throw new Error('Argumentos inválidos.');
  args.set(key.slice(2), value);
}

const port = Number(args.get('port'));
const action = args.get('action') || 'ping';
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Porta CDP inválida.');

const deadline = Date.now() + 90_000;
let browser;
let lastError;
while (Date.now() < deadline) {
  try {
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
    break;
  } catch (error) {
    lastError = error;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}
if (!browser) throw lastError instanceof Error ? lastError : new Error('Shell CDP indisponível.');

try {
  const context = browser.contexts()[0];
  const pageDeadline = Date.now() + 90_000;
  let page;
  while (Date.now() < pageDeadline) {
    page = context?.pages().find((candidate) => candidate.url().startsWith('https://cloudos.local'));
    if (page) break;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  if (!page) throw new Error('Documento confiável do Shell não foi encontrado.');

  const result = await page.evaluate(async (requestedAction) => {
    const transport = window.chrome?.webview;
    const nonce = window.__cloudosNativeNonce;
    if (!transport || !nonce) throw new Error('Bridge nativa não está pronta.');

    const request = (method, params = {}) => new Promise((resolve, reject) => {
      const id = crypto.randomUUID();
      const timer = window.setTimeout(() => {
        transport.removeEventListener('message', onMessage);
        reject(new Error(`Timeout em ${method}`));
      }, 30_000);
      function onMessage(event) {
        const message = event.data;
        if (!message || message.type !== 'response' || message.id !== id) return;
        window.clearTimeout(timer);
        transport.removeEventListener('message', onMessage);
        if (message.ok) resolve(message.result);
        else reject(new Error(message.error?.code || 'NATIVE_REQUEST_FAILED'));
      }
      transport.addEventListener('message', onMessage);
      transport.postMessage({ v: 1, id, type: 'request', method, nonce, params });
    });

    await request('bridge.handshake');
    if (requestedAction === 'open-twice') {
      const [first, second] = await Promise.all([
        request('browser.open', {}),
        request('browser.open', {}),
      ]);
      return { action: requestedAction, first, second };
    }
    if (requestedAction === 'ping') {
      const host = await request('host.getState', {});
      return {
        action: requestedAction,
        nativeHost: host?.nativeHost === true,
        platform: host?.platform || null,
      };
    }
    throw new Error('Ação de smoke desconhecida.');
  }, action);

  process.stdout.write(JSON.stringify(result));
} finally {
  if (browser?.isConnected()) {
    try {
      await browser.close();
    } catch (error) {
      const name = error instanceof Error ? error.name : 'Error';
      process.stderr.write(`WARN CDP disconnect failed: ${name}\n`);
    }
  }
}
