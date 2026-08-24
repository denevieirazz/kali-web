import { test, expect } from './fixtures/cloudos.fixture';
import { waitForOobe, waitForDesktop } from './helpers/cloudos.ui';

test.describe('PW-01 — Boot e Primeiro Acesso (OOBE)', () => {
  test('conclui o fluxo completo de primeiro acesso e inicializa o desktop', async ({ page, cloudos }) => {
    await waitForOobe(page, cloudos.baseURL);

    const welcomeBtn = page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Começar' }).or(page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Continuar' })).first();
    if (await welcomeBtn.isVisible()) {
      await welcomeBtn.click();

      // Distro select step
      const distroBtn = page.locator('.setup-footer button.setup-btn-primary').first();
      await distroBtn.click();

      // Installing runtime step automatically advances to account
      await expect(page.locator('.setup-form')).toBeVisible({ timeout: 25_000 });
    }

    // Account creation step
    const nameInput = page.locator('.setup-form input').nth(0);
    await nameInput.fill('Playwright Admin');
    const userInput = page.locator('.setup-form input').nth(1);
    await userInput.fill('playwright.admin');
    const pwdInput = page.locator('.setup-password-grid input[type="password"]').nth(0);
    await pwdInput.fill('CloudOS-Test-2026!');
    const confirmPwdInput = page.locator('.setup-password-grid input[type="password"]').nth(1);
    await confirmPwdInput.fill('CloudOS-Test-2026!');

    const emeraldColorButton = page.locator('button[aria-label="Cor #10b981"]');
    if (await emeraldColorButton.isVisible()) {
      await emeraldColorButton.click();
    }

    const createAccountButton = page.locator('.setup-footer button.setup-btn-primary');
    await createAccountButton.click();

    // Ready step with recovery code
    const recoveryCodeElement = page.locator('.setup-content code');
    await expect(recoveryCodeElement).toBeVisible({ timeout: 15_000 });
    const recoveryCodeText = (await recoveryCodeElement.textContent())?.trim();
    expect(recoveryCodeText).toBeTruthy();
    expect(recoveryCodeText?.length).toBeGreaterThan(10);

    const continueWithoutSaveBtn = page.locator('button:has-text("Continuar sem salvar")').first();
    if (await continueWithoutSaveBtn.isVisible()) {
      page.once('dialog', dialog => dialog.accept());
      await continueWithoutSaveBtn.click();
    } else {
      const enterButton = page.locator('.setup-footer button.setup-btn-primary');
      await enterButton.click();
    }

    await waitForDesktop(page);
    expect(await page.evaluate(() => localStorage.getItem('cloudos_jwt_token'))).toBeTruthy();
  });
});
