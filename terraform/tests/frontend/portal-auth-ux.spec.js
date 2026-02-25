const { test, expect } = require('@playwright/test');

const PORTAL_URL = '/examples/5-integrated/frontend/index.html';

async function openPortal(page) {
  await page.goto(PORTAL_URL);
  await expect(page.locator('h1')).toContainText('AgentCore Tenant Operations Portal');
  await expect(page.getByRole('button', { name: 'Diagnostics' })).toBeVisible();
}

test.describe('Tenant Portal Auth UX', () => {
  test('shows explicit session-expiry UX and retry affordance for portal requests', async ({ page }) => {
    let diagnosticsCalls = 0;
    await page.route('**/api/tenancy/v1/admin/tenants/**/diagnostics', async (route) => {
      diagnosticsCalls += 1;
      if (diagnosticsCalls === 1) {
        await route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Session expired while refreshing token for tenant admin route (internal detail should not be shown)',
          }),
        });
        return;
      }

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          health: 'HEALTHY',
          generatedAt: '2026-02-25T12:00:00Z',
          policyVersion: 'v7',
          appId: 'portal-prod',
          lastDeploymentSha: '1234567890abcdef',
          memoryUsage: { usedBytes: 2048, summary: '2 KB used' },
        }),
      });
    });

    await openPortal(page);
    await page.getByRole('button', { name: 'Diagnostics' }).click();

    await expect(page.getByText('Session Expired')).toBeVisible();
    await expect(page.getByText(/sign in again, then retry/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /^Retry Diagnostics / })).toBeVisible();
    await expect(
      page.getByText('Authentication required: your portal session expired or is invalid. Sign in again and retry.'),
    ).toBeVisible();
    await expect(page.getByText('internal detail should not be shown')).toHaveCount(0);

    await page.getByRole('button', { name: /^Retry Diagnostics / }).click();

    await expect(page.getByText('Session Expired')).toHaveCount(0);
    await expect(page.getByText('HEALTHY')).toBeVisible();
    await expect.poll(() => diagnosticsCalls).toBe(2);
  });

  test('shows scope-mismatch messaging without leaking backend isolation error text', async ({ page }) => {
    await page.route('**/api/tenancy/v1/admin/tenants/**/diagnostics', async (route) => {
      await route.fulfill({
        status: 403,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Tenant isolation violation: path tenant does not match authenticated tenant',
        }),
      });
    });

    await openPortal(page);
    await page.getByRole('button', { name: 'Diagnostics' }).click();

    await expect(page.getByText('Tenant/App Scope Mismatch')).toBeVisible();
    await expect(
      page.getByText('Access denied: selected tenant/app scope does not match the authenticated session.'),
    ).toBeVisible();
    await expect(page.getByText('Tenant isolation violation: path tenant does not match authenticated tenant')).toHaveCount(0);
    await expect(page.getByRole('button', { name: /^Retry Diagnostics / })).toBeVisible();
  });

  test('distinguishes non-auth API failures from auth failures with sanitized messaging', async ({ page }) => {
    await page.route('**/api/tenancy/v1/admin/tenants/**/diagnostics', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Unhandled exception stack trace should not be rendered in the portal',
        }),
      });
    });

    await openPortal(page);
    await page.getByRole('button', { name: 'Diagnostics' }).click();

    await expect(page.getByText('Session Expired')).toHaveCount(0);
    await expect(page.getByText('Tenant/App Scope Mismatch')).toHaveCount(0);
    await expect(page.getByText(/Diagnostics acme-finance request failed \(HTTP 500\)\./)).toBeVisible();
    await expect(page.getByText('Unhandled exception stack trace should not be rendered in the portal')).toHaveCount(0);
  });

  test('restores the chat prompt after auth failure and shows scope-mismatch chat messaging', async ({ page }) => {
    await page.route('**/api/chat', async (route) => {
      await route.fulfill({
        status: 403,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Session isolation violation: tenant mismatch',
        }),
      });
    });

    await openPortal(page);
    await page.getByLabel('Prompt').fill('Run tenant diagnostics and summarize anomalies');
    await page.getByRole('button', { name: 'Send' }).click();

    await expect(
      page.getByText('Access denied: tenant/app scope mismatch. Sign in with the correct role or tenant context, then retry.'),
    ).toBeVisible();
    await expect(page.getByText('Session isolation violation: tenant mismatch')).toHaveCount(0);
    await expect(page.getByText('Tenant/App Scope Mismatch')).toBeVisible();
    await page.getByRole('button', { name: 'Restore Prompt' }).click();
    await expect(page.getByLabel('Prompt')).toHaveValue('Run tenant diagnostics and summarize anomalies');
  });
});
