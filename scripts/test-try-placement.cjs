// Runs the real editor code and room geometry in Node, with a DOM/WebGL test
// double. This verifies logic and buffer lengths, not GPU shader compilation.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'Tuck/Resources/DemoRoom.html'), 'utf8');
const dataScript = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const editorScript = '';

function roomContext() {
  const ids = new Map(), events = [], draws = [];
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
  for (const id of ['c', 'chatHandle', 'axisIndicator', 'rotationHUD', 'rotateLeft', 'rotateRight']) { const el = new Element(id === 'c' ? 'canvas' : 'div'); el.id = id; }
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
  return {context, api: context.tuckProducts, editor: context.tuckEditor, events, ids, draws,
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
      color: [.5,.3,.15], roughness: .7, texture: 'data:image/png;base64,fixture'}]};
}


const clean=v=>JSON.parse(JSON.stringify(v));
(async()=>{
 const a=roomContext(),api=a.api,editor=a.editor;
 const original=clean(editor.layout()),camera=clean(editor.interactionState().camera);
 assert.equal(original.items.length,6);
 assert(!a.ids.has('furnitureLabels')&&!a.ids.has('furnitureTools')&&!a.ids.has('selectedFurniture'));
 await assert.rejects(()=>api.register(fixture('invented')),/Invalid furniture/);
 const ids=['sofa_007_brown','sofa_027_brown','sofa_028_brown'];
 for(const id of ids)await api.register(fixture(id));
 for(const id of ids)api.add(id);
 api.add(ids[0]);assert.equal(editor.layout().items.length,9,'repeated add is idempotent');
 assert.equal(editor.interactionState().furnitureMoveEnabled,false,'Try never enables move mode');
 assert.equal(editor.interactionState().selected,null,'Try does not change furniture selection');
 assert.deepEqual(clean(editor.interactionState().camera),camera,'Try never changes camera');
 a.frame(); // Real UV/shadow buffer sizes checked by the harness.
 let added=editor.layout().items.find(i=>i.assetId===ids[0]);
 editor.setTransform(added.instanceId,[0,1.6,0],.4);
 editor.setFurnitureMoveEnabled(true);editor.select(added.instanceId);
 assert.equal(a.ids.get('rotationHUD').hidden,false,'baseline rotation HUD remains available');
 a.ids.get('rotateRight').onclick();
 let rotated=editor.layout().items.find(i=>i.assetId===ids[0]);
 assert(Math.abs(rotated.yawRadians-.4-Math.PI/12)<1e-9);
 const center=editor.boundsCenter(rotated),screen=editor.project(center);
 assert.equal(editor.pick(editor.ray(...screen)).item.assetId,ids[0],'real mesh participates in original picking');
 const saved=clean(editor.layout());
 const b=roomContext();for(const id of ids)await b.api.register(fixture(id));
 b.editor.loadLayout(saved);assert.deepEqual(clean(b.editor.layout()),saved,'save/restore preserves product transforms');
 b.api.remove(ids[0]);assert(!b.editor.layout().items.some(i=>i.assetId===ids[0]));
 assert(b.editor.layout().items.some(i=>i.assetId===ids[1]),'Remove does not affect a different product');
 assert.throws(()=>b.api.add('invented'),/has not loaded/);
 assert.throws(()=>b.editor.loadLayout({...saved,items:[{...saved.items[0],assetId:'missing'}]}),/Invalid furniture/);
 const bad=fixture(ids[0]);bad.parts[0].uvs='AAAA';const fresh=roomContext();
 await assert.rejects(()=>fresh.api.register(bad),/Invalid furniture (geometry|buffer)/);
 assert.deepEqual(clean(fresh.editor.layout()),original,'failed model registration leaves room untouched');
 console.log('PASS: Try registers three textured meshes; additions/deduplication/Remove; unchanged camera and move mode; original rotation/picking; saved transform restore; invalid model rollback; no new controls.');
})().catch(error=>{console.error(error);process.exit(1)});
