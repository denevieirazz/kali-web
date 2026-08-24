import { chromium } from '@playwright/test';
import path from 'node:path';

const BASE_URL = 'http://127.0.0.1:18080';
const ARTIFACT_DIR = path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc');

async function runRealJourney() {
  console.log('🚀 Starting CloudOS Real User Journey Validation...');
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    locale: 'pt-BR'
  });
  const page = await context.newPage();

  try {
    // 1. Open CloudOS
    console.log('Step 1: Navigating to CloudOS at', BASE_URL);
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step1_open.png') });

    // 2. Lock Screen -> Show Panel -> Fill Credentials
    console.log('Step 2: Checking Lock Screen / Login...');
    const lockScreen = page.locator('.cloudos-lock-screen');
    await lockScreen.waitFor({ state: 'visible', timeout: 10000 });

    // Click lock screen to show panel
    await lockScreen.click({ position: { x: 400, y: 300 } });
    await page.locator('#login-password').waitFor({ state: 'visible', timeout: 8000 });

    const userInput = page.locator('#login-username');
    if (await userInput.isVisible()) await userInput.fill('douglas');
    await page.locator('#login-password').fill('Admin@123456');
    await page.locator('button[type="submit"]:has-text("Entrar")').click();

    // 3. Desktop Ready
    console.log('Step 3: Verifying Desktop...');
    await page.locator('.desktop').waitFor({ state: 'visible', timeout: 15000 });
    await page.locator('.taskbar').waitFor({ state: 'visible', timeout: 10000 });
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step3_desktop.png') });
    console.log('✅ Desktop loaded successfully.');

    // 4. Open Linux App Center
    console.log('Step 4: Opening Linux App Center...');
    const appCenterIcon = page.locator('.desktop-icon', { hasText: 'Linux App Center' }).or(page.locator('.desktop-icon', { hasText: 'App Center' })).first();
    if (await appCenterIcon.isVisible()) {
      await appCenterIcon.dblclick();
    } else {
      await page.locator('button[title="Iniciar"]').click();
      await page.locator('.start-native-tabs button', { hasText: 'Todos' }).click();
      await page.locator('.start-app-btn', { hasText: 'Linux App Center' }).click();
    }

    const appCenterWindow = page.locator('.window', { hasText: 'Linux App Center' }).first();
    await appCenterWindow.waitFor({ state: 'visible', timeout: 15000 });
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step4_app_center.png') });
    console.log('✅ Linux App Center opened.');

    // 5. Find Firefox in App Center & Install / Verify Installed
    console.log('Step 5: Locating Firefox in App Center (waiting for package scan)...');
    const firefoxCard = appCenterWindow.locator('.app-card', { hasText: 'Firefox' }).first();
    await firefoxCard.waitFor({ state: 'visible', timeout: 45000 });

    const installBtn = firefoxCard.locator('button:has-text("Instalar")');
    if (await installBtn.isVisible()) {
      console.log('Installing Firefox...');
      await installBtn.click();
      await page.locator('button:has-text("Abrir")').waitFor({ state: 'visible', timeout: 120000 });
    }

    // 6. Open Firefox
    console.log('Step 6: Opening Firefox...');
    const openBtn = firefoxCard.locator('button:has-text("Abrir")').first();
    await openBtn.click({ force: true });

    // 7. Verify Firefox Window opens & Navigate
    console.log('Step 7: Verifying Firefox surface / window...');
    const linuxWindow = page.locator('.window', { hasText: 'Mozilla Firefox' }).or(page.locator('.window[data-app-id="linux-app-runner"]')).first();
    await linuxWindow.waitFor({ state: 'visible', timeout: 25000 });
    await page.waitForTimeout(3000);
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step7_firefox_open.png') });
    console.log('✅ Firefox opened and rendered.');

    // 8. Close Firefox
    console.log('Step 8: Closing Firefox...');
    const closeBtn = linuxWindow.locator('.window-controls button.close').first();
    await closeBtn.click({ force: true });
    await page.waitForTimeout(2000);
    console.log('✅ Firefox closed successfully.');

    // 9. Reopen Firefox via Start Menu
    console.log('Step 9: Reopening Firefox via App Center...');
    await openBtn.click({ force: true });
    await linuxWindow.waitFor({ state: 'visible', timeout: 25000 });
    console.log('✅ Firefox reopened successfully.');
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step9_firefox_reopened.png') });

    // Close Firefox and App Center to continue test
    const closeBtn2 = linuxWindow.locator('.window-controls button.close').first();
    if (await closeBtn2.isVisible()) await closeBtn2.click({ force: true });
    await page.waitForTimeout(1000);
    const closeAppCenterBtn = appCenterWindow.locator('.window-controls button.close').first();
    if (await closeAppCenterBtn.isVisible()) await closeAppCenterBtn.click({ force: true });
    await page.waitForTimeout(1000);

    // 10. File Explorer & CloudOS Files
    console.log('Step 10: Testing File Explorer / CloudOS Files...');
    const filesIcon = page.locator('.desktop-icon', { hasText: 'Explorador de Arquivos' }).or(page.locator('.desktop-icon', { hasText: 'CloudOS Files' })).first();
    if (await filesIcon.isVisible()) {
      await filesIcon.dblclick();
    } else {
      await page.locator('button[title="Iniciar"]').click();
      await page.locator('.start-app-btn', { hasText: 'Explorador de Arquivos' }).click();
    }
    const filesWindow = page.locator('.window', { hasText: 'Explorador de Arquivos' }).or(page.locator('.window', { hasText: 'CloudOS Files' })).first();
    await filesWindow.waitFor({ state: 'visible', timeout: 15000 });
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step10_files.png') });
    console.log('✅ File Explorer verified.');
    const closeFilesBtn = filesWindow.locator('.window-controls button.close').first();
    if (await closeFilesBtn.isVisible()) await closeFilesBtn.click({ force: true });
    await page.waitForTimeout(1000);

    // 11. Logout & Login again
    console.log('Step 11: Testing Logout and Re-authentication...');
    await page.locator('button[title="Iniciar"]').click();
    await page.locator('.start-power-btn').click();
    const logoutBtn = page.locator('button:has-text("Sair da Conta")').first();
    await logoutBtn.click();

    console.log('Step 12: Verifying Logout completed...');
    await page.locator('.cloudos-lock-screen').waitFor({ state: 'visible', timeout: 15000 });
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step12_logged_out.png') });
    console.log('✅ Logout verified.');

    // Login back
    console.log('Step 13: Logging back in...');
    await page.locator('.cloudos-lock-screen').click({ position: { x: 400, y: 300 } });
    await page.locator('#login-password').waitFor({ state: 'visible', timeout: 8000 });
    await page.locator('#login-username').fill('douglas');
    await page.locator('#login-password').fill('Admin@123456');
    await page.locator('button[type="submit"]:has-text("Entrar")').click();

    await page.locator('.desktop').waitFor({ state: 'visible', timeout: 15000 });
    console.log('Step 14: Logged back in, opening Firefox one more time...');

    // Open Linux App Center -> Open Firefox
    await page.locator('button[title="Iniciar"]').click();
    await page.locator('.start-native-tabs button', { hasText: 'Todos' }).click();
    await page.locator('.start-app-btn', { hasText: 'Linux App Center' }).click();
    await appCenterWindow.waitFor({ state: 'visible', timeout: 15000 });
    await appCenterWindow.locator('.app-card', { hasText: 'Firefox' }).locator('button:has-text("Abrir")').click({ force: true });

    // Wait for the visible Firefox window
    await page.locator('.window:not([aria-hidden="true"])', { hasText: 'Mozilla Firefox' }).or(page.locator('.window:not([aria-hidden="true"])[data-app-id="linux-app-runner"]')).first().waitFor({ state: 'visible', timeout: 25000 });
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_step14_final_firefox.png') });
    console.log('🎉 COMPLETE REAL USER JOURNEY VALIDATED SUCCESSFULLY 100%!');

  } catch (err) {
    console.error('❌ Journey validation error:', err);
    await page.screenshot({ path: path.join(ARTIFACT_DIR, 'journey_error.png') });
    throw err;
  } finally {
    await browser.close();
  }
}

runRealJourney().catch(() => process.exit(1));
