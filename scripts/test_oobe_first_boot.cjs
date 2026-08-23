const { chromium } = require('playwright');
const path = require('path');

async function main() {
  console.log('Iniciando teste de First Boot OOBE...');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  // Garante que o estado inicial é de primeiro boot (limpando localStorage)
  await page.goto('http://127.0.0.1:55931');
  await page.evaluate(() => {
    localStorage.removeItem('cloudos-oobe-completed');
    localStorage.removeItem('obsidianos-setup-completed');
  });

  // Recarrega para simular primeiro boot
  await page.reload();

  console.log('Aguardando boot sequence e tela OOBE...');
  await page.waitForSelector('.setup-wizard', { timeout: 15000 });
  console.log('✓ SUCESSO: Tela OOBE (.setup-wizard) detectada no First Boot!');

  await page.waitForTimeout(1000);

  const screenshotPath = path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_first_boot_screen.png');
  await page.screenshot({ path: screenshotPath });
  console.log('✓ Screenshot 1 salvo em:', screenshotPath);

  // Clica em "Começar →" para ir para a Tela 2 (Escolha seu Sistema Base)
  const btnComecar = page.locator('text=Começar →');
  await btnComecar.click();
  await page.waitForTimeout(1000);

  const screenshotPathTela2 = path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_tela2_distro_select.png');
  await page.screenshot({ path: screenshotPathTela2 });
  console.log('✓ Screenshot 2 (Tela 2) salvo em:', screenshotPathTela2);

  await browser.close();
  console.log('Teste OOBE concluído com 100% de sucesso!');
}

main().catch(err => {
  console.error('Erro no teste OOBE:', err);
  process.exit(1);
});
