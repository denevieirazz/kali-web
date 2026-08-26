import { test, expect } from './fixtures/cloudos.fixture';
import { login, openStartMenu, openAllApps } from './helpers/cloudos.ui';

const deterministicWindowsCatalog = [
  {
    id: 'native-aaaaaaaaaaaaaaaaaaaaaaaa',
    name: 'Windows Fixture Editor',
    source: 'windows',
    distribution: null,
    icon: '▦',
    iconUrl: null,
    comment: 'Deterministic Playwright catalog fixture',
    keywords: ['Windows', 'Fixture'],
    categories: ['Windows'],
    category: 'windows',
    mimeTypes: [],
    windowMode: 'unavailable',
    launchable: false
  },
  {
    id: 'native-bbbbbbbbbbbbbbbbbbbbbbbb',
    name: 'Windows Fixture Browser',
    source: 'windows',
    distribution: null,
    icon: '▦',
    iconUrl: null,
    comment: 'Deterministic Playwright catalog fixture',
    keywords: ['Windows', 'Fixture'],
    categories: ['Windows'],
    category: 'windows',
    mimeTypes: [],
    windowMode: 'unavailable',
    launchable: false
  }
];

test.describe('PW-02 — Menu Iniciar', () => {
  test('abre seções Início, Todos os apps com catálogo completo e fecha com Escape', async ({ page, cloudos }) => {
    // Visual characterization must not depend on the mutable Windows image installed
    // on GitHub-hosted runners. Backend unit tests cover real shortcut discovery;
    // this fixture keeps the Start Menu rendering contract deterministic.
    await page.route('**/api/apps**', async (route) => {
      if (route.request().method() !== 'GET') {
        await route.continue();
        return;
      }
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ apps: deterministicWindowsCatalog })
      });
    });

    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await openStartMenu(page);

    const startMenu = page.locator('.start-menu');
    await expect(startMenu).toBeVisible();

    const tabs = page.locator('.start-native-tabs');
    const homeTab = tabs.locator('button', { hasText: 'Início' });
    const allTab = tabs.locator('button', { hasText: 'Todos' });
    const runningTab = tabs.locator('button', { hasText: 'Abertos' });
    await expect(homeTab).toBeVisible();
    await expect(allTab).toBeVisible();
    await expect(runningTab).toBeVisible();
    // Home remains a strict pixel-for-pixel contract. Adding a catalog entry must not replace a pinned app.
    await expect(page).toHaveScreenshot('start-menu-home.png');

    await openAllApps(page);
    for (const name of ['Calculadora', 'Bloco de Notas', 'Configurações', 'Explorador de Arquivos', 'Gerenciador de Tarefas', 'Kali Tool Center', 'Windows Fixture Editor', 'Windows Fixture Browser']) {
      await expect(page.locator('.start-app-btn', { hasText: name })).toBeVisible({ timeout: 5_000 });
    }
    expect(await page.locator('.start-app-btn').count()).toBeGreaterThanOrEqual(10);

    // The deterministic catalog image is a strict visual contract. Intentional UI changes must refresh the baseline.
    await expect(page).toHaveScreenshot('start-menu-all.png');

    await page.keyboard.press('Escape');
    await expect(page.locator('.start-menu')).toHaveCount(0);
    await openStartMenu(page);
    await expect(page.locator('.start-menu')).toBeVisible();
  });
});
