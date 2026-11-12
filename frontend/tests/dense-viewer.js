// A synthetic, dense storefront in the real viewer. No OCR/API spending or saved data.
// Leaves the page open for interactive material inspection.
async (page) => {
  const origin = new URL(page.url()).origin;
  const id = "8d6b2cf4-6957-41a4-9314-2b7ec9f69d40";
  const regions = [];
  const text = (
    x,
    y,
    w,
    h,
    source,
    translation,
    background = "#ffffff",
    foreground = "#171719",
  ) => {
    const id = `r${String(regions.length + 1).padStart(3, "0")}`;
    regions.push({
      id,
      box: [x, y, w, h],
      polygon: [
        [x, y],
        [x + w, y],
        [x + w, y + h],
        [x, y + h],
      ],
      source,
      raw_text: source,
      translation,
      confidence: 0.99,
      background,
      foreground,
    });
    return `<text x="${x}" y="${y + h * 0.78}" fill="${foreground}" font-size="${h * 0.72}" font-family="Arial,sans-serif">${source}</text>`;
  };
  const colors = [
    "#d7ebff",
    "#ffe3d8",
    "#e5dcff",
    "#d9f1de",
    "#ffebc2",
    "#ffdce9",
  ];
  let svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1170" height="3000"><defs><pattern id="lines" width="24" height="24" patternUnits="userSpaceOnUse"><path d="M0 0V24M12 0V24" stroke="#ffffff" stroke-width="3" opacity=".55"/></pattern></defs><rect width="1170" height="3000" fill="#f2f2f7"/><rect width="1170" height="190" fill="#0a65ed"/>';
  svg += text(
    48,
    80,
    650,
    62,
    "发现好物 · 每日上新",
    "Discover · New arrivals",
    "#0a65ed",
    "#ffffff",
  );
  svg += text(48, 205, 620, 48, "精选推荐", "Selected for you", "#f2f2f7");
  svg +=
    '<text x="775" y="244" fill="#63636b" font-size="30">SYNTHETIC DEMO</text>';
  const names = [
    ["轻便通勤双肩包", "Everyday backpack"],
    ["无线降噪耳机", "Wireless headphones"],
    ["磁吸移动电源", "Magnetic power bank"],
    ["轻量运动跑鞋", "Lightweight trainers"],
    ["便携咖啡随行杯", "Travel coffee cup"],
    ["复古数码相机", "Pocket digital camera"],
  ];
  for (let row = 0; row < 4; row++)
    for (let col = 0; col < 2; col++) {
      const n = row * 2 + col,
        x = 28 + col * 572,
        y = 285 + row * 650,
        color = colors[n % 6];
      svg += `<rect x="${x}" y="${y}" width="542" height="620" rx="28" fill="#ffffff"/><rect x="${x + 12}" y="${y + 12}" width="518" height="370" rx="20" fill="${color}"/><rect x="${x + 12}" y="${y + 12}" width="518" height="370" rx="20" fill="url(#lines)"/>`;
      svg += `<circle cx="${x + 271}" cy="${y + 190}" r="113" fill="${colors[(n + 2) % 6]}" stroke="#ffffff" stroke-width="12"/><path d="M${x + 210} ${y + 140}h122v115h-122z" fill="#27273a" opacity=".8"/><path d="M${x + 229} ${y + 140}v-20q42-40 84 0v20" fill="none" stroke="#27273a" stroke-width="14"/>`;
      svg += text(x + 22, y + 400, 495, 47, names[n % 6][0], names[n % 6][1]);
      svg += text(
        x + 22,
        y + 455,
        485,
        35,
        "限时优惠 · 今日包邮",
        "Limited offer · Free delivery",
      );
      svg += `<text x="${x + 22}" y="${y + 555}" fill="#e54a24" font-size="57" font-family="Arial">¥ ${128 + n * 39}.00</text><rect x="${x + 364}" y="${y + 502}" width="150" height="58" rx="29" fill="#0a65ed"/>`;
      svg += text(
        x + 386,
        y + 510,
        107,
        36,
        "选购",
        "Shop",
        "#0a65ed",
        "#ffffff",
      );
      svg += text(
        x + 22,
        y + 574,
        480,
        29,
        "已有 2,400+ 人购买",
        "2,400+ orders · ★ 4.9",
      );
    }
  svg += "</svg>";
  const session = {
    id,
    status: "ready",
    width: 1170,
    height: 3000,
    created_at: 1,
    expires_at: 9999999999,
    error: null,
    original_url: "/dense-glass-fixture.svg",
    annotated_url: null,
    view_url: `/view/${id}`,
    regions,
  };
  await page.route(`${origin}/api/sessions/${id}`, (route) =>
    route.fulfill({ json: session }),
  );
  await page.route(`${origin}/dense-glass-fixture.svg`, (route) =>
    route.fulfill({ contentType: "image/svg+xml", body: svg }),
  );
  await page.setViewportSize({ width: 480, height: 900 });
  await page.goto(`${origin}/view/${id}`);
  await page.locator('.viewer-toolbar[data-optics="webgl"]').waitFor();
  await page
    .getByRole("button", {
      name: "Everyday backpack. Show original and full translation",
      exact: true,
    })
    .first()
    .click();
  await page.locator('.detail-island[data-optics="webgl"]').waitFor();
  await page.evaluate(() => scrollTo(0, 280));
  await page.waitForTimeout(400);
  await page.bringToFront();
  await page.screenshot({ path: "output/playwright/dense-glass.png" });
}
