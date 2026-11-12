// Run against an isolated backend with a real settings database (for example port 8100).
// Creates a separate browser context to prove synchronization without shared browser storage.
async (page) => {
  const origin=new URL(page.url()).origin;
  const response=await page.request.get(`${origin}/api/settings/appearance`);
  const original=await response.json();
  const otherContext=await page.context().browser().newContext({viewport:{width:390,height:844}});
  const phone=await otherContext.newPage();
  const assert=(value,message)=>{if(!value)throw new Error(message);};
  let releaseHeldGet=()=>{};
  try {
    await page.setViewportSize({width:1280,height:940});
    await page.goto(origin);
    await page.getByRole('link',{name:'Appearance settings',exact:true}).click();
    assert(new URL(page.url()).pathname==='/settings','Home did not open settings');
    await page.locator('.demo-lens[data-optics="webgl"]').waitFor();
    await phone.goto(`${origin}/settings`);
    await phone.locator('#glass-frost:enabled').waitFor();
    const saved=page.waitForResponse(r=>r.url().endsWith('/api/settings/appearance')&&r.request().method()==='PATCH'&&r.ok());
    await page.getByLabel('Frost',{exact:true}).press('End');
    await saved;
    await phone.waitForFunction(()=>document.querySelector('#glass-frost').value==='6',{},{timeout:8000});
    const edited=phone.waitForResponse(r=>r.url().endsWith('/api/settings/appearance')&&r.request().method()==='PATCH'&&r.ok());
    await phone.getByLabel('Glossiness',{exact:true}).press('Home');
    await edited;
    await page.waitForFunction(()=>document.querySelector('#glass-gloss').value==='0',{},{timeout:8000});
    assert(await page.getByLabel('Frost',{exact:true}).inputValue()==='6','Another device erased an unrelated setting');
    await page.getByRole('radio',{name:'3×',exact:true}).check();
    await phone.waitForFunction(()=>document.querySelector('input[name=resolution][value="3x"]').checked,{},{timeout:8000});
    await phone.locator('.demo-lens[data-optics="webgl"]').waitFor();
    await phone.waitForFunction(()=>{const lens=document.querySelector('.demo-lens');return lens.querySelector('canvas').width/lens.getBoundingClientRect().width>2.99;});
    await phone.getByRole('button',{name:'Fine detail',exact:true}).click();
    await phone.locator('.demo-type .demo-lens[data-optics="webgl"]').waitFor();
    await phone.waitForTimeout(600);
    await phone.emulateMedia({reducedMotion:'reduce'});
    await phone.waitForFunction(()=>document.querySelector('.demo-play-row button').disabled);
    assert(await phone.getByRole('button',{name:'Move scene',exact:true}).isDisabled(),'Demo animation ignored reduced motion');
    assert(await phone.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Settings overflow the phone width');
    await page.screenshot({path:'output/playwright/appearance-desktop.png',scale:'css'});
    await phone.screenshot({path:'output/playwright/appearance-mobile.png',scale:'css'});

    let fail=true;
    await page.route(`${origin}/api/settings/appearance`,route=>{
      if(fail&&route.request().method()==='PATCH'){fail=false;return route.abort();}
      return route.continue();
    });
    await page.getByLabel('Frost',{exact:true}).press('Home');
    await page.getByRole('alert').waitFor();
    assert(await page.getByLabel('Frost',{exact:true}).inputValue()==='0','Failed save discarded the preview');
    await page.getByRole('button',{name:'Retry',exact:true}).click();
    await page.getByRole('alert').waitFor({state:'detached'});
    await phone.waitForFunction(()=>document.querySelector('#glass-frost').value==='0',{},{timeout:8000});
    await page.unroute(`${origin}/api/settings/appearance`);
    // A slow refresh started before an edit must not roll back a successful save.
    let markStarted,markFinished,held=false;
    const started=new Promise(resolve=>{markStarted=resolve;});
    const finished=new Promise(resolve=>{markFinished=resolve;});
    const release=new Promise(resolve=>{releaseHeldGet=resolve;});
    await page.route(`${origin}/api/settings/appearance`,async route=>{
      if(route.request().method()==='GET'&&!held){
        held=true;const stale=await route.fetch();markStarted();await release;
        await route.fulfill({response:stale});markFinished();return;
      }
      return route.continue();
    });
    await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
    await started;
    const freshSave=page.waitForResponse(r=>r.url().endsWith('/api/settings/appearance')&&r.request().method()==='PATCH'&&r.ok());
    await page.getByLabel('Frost',{exact:true}).press('End');await freshSave;
    releaseHeldGet();await finished;await page.waitForTimeout(100);
    assert(await page.getByLabel('Frost',{exact:true}).inputValue()==='6','A stale refresh rolled back a saved edit');
    await page.unroute(`${origin}/api/settings/appearance`);
    await page.getByRole('button',{name:'Reset appearance to default',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#glass-frost').value==='1');
    await page.waitForTimeout(600);
    await phone.reload();
    await phone.locator('#glass-frost:enabled').waitFor();
    assert(await phone.getByLabel('Frost',{exact:true}).inputValue()==='1','Reset did not persist on the server');
    return 'Home entry, live optical preview, cross-device edits, 3× quality, retry, reset and mobile layout passed';
  } finally {
    releaseHeldGet();
    await page.unroute(`${origin}/api/settings/appearance`);
    await page.request.patch(`${origin}/api/settings/appearance`,{data:original});
    await otherContext.close();
  }
}
