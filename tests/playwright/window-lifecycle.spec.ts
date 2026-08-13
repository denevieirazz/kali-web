import { test, expect } from './fixtures/cloudos.fixture';
import { login, openStartMenu, launchApp, stabilizeWindowForSnapshot } from './helpers/cloudos.ui';

test.describe('PW-03 — Ciclo de Vida de Janela', () => {
  test('abre Calculadora, minimiza, restaura pelo Start Abertos e encerra a janela', async ({ page, cloudos }) => {
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await launchApp(page, 'Calculadora');

    const calculatorWindow = page.locator('.window', { hasText: 'Calculadora' });
    await expect(calculatorWindow).toBeVisible({ timeout: 10_000 });
    await stabilizeWindowForSnapshot(calculatorWindow, 240, 36);

    const taskbarButton = page.locator('button.taskbar-app-btn[title="Calculadora"]');
    await expect(taskbarButton).toBeVisible({ timeout: 5_000 });

    await openStartMenu(page);
    const startMenu = page.locator('.start-menu');
    await expect(startMenu).toBeVisible();

    const runningTab = startMenu.locator('.start-native-tabs button', { hasText: 'Abertos' });
    await runningTab.click();
    await expect(runningTab).toHaveClass(/active/);

    const runningItem = startMenu.locator('.running-item', { hasText: 'Calculadora' });
    await expect(runningItem).toBeVisible({ timeout: 5_000 });
    await expect(page).toHaveScreenshot('start-running-calculator.png');

    await runningItem.locator('button[title="Minimizar"]').click();
    await expect(taskbarButton).toHaveClass(/minimized/);
    await expect(calculatorWindow).toHaveCount(0);

    await runningItem.locator('.running-main').click();
    await expect(page.locator('.start-menu')).toHaveCount(0);
    await expect(taskbarButton).not.toHaveClass(/minimized/);
    await expect(calculatorWindow).toBeVisible();

    await calculatorWindow.locator('button.window-btn.close').click();
    await expect(calculatorWindow).toHaveCount(0);
    await expect(taskbarButton).toHaveCount(0);
  });
});
