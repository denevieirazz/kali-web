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
    await expect(page).toHaveScreenshot('start-menu-home.png');

    await openAllApps(page);
    for (const name of ['Calculadora', 'Bloco de Notas', 'Configurações', 'Explorador de Arquivos', 'Gerenciador de Tarefas']) {
      await expect(page.locator('.start-app-btn', { hasText: name })).toBeVisible({ timeout: 5_000 });
    }
    expect(await page.locator('.start-app-btn').count()).toBeGreaterThanOrEqual(10);
    await expect(page).toHaveScreenshot('start-menu-all.png');

    await page.keyboard.press('Escape');
    await expect(page.locator('.start-menu')).toHaveCount(0);
    await openStartMenu(page);
    await expect(page.locator('.start-menu')).toBeVisible();
  });
});
