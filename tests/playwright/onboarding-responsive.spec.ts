import { test, expect } from './fixtures/cloudos.fixture';
import { waitForOobe } from './helpers/cloudos.ui';

type Geometry = { x: number; width: number; scrollWidth: number; clientWidth: number };

async function accountStep(page: Parameters<typeof waitForOobe>[0], baseURL: string) {
  await waitForOobe(page, baseURL);
  const welcomeBtn = page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Começar' }).or(page.locator('.setup-footer button.setup-btn-primary', { hasText: 'Continuar' })).first();
  if (await welcomeBtn.isVisible()) {
    await welcomeBtn.click();
    const distroBtn = page.locator('.setup-footer button.setup-btn-primary').first();
    await distroBtn.click();
    await expect(page.locator('.setup-form')).toBeVisible({ timeout: 25_000 });
  }
}

async function geometry(page: Parameters<typeof waitForOobe>[0]): Promise<Geometry> {
  return page.evaluate(() => {
    const container = document.querySelector('.setup-container') as HTMLElement | null;
    const wizard = document.querySelector('.setup-wizard') as HTMLElement | null;
    if (!container || !wizard) throw new Error('OOBE geometry unavailable');
    const rect = container.getBoundingClientRect();
    return { x: rect.x, width: rect.width, scrollWidth: wizard.scrollWidth, clientWidth: wizard.clientWidth };
  });
}

async function expectNoHorizontalOverflow(page: Parameters<typeof waitForOobe>[0]) {
  const state = await page.evaluate(() => {
    const wizard = document.querySelector('.setup-wizard') as HTMLElement;
    const fields = [...document.querySelectorAll('.setup-input')] as HTMLElement[];
    const viewport = window.innerWidth;
    return {
      scrollWidth: wizard.scrollWidth,
      clientWidth: wizard.clientWidth,
      fields: fields.map(field => {
        const rect = field.getBoundingClientRect();
        return { left: rect.left, right: rect.right, width: rect.width };
      }),
      viewport,
    };
  });
  expect(state.scrollWidth).toBeLessThanOrEqual(state.clientWidth + 1);
  for (const field of state.fields) {
    expect(field.width).toBeGreaterThan(0);
    expect(field.left).toBeGreaterThanOrEqual(-1);
    expect(field.right).toBeLessThanOrEqual(state.viewport + 1);
  }
}

test.describe('Onboarding responsive geometry', () => {
  test('Tab never changes form geometry and 1366x768 remains unclipped', async ({ page, cloudos }) => {
    await page.setViewportSize({ width: 1366, height: 768 });
    await accountStep(page, cloudos.baseURL);
    const before = await geometry(page);
    await expectNoHorizontalOverflow(page);

    const inputBoxes = await page.locator('.setup-input').evaluateAll(elements => elements.map(element => {
      const rect = (element as HTMLElement).getBoundingClientRect();
      return { x: rect.x, width: rect.width };
    }));

    await page.locator('.setup-input').first().focus();
    for (let step = 0; step < 8; step += 1) {
      await page.keyboard.press('Tab');
      const after = await geometry(page);
      expect(Math.abs(after.x - before.x)).toBeLessThanOrEqual(0.5);
      expect(Math.abs(after.width - before.width)).toBeLessThanOrEqual(0.5);
      expect(after.scrollWidth).toBeLessThanOrEqual(after.clientWidth + 1);
    }

    const afterInputBoxes = await page.locator('.setup-input').evaluateAll(elements => elements.map(element => {
      const rect = (element as HTMLElement).getBoundingClientRect();
      return { x: rect.x, width: rect.width };
    }));
    expect(afterInputBoxes).toEqual(inputBoxes);

    const passwords = page.locator('.setup-password-grid .setup-input');
    const first = await passwords.nth(0).boundingBox();
    const second = await passwords.nth(1).boundingBox();
    expect(first).not.toBeNull();
    expect(second).not.toBeNull();
    expect(Math.abs((first?.width || 0) - (second?.width || 0))).toBeLessThanOrEqual(1);
    expect(Math.abs((first?.y || 0) - (second?.y || 0))).toBeLessThanOrEqual(1);
  });

  for (const zoom of [1, 1.25, 1.5]) {
    test(`layout remains contained at ${Math.round(zoom * 100)}% scale`, async ({ page, cloudos }) => {
      await page.setViewportSize({ width: 1366, height: 768 });
      await accountStep(page, cloudos.baseURL);
      await page.evaluate(value => { document.documentElement.style.zoom = String(value); }, zoom);
      await expectNoHorizontalOverflow(page);
      await expect(page.getByLabel('Senha', { exact: true })).toBeVisible();
      await expect(page.getByLabel('Confirmar senha', { exact: true })).toBeVisible();
    });
  }

  test('narrow window switches password fields to one column without clipping', async ({ page, cloudos }) => {
    await page.setViewportSize({ width: 500, height: 700 });
    await accountStep(page, cloudos.baseURL);
    await expectNoHorizontalOverflow(page);
    const passwords = page.locator('.setup-password-grid .setup-input');
    const first = await passwords.nth(0).boundingBox();
    const second = await passwords.nth(1).boundingBox();
    expect(first).not.toBeNull();
    expect(second).not.toBeNull();
    expect(Math.abs((first?.width || 0) - (second?.width || 0))).toBeLessThanOrEqual(1);
    expect((second?.y || 0)).toBeGreaterThan((first?.y || 0) + (first?.height || 0) - 1);
  });
});
