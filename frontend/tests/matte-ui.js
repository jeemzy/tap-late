// Synthetic appearance responses: no changes to the real server's glass preferences.
async (page) => {
  const origin = new URL(page.url()).origin, endpoint = `${origin}/api/settings/appearance`;
  let settings = {...await (await page.request.get(endpoint)).json(),matte:0};
  delete settings.matte; // Older saved/API payloads must retain the polished default.
  const originalRefraction = settings.refraction_strength;
  const route = current => current.route(endpoint, async request => {
    if (request.request().method()==='PATCH') settings={...settings,...request.request().postDataJSON()};
    await request.fulfill({json:settings});
  });
  const other = await page.context().browser().newContext({viewport:{width:390,height:844}});
  const phone = await other.newPage();
  const check=(value,message)=>{if(!value)throw new Error(message);};
  const controlErrors=[];
  const onConsole=message=>{if(message.type()==='error'&&/controlled input|uncontrolled input/.test(message.text()))controlErrors.push(message.text());};
  page.on('console',onConsole);
  await route(page); await route(phone);
  try {
    await page.setViewportSize({width:1440,height:1000});
    await page.goto(`${origin}/settings`); await phone.goto(`${origin}/settings`);
    const slider = page.getByLabel('Matte finish',{exact:true});
    await page.locator('.demo-lens[data-optics="webgl"]').waitFor();
    check(await slider.inputValue()==='0','Old appearance must start polished');
    check(controlErrors.length===0,'Old appearance payload left the matte control undefined');
    const browser=page.context().browser().browserType().name();
    await page.screenshot({path:`output/playwright/matte-${browser}-desktop-clear.png`});
    await slider.press('Home');
    for(let i=0;i<13;i++)await slider.press('ArrowRight');
    await page.waitForFunction(()=>document.querySelector('#glass-matte').value==='0.65');
    await phone.waitForFunction(()=>document.querySelector('#glass-matte').value==='0.65',{},{timeout:8000});
    check(settings.refraction_strength===originalRefraction,'Matte edit replaced another optical choice');
    await page.locator('.demo-lens[data-optics="webgl"]').waitFor();
    await page.screenshot({path:`output/playwright/matte-${browser}-desktop.png`});
    await phone.getByLabel('Matte finish',{exact:true}).scrollIntoViewIfNeeded();
    await phone.locator('.demo-lens[data-optics="webgl"]').waitFor();
    await phone.screenshot({path:`output/playwright/matte-${browser}-phone.png`});
    check(await phone.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Phone layout overflows');
    check(await page.locator('.demo-lens-copy').evaluate(el=>getComputedStyle(el).filter)==='none','Foreground text was blurred');
    const extension = await page.locator('.demo-lens').evaluate(el=>{
      const extension=el.querySelector('canvas').getContext('webgl').getExtension('WEBGL_lose_context');
      window.__matteContext=extension;extension.loseContext();return !!extension;
    });
    check(extension,'No context-loss testing support');
    await page.locator('.demo-lens[data-optics="fallback"]').waitFor();
    const fallback=await page.locator('.demo-lens').evaluate(el=>{
      const style=getComputedStyle(el); return style.backdropFilter || style.webkitBackdropFilter;
    });
    const fallbackRadius=Number(fallback.match(/blur\(([\d.]+)px\)/)?.[1]);
    check(Math.abs(fallbackRadius-39.6)<.01,'Matte amount was lost in CSS fallback: '+fallback);
    await page.evaluate(()=>window.__matteContext.restoreContext());
    await page.locator('.demo-lens[data-optics="webgl"]').waitFor();
    await phone.emulateMedia({reducedMotion:'reduce',contrast:'more'});
    await phone.locator('.demo-lens[data-optics="opaque"]').waitFor();
    check(await phone.locator('.demo-lens').evaluate(el=>getComputedStyle(el).backdropFilter)==='none','High contrast must remain opaque');
    const resetSaved=page.waitForResponse(response=>response.url()===endpoint&&response.request().method()==='PATCH'&&response.ok());
    await page.getByRole('button',{name:'Reset appearance to default',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#glass-matte').value==='0');
    await resetSaved;
    await page.reload();await slider.waitFor();
    check(await slider.inputValue()==='0','Reset did not persist');
    return {settings:'passed',crossDevice:'passed',contextRecovery:'passed',accessibility:'passed',foreground:'sharp'};
  } finally {
    page.off('console',onConsole);
    await page.unroute(endpoint); await other.close();
  }
}
