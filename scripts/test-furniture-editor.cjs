// Runs the real editor code and room geometry in Node, with a DOM/WebGL test
// double. This verifies logic and buffer lengths, not GPU shader compilation.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'Tuck/Resources/DemoRoom.html'), 'utf8');
const dataScript = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const editorScript = fs.readFileSync(path.join(root, 'Tuck/Resources/DemoFurniture.js'), 'utf8');

function roomContext({normalMaps = true} = {}) {
  const ids = new Map(), events = [], draws = [], materials = [], uniforms = new Map(), textures = new Map();
  let activeTexture;
  let constant = 100, boundBuffer, nextID = 0;
  const constants = new Map(), pointers = new Map(), enabled = new Set();
  const gl = new Proxy({
    createBuffer: () => ({id: ++nextID}),
    bindBuffer: (_, buffer) => { boundBuffer = buffer; },
    bufferData: (_, data) => { boundBuffer.length = data.length; },
    getShaderParameter: () => true, getProgramParameter: () => true,
    checkFramebufferStatus: () => gl.FRAMEBUFFER_COMPLETE,
    getAttribLocation: (_, name) => ({aPosition: 0, aNormal: 1, aUV: 2}[name]),
    getUniformLocation: (_, name) => name,
    getExtension: name => name === 'OES_standard_derivatives' && normalMaps ? {} : null,
    activeTexture: unit => { activeTexture = unit; },
    bindTexture: (_, texture) => textures.set(activeTexture, texture),
    uniform1i: (name, value) => uniforms.set(name, value),
    uniform1f: (name, value) => uniforms.set(name, value),
    uniform3fv: (name, value) => uniforms.set(name, Array.from(value)),
    enableVertexAttribArray: index => enabled.add(index),
    disableVertexAttribArray: index => enabled.delete(index),
    vertexAttribPointer: (index, size) => pointers.set(index, {size, buffer: boundBuffer}),
    drawArrays: (_, first, count) => {
      for (const index of enabled) {
        const value = pointers.get(index);
        assert(value && value.buffer.length >= (first + count) * value.size,
          `Attribute ${index} buffer is too small`);
      }
      draws.push(count);
      if (enabled.has(2)) materials.push({color: uniforms.get('uColor'), normal: uniforms.get('uHasNormalMap'),
        roughness: uniforms.get('uHasRoughnessMap'), normalTexture: textures.get(gl.TEXTURE2),
        roughnessTexture: textures.get(gl.TEXTURE3)});
    },
  }, {get(target, key) {
    if (key in target) return target[key];
    if (/^[A-Z0-9_]+$/.test(key)) {
      if (!constants.has(key)) constants.set(key, constant++);
      return constants.get(key);
    }
    if (/^create/.test(key)) return () => ({id: ++nextID});
    return () => {};
  }});
  class Element {
    constructor(tag) {
      this.tagName = tag; this.children = []; this.listeners = {}; this.style = {};
      this.value = ''; this.hidden = false; this.clientWidth = 390; this.clientHeight = 310;
      this.classList = {toggle() {}};
    }
    set id(value) { this._id = value; ids.set(value, this); }
    get id() { return this._id; }
    append(...children) { this.children.push(...children); }
    add(value) { this.children.push(value); }
    replaceChildren(...children) { this.children = children; }
    setAttribute() {} remove() { this.removed = true; } click() { this.onclick?.(); }
    addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
    getContext() { return gl; }
    getBoundingClientRect() { return {left: 0, top: 0, width: 390, height: 310}; }
    setPointerCapture() {} blur() { document.activeElement = null; }
  }
  const document = {head: new Element('head'), body: new Element('body'), activeElement: null,
    createElement: tag => new Element(tag), getElementById: id => ids.get(id) || null};
  for (const id of ['c', 'chatHandle', 'axisIndicator']) { const el = new Element(id === 'c' ? 'canvas' : 'div'); el.id = id; }
  class Image {
    constructor() { this.width = this.height = 2; }
    set src(value) { queueMicrotask(() => value.startsWith('data:image/') ? this.onload() : this.onerror()); }
  }
  const context = vm.createContext({console, document, Image,
    Option: function(text, value) { this.text = text; this.value = value; },
    Float32Array, Uint8Array, Map, Set, Math, Number, Array, Error, Promise,
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    innerWidth: 390, innerHeight: 310, devicePixelRatio: 1,
    requestAnimationFrame: callback => { context.nextFrame = callback; },
    addEventListener() {}, setTimeout, clearTimeout,
    webkit: {messageHandlers: {furniture: {postMessage: value => events.push(JSON.parse(JSON.stringify(value)))},
      previewError: {postMessage: error => { throw Error(error); }}}},
  });
  context.window = context;
  vm.runInContext(dataScript, context, {filename: 'DemoRoom-data.js'});
  vm.runInContext(editorScript, context, {filename: 'DemoFurniture.js'});
  return {context, api: context.tuckFurniture, editor: context.tuckEditor, events, ids, draws, materials,
    body: document.body,
    frame: () => context.nextFrame(),
    pointer: (name, id, x, y) => {
      for (const fn of ids.get('c').listeners[name] || []) fn({pointerId: id, clientX: x, clientY: y});
    }};
}

function fixture(id) {
  // Synthetic geometry only. Actual bundled USDZ decoding is tested by XCTest.
  const corners = [[-.3,0,-.35],[.3,0,-.35],[.3,.8,-.35],[-.3,.8,-.35],
    [-.3,0,.35],[.3,0,.35],[.3,.8,.35],[-.3,.8,.35]];
  const faces = [[0,1,2],[0,2,3],[4,6,5],[4,7,6],[0,4,5],[0,5,1],
    [3,2,6],[3,6,7],[0,3,7],[0,7,4],[1,5,6],[1,6,2]];
  const positions = faces.flatMap(face => face.flatMap(i => corners[i]));
  const normals = faces.flatMap(() => [0,1,0,0,1,0,0,1,0]);
  const pack = values => Buffer.from(new Float32Array(values).buffer).toString('base64');
  return {id, label: `Actual product ${id}`, bounds: [[-.3,0,-.35],[.3,.8,.35]],
    parts: [{positions: pack(positions), normals: pack(normals), uvs: pack(Array(72).fill(0)),
      color: [.5,.3,.15], roughness: .7, texture: 'data:image/png;base64,fixture',
      normalTexture: 'data:image/png;base64,normal', normalStrength: .6,
      roughnessTexture: 'data:image/png;base64,roughness'}]};
}

const clean = value => JSON.parse(JSON.stringify(value));
(async () => {
  const a = roomContext(), api = a.api, editor = a.editor;
  assert.equal(api.layout().items.length, 7);
  assert(api.layout().items.every(item => item.label));
  assert.equal(a.events[0].type, 'ready');
  assert(a.draws.length > 0);
  assert.equal(a.ids.get('furnitureTools').children.length, 1);
  assert.equal(a.ids.get('furnitureTools').children[0].textContent, 'Names on');
  const descendants = node => [node, ...node.children.flatMap(descendants)];
  assert(!descendants(a.body).some(node => node.tagName === 'select'), 'No furniture selection dropdown in the room');
  await assert.rejects(() => api.register(fixture('invented')), /Unknown chair/);
  const ids = ['sofa_007_brown', 'sofa_027_brown', 'sofa_028_brown'];
  for (const id of ids) await api.register(fixture(id));
  for (const id of ids) api.tryProduct(id);
  api.tryProduct(ids[0]); api.tryProduct(ids[0]);
  assert.equal(api.layout().items.length, 10, 'repeated Try must be idempotent');
  assert.equal(new Set(api.layout().items.filter(i => i.productID).map(i => i.productID)).size, 3);
  a.frame(); // checks texture UV and shadow-pass buffer lengths
  assert(a.materials.length >= 3);
  for (const material of a.materials) {
    assert.deepEqual(material.color, [.5,.3,.15], 'Selection must not recolor an original chair');
    assert.equal(material.normal, 1); assert.equal(material.roughness, 1);
    assert(material.normalTexture && material.roughnessTexture);
  }
  const fallback = roomContext({normalMaps: false});
  await fallback.api.register(fixture(ids[0])); fallback.api.tryProduct(ids[0]); fallback.frame();
  assert(fallback.materials.length > 0);
  assert(fallback.materials.every(material => material.normal === 0 && material.roughness === 1));
  const product = api.layout().items.find(i => i.productID === ids[0]);
  editor.setTransform(product.instanceId, [0,0,.15], .3);
  api.select(product.instanceId); api.rename('My reading chair'); api.rotate(15);
  assert.equal(api.layout().items.find(i => i.productID === ids[0]).label, 'My reading chair');
  assert(Math.abs(api.layout().items.find(i => i.productID === ids[0]).yawRadians - (.3 + Math.PI / 12)) < 1e-8);
  const bed = api.layout().items.find(i => i.assetId === 'bed');
  api.select(bed.instanceId); api.rename('Guest bed'); api.removeSelected();
  assert(!api.layout().items.some(i => i.assetId === 'bed'));
  assert.equal(api.layout().items.filter(i => i.productID).length, 3);
  api.removeProduct(ids[1]);
  assert(!api.layout().items.some(i => i.productID === ids[1]));
  api.tryProduct(ids[1]);
  assert.equal(api.layout().items.filter(i => i.productID === ids[1]).length, 1);

  // Use the real ray picking and existing pointer movement implementation.
  api.removeProduct(ids[1]); api.removeProduct(ids[2]);
  api.select(product.instanceId);
  editor.setTransform(product.instanceId, [0,0,.1], 0);
  const current = api.layout().items.find(i => i.instanceId === product.instanceId);
  const pixel = editor.project(editor.boundsCenter(current));
  assert.equal(editor.pick(editor.ray(...pixel)).item.instanceId, product.instanceId);
  const before = [...current.position], camera = clean(editor.interactionState().camera);
  a.pointer('pointerdown', 1, ...pixel);
  a.pointer('pointermove', 1, pixel[0] + 40, pixel[1] + 5);
  a.pointer('pointerup', 1, pixel[0] + 40, pixel[1] + 5);
  const after = api.layout().items.find(i => i.instanceId === product.instanceId).position;
  assert(after.some((value, i) => value !== before[i]), 'drag must move the selected furniture');
  assert.deepEqual(clean(editor.interactionState().camera), camera, 'furniture drag must not orbit the camera');
  assert(a.events.some(event => event.type === 'layout' && event.layout.items.some(i => i.productID === ids[0])));

  api.tryProduct(ids[1]); api.tryProduct(ids[2]);

  const saved = clean(api.layout());
  const b = roomContext();
  for (const id of ids) await b.api.register(fixture(id));
  b.api.restore(saved);
  assert.deepEqual(clean(b.api.layout()), saved, 'reload must retain names, movement, removals, and all products');
  const invalid = clean(saved); invalid.items.push({...invalid.items.find(i => i.productID), instanceId: 'duplicate'});
  assert.throws(() => b.api.restore(invalid), /duplicate product/);
  assert.deepEqual(clean(b.api.layout()), saved, 'invalid restore must not partially overwrite the room');
  b.api.select(saved.items.find(i => i.productID).instanceId); b.api.removeSelected();
  assert.equal(b.api.layout().items.filter(i => i.productID).length, 2);
  assert.equal(b.events.at(-1).layout.items.filter(i => i.productID).length, 2, 'Remove must report confirmed card membership');
  b.api.reset();
  assert.equal(b.api.layout().items.length, 7);
  assert.equal(b.api.layout().items.filter(i => i.productID).length, 0);
  b.api.tryProduct(ids[0]); assert.equal(b.api.layout().items.length, 8);
  assert.equal(b.editor.interactionState().furnitureMoveEnabled, true, 'Try must enable furniture movement');
  b.editor.setFurnitureMoveEnabled(false);
  const orbitBefore = clean(b.editor.interactionState().camera);
  b.pointer('pointerdown', 5, 10, 50); b.pointer('pointermove', 5, 35, 60); b.pointer('pointerup', 5, 35, 60);
  assert.notDeepEqual(clean(b.editor.interactionState().camera), orbitBefore, 'orbit mode must rotate the room camera');
  const reading = b.api.layout().items.find(i => i.productID);
  b.api.select(reading.instanceId);
  assert.equal(b.editor.interactionState().furnitureMoveEnabled, true, 'selecting furniture enables editing');

  // Keep the latest scanned-room adapter and saved-room source while adding a product.
  const matrix = (x,y,z) => [1,0,0,0,0,1,0,0,0,0,1,0,x,y,z,1];
  const scan = {schemaVersion:1,id:'scan-fixture',units:'meters',coordinateSystem:'right-handed-y-up',transformLayout:'column-major',
    walls:[{id:'wall-a',dimensions:{width:4,height:2.6,depth:0},transform:matrix(0,1.3,-2)}],
    doors:[],windows:[],openings:[],floors:[],
    objects:[{id:'chair-a',category:'chair',label:'My original chair',dimensions:{width:.6,height:.8,depth:.7},transform:matrix(0,.4,0)}]};
  b.editor.loadScannedRoom(scan);
  b.api.tryProduct(ids[0]); b.api.tryProduct(ids[1]);
  const scanSaved = clean(b.api.layout());
  assert.equal(scanSaved.scannedRoom.id, 'scan-fixture');
  assert.equal(scanSaved.items.filter(i=>i.productID).length, 2);
  b.api.restore(scanSaved);
  assert.deepEqual(clean(b.api.layout()), scanSaved, 'saved scan plus actual product placements must survive reload');
  if (b.editor.chatContext) {
    assert.equal(b.api.layout().items.find(i=>i.assetId==='scan-chair-a').label,'My original chair');
    assert.equal(b.editor.chatContext().objects.find(i=>i.id==='chair-a').label,'My original chair');
  }
  b.api.reset();
  assert.equal(b.api.layout().scannedRoom.id, 'scan-fixture', 'reset must retain the current room source');
  assert.equal(b.api.layout().items.filter(i=>i.productID).length, 0);
  b.api.restore(saved);
  assert.equal(b.editor.interactionState().sourceRoomID, null, 'switching back must restore the demo structure');
  assert.deepEqual(clean(b.api.layout()), saved);
  if (b.editor.chatContext) {
    const id = saved.items.find(i=>i.productID).instanceId;
    b.api.select(id); b.api.rename('Chair for reading');
    let context = b.editor.chatContext();
    const item = context.objects.find(i=>i.id===id);
    assert.equal(item.label,'Chair for reading','chat must include edited product names');
    assert(item.dimensionsMeters.every(v=>Number.isFinite(v)&&v>0),'chat must measure binary model buffers');
    b.api.removeSelected();
    context = b.editor.chatContext();
    assert(!context.objects.some(i=>i.id===id),'chat must exclude a removed product');
  }
  console.log('PASS: initial scene, 3-model registration, textured buffers, Try deduplication, multiple products, rename, rotate, existing furniture removal, ray-picked drag, card synchronization, restore validation, and reset.');
  console.log('Scope: Node DOM/WebGL doubles + synthetic chair geometry; GPU shaders, USDZ import, and iOS UI require Xcode/device testing.');
})().catch(error => { console.error(error); process.exit(1); });
