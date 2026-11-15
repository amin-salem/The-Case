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
      const bar = page.locator('#tabbar'), more = page.locator('#more'), sheet = page.locator('#moresheet'), moreBtn = bar.locator('[data-more]');
      assert.equal(await bar.isVisible(), true);
      assert.equal(await more.isVisible(), false);
      assert.equal(await bar.locator('button[data-k]').count() + await sheet.locator('button').count(), 11, 'every section is reachable');
      const bb = await bar.boundingBox();
      assert.ok(bb.x >= -1 && bb.x + bb.width <= width + 1, 'tab bar must stay within screen width');
      assert.ok(bb.y + bb.height <= height + 1, 'tab bar must end inside the screen');
      await moreBtn.click();
      assert.equal(await more.isVisible(), true);
      const box = await sheet.boundingBox();
      assert.ok(box.x >= -1 && box.x + box.width <= width + 1, 'sheet must stay within screen width');
      assert.ok(box.y >= -1 && box.y + box.height <= height + 1, 'sheet must stay inside the screen (it scrolls)');
      await sheet.locator('[data-k="funnel"]').click();
      await page.waitForSelector('#fbody h2');
      assert.ok(requests.includes('/admin/api/funnel'), 'real funnel navigation must request its data');
      assert.equal(await more.isVisible(), false);
      assert.equal(await moreBtn.getAttribute('class'), 'on', 'a section inside «بیشتر» lights the more button');
      await moreBtn.click();
      assert.equal(await sheet.locator('[data-k="funnel"]').getAttribute('class'), 'on');
      await page.keyboard.press('Escape');
      assert.equal(await more.isVisible(), false);
      await moreBtn.click();
      await page.mouse.click(Math.floor(width / 2), 2);
      assert.equal(await more.isVisible(), false, 'tapping outside closes the sheet');
      await moreBtn.click();
      await sheet.locator('[data-k="actions"]').click();
      await page.waitForSelector('#bc');
      assert.equal(await more.isVisible(), false);
      await moreBtn.click();
      await sheet.locator('[data-k="funnel"]').click();
      await page.waitForSelector('#fbody h2');
      await page.reload();
      await page.waitForSelector('#fbody h2');
      assert.equal(await more.isVisible(), false, 'reload preserves section but closes the sheet');
      await page.locator('#logout').click();
      assert.equal(await page.locator('#app').isVisible(), false);
      assert.equal(await page.locator('#login').isVisible(), true);
      assert.deepEqual(errors, []);
      console.log(`admin menu: ${width}x${height}, large text=${largeText}: passed`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
