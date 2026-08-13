import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/playwright',
  outputDir: './test-results/playwright',
  forbidOnly: Boolean(process.env.CI),
  fullyParallel: false,
  workers: 1,
  timeout: 45_000,
  expect: {
    timeout: 8_000,
    toHaveScreenshot: {
      animations: 'disabled',
      maxDiffPixelRatio: 0.003,
      stylePath: './tests/playwright/support/visual-stability.css',
    },
  },
  reporter: [
    ['list'],
    ['html', {
      outputFolder: 'playwright-report',
      open: 'never',
    }],
  ],
  use: {
    ...devices['Desktop Chrome'],
    browserName: 'chromium',
    viewport: {
      width: 1280,
      height: 720,
    },
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    colorScheme: 'dark',
    reducedMotion: 'reduce',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium-windows',
    },
  ],
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFilePath}/{arg}-{projectName}{ext}',
});
