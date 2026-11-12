// playwright-cli run-code --filename frontend/tests/currency.js
// Synthetic responses only: no uploads, OCR, paid translations, or production edits.
async (page) => {
  const origin = new URL(page.url()).origin;
  const id = "cbee78c8-0ddc-4b3b-987d-a7dcc7c1aca3";
  const base = `${origin}/api/sessions/${id}`;
  const amount = (id, text, value, detected_currency = null) => ({ id, text, value, detected_currency, source_currency: null });
  const region = (id, y, text, amounts) => ({
    id, box: [100, y, 550, 70], polygon: [[100,y],[650,y],[650,y+70],[100,y+70]],
    source: text, raw_text: text, translation: text, confidence: .99,
    background: "#fff", foreground: "#111", amounts,
  });
  const regions = [region("r001", 1350, "¥128.00", [amount("a1", "¥128.00", "128.00", "CNY")]),
    region("r002", 900, "128.00 / 0", [amount("a2", "128.00", "128.00"), amount("a3", "0", "0")]),
    region("r003", 500, "普通文字", []),
    { ...region("r004", 650, "42", [amount("a4", "42", "42")]), translation: null }];
  const session = { id, status: "ready", width: 1170, height: 2532, created_at: 1, expires_at: 9999999999,
    error: null, original_url: "/currency-fixture.svg", annotated_url: null, view_url: `/view/${id}`, regions };
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  let failRates = false, failSave = false, delay = 0, conversions = 0, saves = 0;
  let holdSave = false, releaseSave = () => {};
  const errors = [];
  const onError = e => errors.push(e.message);
  page.on("pageerror", onError);
  await page.route(`${base}/**`, async route => {
    const path = new URL(route.request().url()).pathname;
    const a = regions.flatMap(r => r.amounts).find(a => path.includes(`/amounts/${a.id}/`));
    if (!a) throw new Error(`Unexpected API route: ${path}`);
    if (path.endsWith("/currency")) {
      saves++;
      if (failSave) return route.fulfill({ status: 503, json: { detail: "Could not save currency. Retry." } });
      a.source_currency = route.request().postDataJSON().currency;
      const saved = { ...a };
      if (holdSave) {
        holdSave = false;
        await new Promise(resolve => { releaseSave = resolve; });
      }
      return route.fulfill({ json: saved });
    }
    conversions++;
    const source = a.source_currency || a.detected_currency;
    const values = { CNY: a.value === "0" ? "0.00" : "128.00", PLN: "64.00", USD: "17.60", EUR: "16.00" };
    if (delay) await new Promise(resolve => setTimeout(resolve, delay));
    if (failRates) return route.fulfill({ status: 503, json: { detail: "Reference rates are unavailable. Retry in a moment." } });
    return route.fulfill({ json: { amount_id: a.id, source_currency: source, rate_date: "2026-11-12", values } });
  });
  await page.route(base, route => route.fulfill({ json: session }));
  await page.route(`${origin}/currency-fixture.svg`, route => route.fulfill({ contentType: "image/svg+xml", body:
    '<svg xmlns="http://www.w3.org/2000/svg" width="1170" height="2532"><rect width="1170" height="2532" fill="#f5f5f7"/><rect x="90" y="230" width="990" height="510" rx="50" fill="#c8ccd2"/><text x="100" y="830" font-size="70" font-family="sans-serif">Wireless headphones</text><text x="100" y="1420" font-size="70">¥128.00</text></svg>' }));
  const button = name => page.getByRole("button", { name, exact: true });
  const tap = async index => {
    await page.locator(".region").nth(index).dispatchEvent("click");
    await page.locator(".detail-island").waitFor();
    await page.waitForTimeout(300);
  };
  const screenshot = async name => {
    const size = page.viewportSize();
    const browser = page.context().browser()?.browserType().name() || "browser";
    await page.screenshot({ path: `output/playwright/currency-${browser}-${size.width}-${name}.png` });
  };
  try {
    for (const size of [{ width: 390, height: 844 }, { width: 1440, height: 1000 }]) {
      for (const a of regions.flatMap(r => r.amounts)) a.source_currency = null;
      await page.setViewportSize(size);
      await page.goto(`${origin}/view/${id}`);
      await page.locator(".region").first().waitFor();
      await tap(0);
      await button("Convert price").waitFor();
      await screenshot("marked");
      check(conversions === 0 || size.width === 1440, "Conversion must be explicit");
      await button("Convert price").click();
      await page.locator(".conversion-grid").waitFor();
      check(await page.locator(".conversion-grid > div").count() === 4, "Four result currencies required");
      check(await page.locator(".rate-note").textContent() === "Approx. · 2026-11-12", "Dated approximate rates required");
      const bounds = await page.locator(".region").first().boundingBox();
      const panel = await page.locator(".detail-island").boundingBox();
      check(bounds.y + bounds.height < panel.y - 12, "Async panel growth must reveal selected amount");
      check(panel.height <= size.height * .36 + 1, "Island height must stay bounded");
      const actions = await page.locator(".conversion-actions").boundingBox();
      check(actions.y + actions.height <= panel.y + panel.height - 12, "Single-amount results must show both actions without scrolling");
      await screenshot("results");
      await button("Change currency").click();
      await page.getByRole("radio", { name: "PLN · Złoty" }).check();
      await screenshot("edit");
      await page.keyboard.press("Escape");
      check(await page.locator(".conversion-grid").isVisible(), "Escape must cancel picker without closing island");
      check(regions[0].amounts[0].source_currency === "CNY", "Draft cannot change saved currency");
      await button("Change currency").click();
      await page.getByRole("radio", { name: "PLN · Złoty" }).check();
      await button("Save & update").click();
      await page.locator(".conversion-grid").waitFor();
      await button("Hide conversion").click();
      await button("Convert from PLN").waitFor();
      const scroll = await page.evaluate(() => scrollY);
      await button("Close translation details").click();
      check(Math.abs(await page.evaluate(() => scrollY) - scroll) < 2, "Close must preserve scroll position");
      check(await page.locator(".region").first().evaluate(el => document.activeElement === el), "Close restores focus");
      await tap(0);
      await button("Convert from PLN").waitFor();
      check(await page.locator(".conversion-grid").count() === 0, "Reopening must not automatically convert");
      await screenshot("reopen");
      await tap(1);
      await button("Convert amount").click();
      check(await page.getByRole("radio").count() === 4, "Exactly four source choices required");
      check(await page.locator("input:checked").count() === 0, "First unmarked picker has no default");
      check(await button("Confirm & convert").isDisabled(), "Confirmation disabled without choice");
      await screenshot("picker");
      await button("Cancel").click();
      check(regions[1].amounts[0].source_currency === null, "Cancel cannot save");
      await button("Convert amount").click();
      await page.getByRole("radio", { name: "USD · Dollar" }).check();
      failSave = true;
      await button("Confirm & convert").click();
      await page.getByRole("alert").filter({ hasText: "Could not save" }).waitFor();
      check(await page.getByRole("radio", { name: "USD · Dollar" }).isChecked(), "Failed save retains draft");
      failSave = false;
      await button("Confirm & convert").click();
      await page.locator(".conversion-grid").waitFor();
      await button("Amount 2: 0").click();
      await button("Convert amount").click();
      check(await page.locator("input:checked").count() === 0, "Amounts have independent choices");
      await page.getByRole("radio", { name: "EUR · Euro" }).check();
      failRates = true;
      await button("Confirm & convert").click();
      await button("Retry").waitFor();
      check(regions[1].amounts[1].source_currency === "EUR", "Save persists despite rate failure");
      check(await page.locator(".amount-original").isVisible(), "Original survives rate failure");
      await screenshot("error");
      failRates = false;
      await button("Retry").click();
      await page.locator(".conversion-grid").waitFor();
      await button("Amount 1: 128.00").click();
      await button("Convert from USD").waitFor();
      delay = 650;
      await button("Convert from USD").click();
      await button("Converting…").waitFor();
      await button("Amount 2: 0").click();
      await page.waitForTimeout(800);
      check(await page.locator(".conversion-grid").count() === 0, "Old amount response must be ignored");
      await button("Convert from EUR").waitFor();
      delay = 0;
      await page.reload();
      await page.locator(".region").first().waitFor();
      await tap(1);
      await button("Convert from USD").waitFor();
      await button("Amount 2: 0").click();
      await button("Convert from EUR").waitFor();
      await tap(2);
      check(await page.locator(".detail-source").isVisible(), "Ordinary details unaffected");
      check(await page.locator(".currency-details").count() === 0, "Text has no conversion UI");
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "No horizontal page overflow");
      await page.emulateMedia({ reducedMotion: "reduce" });
      await tap(0);
      check(await page.locator(".detail-island").evaluate(el => getComputedStyle(el).animationName) === "none", "Reduced motion respected");
      await page.emulateMedia({ reducedMotion: "no-preference" });
      // A delayed save response from an unmounted amount cannot replace a newer save.
      regions[1].amounts[0].source_currency = null;
      await page.reload();
      await page.locator(".region").first().waitFor();
      await tap(1);
      await button("Convert amount").click();
      await page.getByRole("radio", { name: "CNY · Yuan" }).check();
      holdSave = true;
      await button("Confirm & convert").click();
      await button("Amount 2: 0").click();
      await button("Amount 1: 128.00").click();
      await button("Convert amount").click();
      await page.getByRole("radio", { name: "PLN · Złoty" }).check();
      await button("Confirm & convert").click();
      await page.locator(".conversion-grid").waitFor();
      releaseSave();
      await page.waitForTimeout(250);
      await button("Hide conversion").click();
      await button("Convert from PLN").waitFor({ timeout: 1500 });
      for (const status of ["ready", "failed"]) {
        session.status = status;
        await page.reload();
        await page.locator(".region").first().waitFor();
        await tap(3);
        await page.getByText("This text could not be translated reliably.", { exact: true }).waitFor({ timeout: 1500 });
      }
      session.status = "ready";
    }
    check(errors.length === 0, `Browser errors: ${errors.join("; ")}`);
    return { passed: true, sizes: [390, 1440], saves, conversions };
  } finally {
    releaseSave();
    page.off("pageerror", onError);
    await page.unroute(`${base}/**`);
    await page.unroute(base);
    await page.unroute(`${origin}/currency-fixture.svg`);
  }
}
