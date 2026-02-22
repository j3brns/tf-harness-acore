const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

test.describe('Accessibility Regression Tests', () => {
  test('component preview page should have no automatically detectable accessibility violations', async ({ page }) => {
    await page.goto('/preview.html');

    // Wait for the React app to hydrate and render.
    // We check for the presence of the AppShell title.
    await expect(page.locator('h1')).toContainText('Component Preview Console');

    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
      .analyze();

    expect(accessibilityScanResults.violations).toEqual([]);
  });
});
