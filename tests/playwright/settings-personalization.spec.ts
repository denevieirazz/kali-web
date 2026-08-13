import { test, expect } from './fixtures/cloudos.fixture';
import { login, openSettingsPersonalization, stabilizeWindowForSnapshot } from './helpers/cloudos.ui';

const MINIMAL_PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

test.describe('PW-04/05/06 — Configurações e Personalização', () => {
  test('PW-04 — altera a cor de destaque (accent color)', async ({ page, cloudos }) => {
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await openSettingsPersonalization(page);
    await stabilizeWindowForSnapshot(page.locator('.window', { has: page.locator('.settings-app') }), 240, 36);
    await expect(page).toHaveScreenshot('settings-personalization.png');

    const beforeAccent = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()
    );
    const greenAccentButton = page.locator('.settings-accent-grid button[aria-label="#22c55e"]');
    await expect(greenAccentButton).toBeVisible({ timeout: 5_000 });
    await greenAccentButton.click();
    const afterAccent = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()
    );

    expect(afterAccent).not.toBe(beforeAccent);
    await expect(page.locator('.settings-app')).toBeVisible();
    await expect(page.locator('.desktop')).toBeVisible();
  });

  test('PW-05 — altera a posição da barra de tarefas para o topo', async ({ page, cloudos }) => {
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await openSettingsPersonalization(page);

    const positionRow = page.locator('.settings-data-row', { hasText: 'Posição' });
    await positionRow.locator('select.settings-select').selectOption('top');
    const taskbar = page.locator('.taskbar');
    await expect(taskbar).toHaveClass(/position-top/);
    await expect(page.locator('.desktop')).toBeVisible();
    await stabilizeWindowForSnapshot(page.locator('.window', { has: page.locator('.settings-app') }), 240, 36);
    await expect(page).toHaveScreenshot('settings-taskbar-top.png');
  });

  test('PW-06 — aplica plano de fundo pessoal (custom wallpaper)', async ({ page, cloudos }) => {
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await openSettingsPersonalization(page);

    const fileInput = page.locator('.settings-card input[type="file"]');
    const reload = page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 10_000 });
    await fileInput.setInputFiles({
      name: 'characterization.png',
      mimeType: 'image/png',
      buffer: Buffer.from(MINIMAL_PNG_BASE64, 'base64')
    });
    await reload;
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');

    const wallpaperData = await page.evaluate(() => localStorage.getItem('cloudos.customWallpaper.v1'));
    expect(wallpaperData).toBeTruthy();
    expect(wallpaperData?.startsWith('data:image/png;base64,')).toBe(true);
    const backgroundImage = await page.evaluate(() => {
      const desktop = document.querySelector('.desktop');
      return desktop ? getComputedStyle(desktop).backgroundImage : 'none';
    });
    expect(backgroundImage).not.toBe('none');
    await expect(page).toHaveScreenshot('desktop-custom-wallpaper.png');
  });
});
