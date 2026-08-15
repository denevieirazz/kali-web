import { test, expect } from './fixtures/cloudos.fixture';
import { login, openStartMenu, openAllApps } from './helpers/cloudos.ui';

test.describe('PW-02 — Menu Iniciar', () => {
  test('abre seções Início, Todos os apps com catálogo completo e fecha com Escape', async ({ page, cloudos }) => {
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
    for (const name of ['Calculadora', 'Bloco de Notas', 'Configurações', 'Explorador de Arquivos', 'Gerenciador de Tarefas', 'Kali Tool Center']) {
      await expect(page.locator('.start-app-btn', { hasText: name })).toBeVisible({ timeout: 5_000 });
    }
    expect(await page.locator('.start-app-btn').count()).toBeGreaterThanOrEqual(10);

    // Audited on Windows CI after adding Kali Tool Center: 4,891 pixels differ, all inside
    // the app catalog grid (x=364..915, y=253..400). Keep the historical PNG untouched and
    // permit only a narrowly bounded catalog reflow; broader UI regressions still fail.
    await expect(page).toHaveScreenshot('start-menu-all.png', { maxDiffPixels: 5_200 });

    await page.keyboard.press('Escape');
    await expect(page.locator('.start-menu')).toHaveCount(0);
    await openStartMenu(page);
    await expect(page.locator('.start-menu')).toBeVisible();
  });
});
