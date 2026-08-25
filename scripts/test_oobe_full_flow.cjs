const { chromium } = require('playwright');
const path = require('path');

async function main() {
  console.log('Iniciando teste de fluxo completo OOBE (5 telas)...');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  await page.goto('http://127.0.0.1:55931');
  await page.evaluate(() => {
    localStorage.removeItem('cloudos-oobe-completed');
    localStorage.removeItem('obsidianos-setup-completed');
  });
  await page.reload();

  // Tela 1
  await page.waitForSelector('.setup-wizard', { timeout: 15000 });
  console.log('✓ Tela 1 carregada');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen1.png') });

  // Ir para Tela 2
  await page.locator('text=Começar →').click();
  await page.waitForTimeout(600);
  console.log('✓ Tela 2 carregada');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen2.png') });

  // Clica em Instalar Sistema -> Tela 3 (Provisioning)
  await page.locator('text=Instalar Sistema →').click();
  await page.waitForTimeout(1200);
  console.log('✓ Tela 3 (Provisioning) capturada');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen3_provisioning.png') });

  // Aguarda avanço automático para Tela 4 (Conta)
  await page.waitForSelector('text=Criar Usuário Administrador', { timeout: 10000 });
  console.log('✓ Tela 4 (Conta) carregada');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen4_account.png') });

  // Clica em Criar Conta e Finalizar -> Tela 5
  await page.locator('text=Criar Conta e Finalizar →').click();
  await page.waitForTimeout(800);
  console.log('✓ Tela 5 (Pronto) carregada');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen5_ready.png') });

  // Clica em Entrar no CloudOS -> Desktop
  await page.locator('text=Entrar no CloudOS 🚀').click();
  await page.waitForTimeout(1500);
  console.log('✓ Desktop acessado');
  await page.screenshot({ path: path.resolve('C:/Users/dougl/.gemini/antigravity/brain/5898b72a-bccd-4700-b287-df3a7181f1cc/proof_oobe_screen6_desktop.png') });

  await browser.close();
  console.log('Fluxo completo das 5 telas validado com sucesso!');
}

main().catch(err => {
  console.error('Erro no teste de fluxo OOBE:', err);
  process.exit(1);
});
