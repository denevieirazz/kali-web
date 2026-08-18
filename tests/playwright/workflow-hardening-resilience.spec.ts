import { test, expect } from './fixtures/cloudos.fixture';
import { login } from './helpers/cloudos.ui';

test.use({ browserDiagnosticsAssert: false });

async function workspaceRoot(page: import('@playwright/test').Page) {
  let root = page.locator('.workflow-workspace').last();
  if (!await root.isVisible().catch(() => false)) {
    await page.keyboard.press('Control+Alt+1');
    root = page.locator('.workflow-workspace').last();
    await expect(root).toBeVisible({ timeout: 15_000 });
  }
  const win = page.locator('.window:has(.workflow-workspace)').last();
  await win.click({ position: { x: 500, y: 80 } }).catch(() => undefined);
  return root;
}

async function createWorkspace(page: import('@playwright/test').Page, name: string) {
  const root = await workspaceRoot(page);
  let modal = page.locator('.ww-modal:visible').last();
  const alreadyOpen = await modal.isVisible().catch(() => false);
  if (alreadyOpen) {
    const isCreateModal = await modal.getByRole('textbox', { name: 'Nome', exact: true }).isVisible().catch(() => false)
      && await modal.getByRole('button', { name: /Criar workspace/i }).isVisible().catch(() => false);
    if (!isCreateModal) {
      const close = modal.getByRole('button', { name: /Cancelar|Fechar/i }).last();
      if (await close.isVisible().catch(() => false)) await close.click();
      else await page.keyboard.press('Escape');
      await expect(page.locator('.ww-modal:visible')).toHaveCount(0, { timeout: 10_000 });
      await root.getByRole('button', { name: /Novo workspace/i }).click();
      modal = page.locator('.ww-modal:visible').last();
    }
  } else {
    await root.getByRole('button', { name: /Novo workspace/i }).click();
    modal = page.locator('.ww-modal:visible').last();
  }
  await expect(modal).toBeVisible();
  await modal.getByRole('textbox', { name: 'Nome', exact: true }).fill(name);
  await modal.getByRole('textbox', { name: 'Cliente', exact: true }).fill(`Cliente ${name}`);
  await modal.getByRole('textbox', { name: 'Descrição', exact: true }).fill(`Resiliência ${name}`);
  await modal.getByRole('button', { name: /Criar workspace/i }).click();
  await expect(page.locator('.ww-modal:visible')).toHaveCount(0, { timeout: 15_000 });
  await expect(root.locator('.ww-header h2')).toHaveText(name, { timeout: 15_000 });
  return root;
}

async function selectWorkspace(root: import('@playwright/test').Locator, name: string) {
  const item = root.locator('.ww-workspace-list > button', { hasText: name }).first();
  await expect(item).toBeVisible({ timeout: 10_000 });
  await item.click();
  await expect(root.locator('.ww-header h2')).toHaveText(name, { timeout: 10_000 });
}

async function openNotes(root: import('@playwright/test').Locator) {
  await root.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
  await expect(root.locator('.ww-notes')).toBeVisible();
}

async function createNote(root: import('@playwright/test').Locator) {
  await openNotes(root);
  const rows = root.locator('.ww-notes aside > button');
  const before = await rows.count();
  await root.locator('.ww-note-tools button').click();
  await expect(rows).toHaveCount(before + 1, { timeout: 10_000 });
  const editor = root.locator('textarea[aria-label="Nota Markdown"]');
  await expect(editor).toBeVisible();
  return editor;
}

test('Resiliência — fechamento, busca, export, evidence e restore preservam contexto', async ({ page, cloudos }) => {
  await cloudos.createAdmin();
  await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');

  // salvar durante fechamento: fecha a janela enquanto a nota ainda está dirty.
  let root = await createWorkspace(page, 'Resilience A');
  let editor = await createNote(root);
  const closeMarker = 'RESILIENCE-SAVE-CLOSE-2026';
  await editor.fill(closeMarker);
  const workspaceWindow = page.locator('.window:has(.workflow-workspace)').last();
  await workspaceWindow.getByRole('button', { name: /Fechar/i }).first().click();
  await expect(page.locator('.workflow-workspace')).toHaveCount(0, { timeout: 10_000 });
  await page.keyboard.press('Control+Alt+1');
  root = page.locator('.workflow-workspace').last();
  await expect(root).toBeVisible({ timeout: 15_000 });
  await selectWorkspace(root, 'Resilience A');
  await openNotes(root);
  editor = root.locator('textarea[aria-label="Nota Markdown"]');
  await expect(editor).toHaveValue(closeMarker, { timeout: 15_000 });

  // notas durante busca + troca de projeto: a busca não pode perder o documento ativo.
  const searchMarker = 'RESILIENCE-SEARCH-SWITCH-2026';
  await editor.fill(`${closeMarker}\n${searchMarker}`);
  await page.keyboard.press('Control+s');
  const search = root.locator('.ww-note-tools input[placeholder*="Pesquisar"]');
  await search.fill(searchMarker);
  await expect(root.locator('.ww-search-status')).toContainText('nota(s)', { timeout: 15_000 });
  await createWorkspace(page, 'Resilience B');
  await selectWorkspace(root, 'Resilience A');
  await openNotes(root);
  editor = root.locator('textarea[aria-label="Nota Markdown"]');
  await expect(editor).toContainText(searchMarker, { timeout: 15_000 });

  // Evidence durante troca de projeto. A lista exibe metadata (nome/tamanho), não conteúdo.
  await root.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
  const evidenceMarker = 'RESILIENCE-EVIDENCE-SWITCH-2026';
  const evidenceRows = root.locator('.ww-evidence-list > div');
  const evidenceBefore = await evidenceRows.count();
  const evidenceArea = root.locator('.ww-evidence textarea, .workflow-evidence textarea, textarea').last();
  await expect(evidenceArea).toBeVisible();
  await evidenceArea.fill(evidenceMarker);
  const evidenceButton = root.getByRole('button', { name: /salvar|adicionar/i }).last();
  await expect(evidenceButton).toBeVisible();
  await evidenceButton.click();
  await expect(evidenceRows).toHaveCount(evidenceBefore + 1, { timeout: 15_000 });
  const evidenceName = (await evidenceRows.last().locator('strong').textContent())?.trim() || '';
  expect(evidenceName).toMatch(/^note-.*\.md$/);
  await selectWorkspace(root, 'Resilience B');
  await selectWorkspace(root, 'Resilience A');
  await root.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
  await expect(root.locator('.ww-evidence-list strong', { hasText: evidenceName })).toBeVisible({ timeout: 15_000 });

  // Export durante mudança de workspace: o ZIP iniciado em A deve continuar sendo de A.
  await root.locator('.ww-tabs').getByRole('button', { name: 'Visão geral', exact: true }).click();
  const downloadEvent = page.waitForEvent('download', { timeout: 20_000 });
  const exportClick = root.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true }).click();
  await selectWorkspace(root, 'Resilience B');
  await exportClick;
  const download = await downloadEvent;
  expect(download.suggestedFilename().toLowerCase()).toContain('resilience-a');
  await expect(root.locator('.ww-header h2')).toHaveText('Resilience B');

  // Terminal durante restore: só comparar depois do loading terminar.
  await page.keyboard.press('Control+Alt+3');
  let terminal = page.locator('.terminal-workspace').last();
  await expect(terminal).toBeVisible({ timeout: 15_000 });
  await expect(terminal).not.toHaveClass(/terminal-workspace--loading/, { timeout: 15_000 });
  await expect.poll(() => terminal.locator('.terminal-tab').count(), { timeout: 15_000 }).toBeGreaterThan(0);
  const terminalWindow = page.locator('.window:has(.terminal-workspace)').last();
  await terminalWindow.click({ position: { x: 500, y: 80 } });
  await page.keyboard.press('Control+t');
  await page.keyboard.press('Control+t');
  const expectedTabs = await terminal.locator('.terminal-tab').count();
  await terminalWindow.getByRole('button', { name: /Fechar/i }).first().click();
  await expect(terminal).toHaveCount(0, { timeout: 10_000 });
  await page.keyboard.press('Control+Alt+3');
  terminal = page.locator('.terminal-workspace').last();
  await expect(terminal).not.toHaveClass(/terminal-workspace--loading/, { timeout: 15_000 });
  await expect(terminal.locator('.terminal-tab')).toHaveCount(expectedTabs, { timeout: 15_000 });
});
