// Run with playwright-cli run-code --filename frontend/tests/viewer-scroll.js.
// Uses synthetic network fixtures; no OCR, OpenAI requests, or saved sessions.
async (page) => {
  const origin = new URL(page.url()).origin;
  const id = "de321a2f-ae49-4b8b-b827-3d213b57435a";
  const region = (id, y, translation) => ({
    id, box: [60, y, 600, 65],
    polygon: [[60, y], [660, y], [660, y + 65], [60, y + 65]],
    source: "原文", raw_text: "原文", translation, confidence: .99,
    background: "#fff", foreground: "#000",
  });
  const session = {
    id, status: "ready", width: 1170, height: 2532,
    created_at: 1, expires_at: 9999999999, error: null,
    original_url: "/viewer-scroll-fixture.svg", annotated_url: null,
    view_url: `/view/${id}`,
    regions: [region("r001", 1200, "Middle translation"), region("r002", 2250, "Bottom translation")],
  };
  await page.route(`${origin}/api/sessions/${id}`, route => route.fulfill({ json: session }));
  await page.route(`${origin}/viewer-scroll-fixture.svg`, route => route.fulfill({
    contentType: "image/svg+xml",
    body: '<svg xmlns="http://www.w3.org/2000/svg" width="1170" height="2532"><rect width="1170" height="2532" fill="white"/></svg>',
  }));
  try {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${origin}/view/${id}`);
    const middle = page.getByRole("button", { name: "Middle translation. Show original and full translation", exact: true });
    await middle.waitFor();
    await page.evaluate(() => {
      window.scrollTo(0, 0);
      if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    });
    // iOS-style tap: the nested text receives a click without focusing the button.
    await middle.locator(".region-text").dispatchEvent("click");
    await page.locator(".detail-island").waitFor();
    await page.waitForTimeout(500);
    const y = await page.evaluate(() => scrollY);
    if (Math.abs(y) > 2) throw new Error(`Tapping visible text jumped from 0 to ${y}px`);
    await page.getByRole("button", { name: "Close translation details", exact: true }).click();
    if (!await middle.evaluate(el => document.activeElement === el))
      throw new Error("Closing details did not restore focus to the tapped region");
    if (Math.abs(await page.evaluate(() => scrollY)) > 2)
      throw new Error("Closing details moved the screenshot");
    await page.evaluate(() => {
      if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    });
    const bottom = page.getByRole("button", { name: "Bottom translation. Show original and full translation", exact: true });
    await bottom.locator(".region-text").dispatchEvent("click");
    await page.locator(".detail-island").waitFor();
    await page.waitForTimeout(500);
    const bounds = await bottom.boundingBox();
    const panel = await page.locator(".detail-island").boundingBox();
    if (!bounds || !panel || bounds.y + bounds.height > panel.y - 12 || bounds.y < 70)
      throw new Error("Covered text was not revealed just above the details island");
  } finally {
    await page.unroute(`${origin}/api/sessions/${id}`);
    await page.unroute(`${origin}/viewer-scroll-fixture.svg`);
  }
}
