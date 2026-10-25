// Real WebGL + real bundled assets. Optional: TUCK_QA_DIR saves local QA images.
// npm install --prefix /tmp/tuck-browser playwright@1.51.1
// /tmp/tuck-browser/node_modules/.bin/playwright install chromium
// TUCK_PLAYWRIGHT=/tmp/tuck-browser/node_modules/playwright node scripts/test-chair-webgl.cjs
const {chromium} = require(process.env.TUCK_PLAYWRIGHT || 'playwright');
const fs = require('node:fs'), http = require('node:http'), path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../Tuck/Resources');
const ids = ['sofa_007_brown', 'sofa_027_brown', 'sofa_028_brown'];
const errors = [];
const server = http.createServer((req, res) => {
  const file = path.resolve(root, '.' + decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  try {
    res.setHeader('Content-Type', file.endsWith('.js') ? 'application/javascript' : file.endsWith('.html') ? 'text/html' : 'application/json');
    res.end(fs.readFileSync(file));
  } catch { res.writeHead(404).end(); }
});
let browser;
const pixels = page => page.evaluate(() => {
  dirty = true; render();
  const data = new Uint8Array(canvas.width * canvas.height * 4);
  gl.readPixels(0, 0, canvas.width, canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, data);
  let hash = 2166136261, nonwhite = 0;
  for (let k=0;k<data.length;k++) hash = Math.imul(hash ^ data[k], 16777619) >>> 0;
  for (let k=0;k<data.length;k+=4) if (Math.min(data[k],data[k+1],data[k+2]) < 245) nonwhite++;
  return {hash, nonwhite, error: gl.getError()};
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  browser = await chromium.launch({headless: true, args: ['--no-sandbox', '--enable-unsafe-swiftshader']});
  const page = await browser.newPage({viewport: {width: 700, height: 700}});
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto(`http://127.0.0.1:${server.address().port}/DemoRoom.html`);
  await page.waitForFunction(() => window.tuckFurniture);
  for (const id of ids) {
    await page.evaluate(async id => {
      await tuckFurniture.register(await (await fetch(`ChairMaterials/${id}.tuckmodel`)).json());
      tuckFurniture.tryProduct(id); tuckFurniture.tryProduct(id);
    }, id);
  }
  assert.equal(await page.evaluate(() => tuckFurniture.layout().items.filter(i => i.productID).length), 3);
  assert.equal((await pixels(page)).error, 0, 'All three models render together in the sample room');
  const snapshot = await page.evaluate(() => tuckFurniture.layout());
  const originalScene = await page.evaluate(() => ({target:sceneTarget, bounds:roomBounds}));
  let firstHash;
  for (const id of ids) {
    const stats = await page.evaluate(id => {
      tuckFurniture.restore({version:1,units:'meters',upAxis:'Y',items:[]});
      tuckFurniture.tryProduct(id); tuckEditor.setTransform(`product:${id}`, [0,0,0], 0);
      tuckFurniture.select(null);
      // Inspect the chair without room geometry occluding it. Production APIs
      // and the production shader remain in use, including the shadow pass.
      roomObjects=[]; sceneTarget=[0,.4,0]; roomBounds=[[-.4,0,-.5],[.4,1,.5]];
      tuckEditor.setCamera(-.65,.25,2.1); showNames=false;
      const part=assetMap.get(id).objects[0];
      return {vertices:part.positionsArray.length/3, triangles:part.count/3,
        maps:!!(part.map&&part.normalMap&&part.roughnessMap&&part.metallicMap),
        retainedEncodedImages:!!part.texture, indexed:!!part.indexBuffer};
    }, id);
    assert(stats.vertices > 150000 && stats.triangles > 290000 && stats.maps && stats.indexed);
    assert.equal(stats.retainedEncodedImages, false, 'Release large encoded image strings after upload');
    const before = await pixels(page);
    assert.equal(before.error, 0); assert(before.nonwhite > 50000, 'Chair must have visible textured pixels');
    if (id === ids[0]) firstHash = before.hash;
    await page.evaluate(id => tuckFurniture.select(`product:${id}`), id);
    assert.equal((await pixels(page)).hash, before.hash, 'Selecting a chair must not recolor it');
    await page.evaluate(() => { lightMatrix = identity; });
    assert.equal((await pixels(page)).hash, before.hash, 'Shadow-map changes must not stain the chair');
    if (process.env.TUCK_QA_DIR) {
      fs.mkdirSync(process.env.TUCK_QA_DIR, {recursive:true});
      await page.screenshot({path:path.join(process.env.TUCK_QA_DIR, `${id}.png`)});
    }
    await page.evaluate(id => {
      const p=assetMap.get(id).objects[0]; p.savedNormal=p.normalMap; p.normalMap=null;
    }, id);
    assert.notEqual((await pixels(page)).hash, before.hash, 'Original normal texture must affect surface detail');
    await page.evaluate(id => {
      const p=assetMap.get(id).objects[0]; p.normalMap=p.savedNormal; delete p.savedNormal;
      tuckFurniture.rotate(45); tuckFurniture.rename('Demo chair');
    }, id);
    assert.notEqual((await pixels(page)).hash, before.hash, 'Rotation changes the visible model');
    await page.evaluate(() => tuckFurniture.removeSelected());
    assert.equal((await pixels(page)).nonwhite, 0, 'Remove clears the chair mesh');
    console.log(`PASS ${id}: original GPU buffers, four maps, no selection tint/shadow stains, rotate/remove`);
  }
  await page.evaluate(({snapshot, originalScene}) => {
    tuckFurniture.restore(snapshot); roomObjects=room.parts.map(upload);
    roomBounds=originalScene.bounds; sceneTarget=originalScene.target;
    tuckEditor.setCamera(-.72,.62,7.5);
  }, {snapshot, originalScene});
  assert.equal((await pixels(page)).error, 0);
  assert.equal(await page.evaluate(() => tuckFurniture.layout().items.filter(i=>i.productID).length), 3);
  await page.close();

  // Real GPU fallback for older WebGL implementations, including no derivatives.
  const fallback = await browser.newPage({viewport:{width:700,height:700}});
  fallback.on('pageerror', e => errors.push(String(e)));
  await fallback.addInitScript(() => {
    const original=WebGLRenderingContext.prototype.getExtension;
    WebGLRenderingContext.prototype.getExtension=function(name){
      return ['OES_element_index_uint','OES_standard_derivatives'].includes(name) ? null : original.call(this,name);
    };
  });
  await fallback.goto(`http://127.0.0.1:${server.address().port}/DemoRoom.html`);
  await fallback.evaluate(async id => {
    await tuckFurniture.register(await (await fetch(`ChairMaterials/${id}.tuckmodel`)).json());
    tuckFurniture.restore({version:1,units:'meters',upAxis:'Y',items:[]}); tuckFurniture.tryProduct(id);
    tuckEditor.setTransform(`product:${id}`,[0,0,0],0); tuckFurniture.select(null);
    roomObjects=[]; sceneTarget=[0,.4,0]; roomBounds=[[-.4,0,-.5],[.4,1,.5]];
    tuckEditor.setCamera(-.65,.25,2.1); showNames=false;
  }, ids[0]);
  const fallbackResult=await pixels(fallback);
  assert.equal(fallbackResult.error,0);
  assert.equal(fallbackResult.hash,firstHash,'Non-indexed fallback preserves the exact rendered appearance');
  assert.deepEqual(errors,[]);
  console.log('PASS: real WebGL shader compilation, all three together, restore, and identical extension fallback');
})().catch(error => { console.error(error); process.exitCode=1; })
  .finally(async () => { if(browser) await browser.close(); await new Promise(resolve=>server.close(resolve)); });
