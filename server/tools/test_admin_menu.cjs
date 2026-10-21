// Exercise the actual panel in Chromium with synthetic responses; no live admin access.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({headless: true});
  try {
    const html = fs.readFileSync(path.join(__dirname, '../app/admin_page.html'), 'utf8');
    for (const [width, height, largeText] of [[320, 640, false], [360, 640, false], [1280, 800, false], [320, 480, true]]) {
      const context = await browser.newContext({viewport: {width, height}, isMobile: width < 700, hasTouch: width < 700});
      const page = await context.newPage();
      const errors = [], requests = [];
      page.on('pageerror', e => errors.push(e.message));
      await page.route('http://admin-menu.test/**', async route => {
        const url = new URL(route.request().url());
        if (url.pathname === '/admin/ui') return route.fulfill({contentType: 'text/html', body: html});
        if (url.pathname.startsWith('/static/')) return route.fulfill({status: 204});
        requests.push(url.pathname);
        const payload = url.pathname.endsWith('/funnel') ? {
          generated_at: 1, days: 30,
          ...Object.fromEntries(['signups', 'funnel', 'retention', 'drop_off', 'money', 'quality'].map(k => [k, {error: 'fixture'}])),
        } : url.pathname.endsWith('/log') ? [] : {
          days: [{day: '2026-10-20', new: 0, active: 0, opened: 0, solved: 0, failed: 0,
            purchases: 0, coins_in: 0, coins_out: 0, stars: 0}], totals: {},
        };
        return route.fulfill({contentType: 'application/json', body: JSON.stringify(payload)});
      });
      await page.goto('http://admin-menu.test/admin/ui#k=synthetic-ui-test');
      await page.waitForFunction(() => !document.querySelector('#app').hidden);
      if (largeText) await page.evaluate(() => { document.body.style.fontSize = '200%'; });
      const toggle = page.locator('#menu-toggle'), nav = page.locator('#nav');
      assert.equal(await nav.isVisible(), false);
      await toggle.click();
      assert.equal(await nav.isVisible(), true);
      assert.equal(await nav.locator('button').count(), 10);
      const box = await nav.boundingBox();
      assert.ok(box.x >= -1 && box.x + box.width <= width + 1, 'menu must stay within screen width');
      assert.ok(box.height <= height * .71, 'short screens must get a scrollable menu');
      assert.ok(box.y + box.height <= height, 'menu must end inside the screen, even below a wrapped header');
      await nav.locator('[data-k="funnel"]').click();
      await page.waitForSelector('#fbody h2');
      assert.ok(requests.includes('/admin/api/funnel'), 'real funnel navigation must request its data');
      assert.equal(await nav.isVisible(), false);
      assert.equal(await page.locator('#menu-toggle:focus').count(), 1);
      await toggle.click();
      assert.equal(await nav.locator('[data-k="funnel"]').getAttribute('aria-current'), 'page');
      await page.keyboard.press('Escape');
      assert.equal(await nav.isVisible(), false);
      await toggle.click();
      await page.locator('header h1').click();
      assert.equal(await nav.isVisible(), false, 'outside click closes menu');
      await toggle.focus();
      await page.keyboard.press('Enter');
      assert.equal(await nav.isVisible(), true, 'keyboard opens native disclosure');
      await nav.locator('[data-k="actions"]').click();
      await page.waitForSelector('#bc');
      assert.equal(await nav.isVisible(), false, 'last item is reachable by scrolling');
      await toggle.click();
      await nav.locator('[data-k="funnel"]').click();
      await page.waitForSelector('#fbody h2');
      await page.reload();
      await page.waitForSelector('#fbody h2');
      assert.equal(await nav.isVisible(), false, 'reload preserves section but closes menu');
      await toggle.click();
      assert.equal(await nav.locator('[data-k="funnel"]').getAttribute('aria-current'), 'page');
      await page.locator('#logout').click();
      assert.equal(await page.locator('#app').isVisible(), false);
      assert.equal(await page.locator('#login').isVisible(), true);
      assert.deepEqual(errors, []);
      console.log(`admin menu: ${width}x${height}, large text=${largeText}: passed`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
