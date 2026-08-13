import { test, expect } from './fixtures/cloudos.fixture';
import { waitForOobe, waitForDesktop } from './helpers/cloudos.ui';

test.describe('PW-01 — Boot e Primeiro Acesso (OOBE)', () => {
  test('conclui o fluxo completo de primeiro acesso e inicializa o desktop', async ({ page, cloudos }) => {
    await waitForOobe(page, cloudos.baseURL);
    await expect(page).toHaveScreenshot('oobe-welcome.png');

    const continueButton = page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Continuar' });
    await continueButton.click();

    await page.getByRole('textbox', { name: 'Nome de exibição' }).fill('Playwright Admin');
    await page.getByRole('textbox', { name: 'Nome de usuário' }).fill('playwright.admin');
    await page.getByLabel('Senha', { exact: true }).fill('CloudOS-Test-2026!');
    await page.getByLabel('Confirmar senha', { exact: true }).fill('CloudOS-Test-2026!');
    await continueButton.click();

    const emeraldColorButton = page.locator('button[aria-label="Cor #10b981"]');
    await expect(emeraldColorButton).toBeVisible({ timeout: 5_000 });
    await emeraldColorButton.click();

    const createAccountButton = page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Criar conta' });
    await createAccountButton.click();

    const recoveryCodeElement = page.locator('.setup-recovery-code code');
    await expect(recoveryCodeElement).toBeVisible({ timeout: 15_000 });
    const recoveryCodeText = (await recoveryCodeElement.textContent())?.trim();
    expect(recoveryCodeText).toBeTruthy();
    expect(recoveryCodeText?.length).toBeGreaterThan(10);

    const enterButton = page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Entrar no CloudOS' });
    await expect(enterButton).toBeDisabled();
    await page.locator('.setup-confirm-save input[type="checkbox"]').check();
    await expect(enterButton).toBeEnabled();
    await enterButton.click();

    await waitForDesktop(page);
    expect(await page.evaluate(() => localStorage.getItem('obsidianos-setup-completed'))).toBe('true');
    expect(await page.evaluate(() => localStorage.getItem('cloudos_jwt_token'))).toBeTruthy();
    await expect(page).toHaveScreenshot('desktop-after-oobe.png');
  });
});
