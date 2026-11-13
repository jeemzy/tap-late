// Run against Vite: playwright-cli run-code --filename frontend/tests/glass-matte.js
// Exercises real rendered pixels. No screenshots, translations or saved settings are mutated.
async (page) => {
  const result = await page.evaluate(async () => {
    const { GlassRenderer } = await import('/src/lib/glass-renderer.ts');
    const { DEFAULT_GLASS } = await import('/src/lib/glass-settings.ts');
    const source = document.createElement('canvas'); source.width = 800; source.height = 480;
    const context = source.getContext('2d'), data = context.createImageData(800, 480);
    for (let y = 0; y < 480; y++) for (let x = 0; x < 800; x++) {
      const i = (y * 800 + x) * 4;
      data.data.set([x * 255 / 800, y * 255 / 480, (Math.floor(x / 8) % 2) * 200 + 20, 255], i);
    }
    context.putImageData(data, 0, 0);
    const canvas = document.createElement('canvas'), renderer = new GlassRenderer(canvas);
    renderer.setSource(source);
    const gl = canvas.getContext('webgl');
    const frame = { bounds: {x:60,y:60,width:240,height:120}, scene:{x:0,y:0,width:400,height:240},
      radius:28,dpr:2,pointer:[.5,.2],energy:0,background:[0,0,0],reducedMotion:false };
    const base = {...DEFAULT_GLASS,frost:0,reflection:0,gloss:0,dispersion:0,magnification:1,refraction_strength:2.5};
    const render = (changes={}) => {
      if (!renderer.draw({...frame,appearance:{...base,...changes}})) throw new Error('Shader did not render');
      const pixels = new Uint8Array(canvas.width*canvas.height*4);
      gl.readPixels(0,0,canvas.width,canvas.height,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
      return pixels;
    };
    const pixel=(data,x,y,c)=>data[((canvas.height-1-y)*canvas.width+x)*4+c];
    const contrast = data => {
      const values=Array.from({length:160},(_,i)=>pixel(data,160+i,120,2));
      return Math.max(...values)-Math.min(...values);
    };
    const difference=(a,b,left,right)=>{
      let total=0,count=0;
      for(let y=80;y<160;y+=4)for(let x=left;x<right;x+=2)for(let c=0;c<3;c++) {
        total+=Math.abs(pixel(a,x,y,c)-pixel(b,x,y,c));count++;
      }
      return total/count;
    };
    const clear=render({matte:0}), matte=render({matte:.7});
    const unbent=render({matte:.7,refraction_strength:0});
    const glossy=render({matte:.7,gloss:2});
    const dispersed=render({matte:.7,dispersion:3});
    const reflected=render({matte:.7,reflection:.25});
    const matteZeroAgain=render({matte:0});
    const beforeMove=render({matte:.7});
    renderer.draw({...frame,scene:{...frame.scene,x:20},appearance:{...base,matte:.7}});
    const afterMove=new Uint8Array(canvas.width*canvas.height*4);
    gl.readPixels(0,0,canvas.width,canvas.height,gl.RGBA,gl.UNSIGNED_BYTE,afterMove);
    const output={clearContrast:contrast(clear),matteContrast:contrast(matte),
      refractionDifference:difference(matte,unbent,2,36),glossDifference:difference(matte,glossy,2,10),
      dispersionDifference:difference(matte,dispersed,2,10),
      topGreen:pixel(matte,240,70,1),bottomGreen:pixel(matte,240,170,1),
      reflectionDifference:difference(matte,reflected,100,360),
      zeroDifference:difference(clear,matteZeroAgain,2,478),
      scrollDifference:difference(beforeMove,afterMove,100,360),corner:pixel(matte,0,0,3),error:gl.getError()};
    renderer.dispose();return output;
  });
  const check=(value,message)=>{if(!value)throw new Error(message+': '+JSON.stringify(result));};
  check(result.matteContrast<result.clearContrast*.2,'Matte finish must diffuse fine detail');
  check(result.refractionDifference>3,'Matte finish must preserve refraction');
  check(result.glossDifference>2,'Matte finish must preserve polished rim highlights');
  check(result.dispersionDifference>.5,'Matte finish must preserve chromatic edge separation');
  check(result.bottomGreen>result.topGreen+20,'Diffusion must preserve scene orientation and local colors');
  check(result.reflectionDifference>10,'Reflection control must still work');
  check(result.zeroDifference===0,'Zero matte must restore the original optical material');
  check(result.scrollDifference>2,'Diffused optics must follow the moving scene');
  check(result.corner===0&&result.error===0,'Rounded coverage or WebGL state is broken');
  return result;
}
