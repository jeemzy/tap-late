// Run against Vite after dense-viewer.js. Verifies real shader pixels and HTML interaction.
async (page) => {
  const assert = (value, message) => {
    if (!value) throw new Error(message);
  };
  await page.locator('.viewer-toolbar[data-optics="webgl"]').waitFor();
  const pixels = await page.evaluate(async () => {
    const { GlassRenderer } = await import("/src/lib/glass-renderer.ts");
    const source = document.createElement("canvas");
    source.width = source.height = 256;
    const context = source.getContext("2d");
    const image = context.createImageData(256, 256);
    for (let y = 0; y < 256; y++)
      for (let x = 0; x < 256; x++) {
        const i = (y * 256 + x) * 4;
        image.data.set([y, x, 40, 255], i);
      }
    context.putImageData(image, 0, 0);
    const canvas = document.createElement("canvas");
    const renderer = new GlassRenderer(canvas);
    renderer.setSource(source);
    const frame = {
      bounds: { x: 20, y: 80, width: 180, height: 80 },
      scene: { x: 0, y: 0, width: 256, height: 256 },
      radius: 24,
      dpr: 3,
      pointer: [0.5, 0.2],
      energy: 0,
      background: [0, 0, 0],
      reducedMotion: false,
    };
    const gl = canvas.getContext("webgl");
    const pixel = (x, y) => {
      const value = new Uint8Array(4);
      gl.readPixels(
        x,
        canvas.height - 1 - y,
        1,
        1,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        value,
      );
      return [...value];
    };
    renderer.draw(frame);
    const size = [canvas.width, canvas.height],
      center = pixel(270, 120),
      top = pixel(270, 50),
      bottom = pixel(270, 190),
      corner = pixel(0, 0);
    const edge = pixel(8, 120);
    renderer.draw({ ...frame, pointer: [1, 1], energy: 1 });
    const litEdge = pixel(8, 120);
    renderer.draw({ ...frame, scene: { ...frame.scene, y: 20 } });
    const shifted = pixel(270, 120);
    const error = gl.getError();
    renderer.dispose();
    return { size, center, top, bottom, corner, edge, litEdge, shifted, error };
  });
  assert(pixels.error === 0, "Optical shader reported a WebGL error");
  assert(
    pixels.size[0] === 540 && pixels.size[1] === 240,
    "3× optical backing resolution was not honored",
  );
  assert(
    pixels.corner[3] === 0 && pixels.center[3] === 255,
    "Rounded lens coverage is incorrect",
  );
  assert(
    pixels.bottom[0] > pixels.top[0] + 12,
    `Captured scene is flipped or not sampled: ${JSON.stringify(pixels)}`,
  );
  assert(
    Math.abs(pixels.center[0] - 128) < 10 &&
      Math.abs(pixels.center[1] - 118) < 10,
    `Glass replaced local colors with a material tint: ${pixels.center}`,
  );
  assert(
    pixels.shifted[0] < pixels.center[0] - 12,
    "Lens sampling did not follow scene movement",
  );
  assert(
    pixels.edge.some((v, i) => i < 3 && Math.abs(v - pixels.litEdge[i]) > 2),
    "Pointer light/refraction did not respond",
  );

  const resolution = await page.locator(".viewer-toolbar").evaluate((el) => {
    const canvas = el.querySelector("canvas"),
      bounds = el.getBoundingClientRect();
    return canvas.width / bounds.width;
  });
  assert(resolution >= 1.99, "Live glass is below 2× resolution");
  await page
    .getByRole("button", { name: "Close translation details", exact: true })
    .click();
  await page
    .getByRole("button", {
      name: "Travel coffee cup. Show original and full translation",
      exact: true,
    })
    .click();
  await page.locator('.detail-island[data-optics="webgl"]').waitFor();
  assert(
    (await page.locator(".detail-translation p").textContent()) ===
      "Travel coffee cup",
    "Translation tap did not update the island",
  );
  await page.emulateMedia({ reducedMotion: "reduce", contrast: "more" });
  await page.locator('.viewer-toolbar[data-optics="opaque"]').waitFor();
  const opaque = await page
    .locator(".viewer-toolbar")
    .evaluate((el) => getComputedStyle(el).backgroundColor);
  assert(
    opaque === "rgb(247, 247, 250)" || opaque === "rgb(36, 36, 40)",
    "High contrast did not get an opaque material",
  );
  await page.emulateMedia({
    reducedMotion: "reduce",
    contrast: "no-preference",
  });
  await page.locator('.viewer-toolbar[data-optics="webgl"]').waitFor();
  await page
    .locator(".viewer-toolbar")
    .dispatchEvent("pointerdown", { clientX: 50, clientY: 30 });
  await page.waitForTimeout(100);
  assert(
    (await page
      .locator(".viewer-toolbar")
      .evaluate((el) =>
        Number(el.style.getPropertyValue("--glass-energy")),
      )) === 0,
    "Reduced motion still animates optical deformation",
  );
  await page.locator(".viewer-toolbar").dispatchEvent("pointerup");
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.screenshot({
    path: "output/playwright/glass-checked.png",
    scale: "css",
  });
  return {
    shader: pixels,
    liveResolution: resolution,
    interaction: "passed",
    accessibility: "passed",
  };
}
