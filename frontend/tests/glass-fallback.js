// Run after dense-viewer.js against either Vite or the production container.
async (page) => {
  const toolbar = page.locator(".viewer-toolbar");
  await toolbar.locator("canvas").waitFor();
  const supported = await toolbar.evaluate((el) => {
    const extension = el
      .querySelector("canvas")
      .getContext("webgl")
      ?.getExtension("WEBGL_lose_context");
    if (!extension) return false;
    window.__glassContextTest = extension;
    extension.loseContext();
    return true;
  });
  if (!supported)
    throw new Error("Browser cannot exercise WebGL context-loss recovery");
  let restored = false;
  try {
    await page.locator('.viewer-toolbar[data-optics="fallback"]').waitFor();
    await page.evaluate(() => window.dispatchEvent(new Event("scroll")));
    await page.waitForTimeout(100);
    if ((await toolbar.getAttribute("data-optics")) !== "fallback")
      throw new Error("Lost GPU context exposed an empty canvas");
    const material = await toolbar.evaluate(
      (el) => getComputedStyle(el).backgroundColor,
    );
    if (material === "rgba(0, 0, 0, 0)")
      throw new Error("Fallback is transparent");
    await page.evaluate(() => window.__glassContextTest.restoreContext());
    await page.locator('.viewer-toolbar[data-optics="webgl"]').waitFor();
    restored = true;
    const resolution = await toolbar.evaluate(
      (el) =>
        el.querySelector("canvas").width / el.getBoundingClientRect().width,
    );
    if (resolution < 1.99)
      throw new Error("Context recovery lost optical resolution");
    return "GPU loss, readable fallback and full-resolution recovery passed";
  } finally {
    if (!restored)
      await page.evaluate(() => window.__glassContextTest?.restoreContext());
    await page.evaluate(() => {
      delete window.__glassContextTest;
    });
  }
}
