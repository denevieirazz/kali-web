import { Locator, Page, expect } from '@playwright/test';

export interface ErrorGuards {
  pageErrors: Error[];
  consoleErrors: string[];
  requestFailures: string[];
  serverErrors: string[];
  assertNoErrors: () => void;
}

export function installBrowserErrorGuards(page: Page): ErrorGuards {
  const pageErrors: Error[] = [];
  const consoleErrors: string[] = [];
  const requestFailures: string[] = [];
  const serverErrors: string[] = [];

  page.on('pageerror', (error) => {
    pageErrors.push(error);
  });

  page.on('console', (message) => {
    if (message.type() === 'error') {
      consoleErrors.push(message.text());
    }
  });

  page.on('requestfailed', (request) => {
    const failure = request.failure();
    if (failure && failure.errorText !== 'net::ERR_ABORTED') {
      requestFailures.push(`${request.method()} ${request.url()} - ${failure.errorText}`);
    }
  });

  page.on('response', (response) => {
    if (response.status() >= 500) {
      serverErrors.push(`${response.status()} ${response.request().method()} ${response.url()}`);
    }
  });

  const assertNoErrors = () => {
    if (pageErrors.length > 0) {
      throw new Error(`Erros de pagina (pageerror) detectados (${pageErrors.length}):\n${pageErrors.map(error => error.stack || error.message).join('\n')}`);
    }
    if (consoleErrors.length > 0) {
      throw new Error(`Erros de console (console.error) detectados (${consoleErrors.length}):\n${consoleErrors.join('\n')}`);
    }
    if (requestFailures.length > 0) {
      throw new Error(`Falhas de requisicao detectadas (${requestFailures.length}):\n${requestFailures.join('\n')}`);
    }
    if (serverErrors.length > 0) {
      throw new Error(`Respostas HTTP 5xx detectadas (${serverErrors.length}):\n${serverErrors.join('\n')}`);
    }
  };

  return {
    pageErrors,
    consoleErrors,
    requestFailures,
    serverErrors,
    assertNoErrors
  };
}

export async function waitForOobe(page: Page, baseURL: string): Promise<void> {
  await page.goto(baseURL);
  await expect(page.locator('.setup-wizard')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('.setup-title').first()).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('.desktop')).toHaveCount(0);
  await expect(page.locator('.taskbar')).toHaveCount(0);
}

export async function waitForDesktop(page: Page): Promise<void> {
  await expect(page.locator('.desktop')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('.taskbar')).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('button[title="Iniciar"]')).toBeVisible({ timeout: 10_000 });
}

export async function login(page: Page, baseURL: string, username: string, password: string): Promise<void> {
  await page.goto(baseURL);
  await expect(page.locator('.cloudos-lock-screen')).toBeVisible({ timeout: 15_000 });

  const glassCard = page.locator('.cloudos-glass-card');
  if (!(await glassCard.isVisible())) {
    await page.locator('.cloudos-lock-screen').click({ position: { x: 200, y: 200 } });
  }
  await expect(glassCard).toBeVisible({ timeout: 5_000 });

  await page.locator('#login-username').fill(username);
  await page.locator('#login-password').fill(password);
  await page.locator('button[type="submit"]:has-text("Entrar")').click();

  await waitForDesktop(page);
}

// Posiciona apenas a superficie visual usada pelo snapshot. Nao altera nem valida
// o estado do window manager; testes de movimentacao devem usar interacao real separada.
export async function stabilizeWindowForSnapshot(windowLocator: Locator, x: number, y: number): Promise<void> {
  await windowLocator.evaluate((element, position) => {
    const marker = `position-${position.x}-${position.y}`;
    element.setAttribute('data-cloudos-playwright-position', marker);
    let stylesheet = document.querySelector<HTMLStyleElement>('#cloudos-playwright-window-position');
    if (!stylesheet) {
      stylesheet = document.createElement('style');
      stylesheet.id = 'cloudos-playwright-window-position';
      document.head.appendChild(stylesheet);
    }
    stylesheet.textContent = `.window[data-cloudos-playwright-position="${marker}"] { left: ${position.x}px !important; top: ${position.y}px !important; }`;
  }, { x, y });

  await expect.poll(async () => windowLocator.evaluate((element) => {
    const style = getComputedStyle(element);
    return { left: style.left, top: style.top };
  })).toEqual({ left: `${x}px`, top: `${y}px` });
}

export async function openStartMenu(page: Page): Promise<void> {
  const startButton = page.locator('button[title="Iniciar"]');
  await startButton.click();
  await expect(page.locator('.start-menu')).toBeVisible({ timeout: 5_000 });
}

export async function openAllApps(page: Page): Promise<void> {
  const tabs = page.locator('.start-native-tabs');
  await expect(tabs).toBeVisible({ timeout: 5_000 });
  const allTab = tabs.locator('button', { hasText: 'Todos' });
  await allTab.click();
  await expect(allTab).toHaveClass(/active/);
  await expect(page.locator('.start-app-btn').first()).toBeVisible({ timeout: 5_000 });
}

export async function launchApp(page: Page, name: string): Promise<void> {
  const startMenu = page.locator('.start-menu');
  if (!(await startMenu.isVisible())) {
    await openStartMenu(page);
  }
  await openAllApps(page);
  const appButton = page.locator('.start-app-btn', { hasText: name });
  await expect(appButton).toBeVisible({ timeout: 5_000 });
  await appButton.click();
}

export async function openSettingsPersonalization(page: Page): Promise<void> {
  await launchApp(page, 'Configurações');
  const settingsApp = page.locator('.settings-app');
  await expect(settingsApp).toBeVisible({ timeout: 10_000 });
  const personalizationNav = settingsApp.locator('.settings-nav-item', { hasText: 'Personalização' });
  await personalizationNav.click();
  await expect(personalizationNav).toHaveClass(/active/);
  await expect(settingsApp.locator('.settings-accent-grid')).toBeVisible({ timeout: 5_000 });
}
