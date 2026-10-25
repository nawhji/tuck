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
  for (const id of ['c', 'chatHandle', 'axisIndicator', 'rotationHUD', 'rotateLeft', 'rotateRight', 'dimensionsOverlay']) { const el = new Element(id === 'c' ? 'canvas' : 'div'); el.id = id; }
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
  return {context, api: context.tuckFurniture, editor: context.tuckEditor, events, ids, draws,
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

const harness=roomContext(),api=harness.editor,ctx=harness.context;
const overlay=ctx.document.createElement('svg');overlay.id='dimensionsOverlay';ctx.document.body.append(overlay);
const plain=v=>JSON.parse(JSON.stringify(v));const run=s=>vm.runInContext(s,ctx);
assert.equal(harness.ids.get('rotationHUD').hidden,true,'rotation buttons start hidden');
assert(!harness.ids.has('furnitureLabels')&&!harness.ids.has('selectedFurniture')&&!harness.ids.has('furnitureTools'),'no name labels, picker or replacement toolbar');
const initialFurniture=api.layout().items[0];harness.api.select(initialFurniture.instanceId);
assert.equal(harness.ids.get('rotationHUD').hidden,false,'original rotation buttons appear when selecting furniture');
let rotation=api.layout().items[0].yawRadians;
harness.ids.get('rotateRight').onclick();
assert(Math.abs(api.layout().items[0].yawRadians-rotation-Math.PI/12)<1e-9,'original clockwise step is 15 degrees');
assert.equal(harness.events.at(-1).type,'layout','rotation synchronizes with native room state');
harness.ids.get('rotateLeft').onclick();assert(Math.abs(api.layout().items[0].yawRadians-rotation)<1e-9);
api.setFurnitureMoveEnabled(false);assert.equal(harness.ids.get('rotationHUD').hidden,true);

run(`assetMap.set('test',{label:'Test',parts:[{vertices:[[-1,0,-.1],[1,1,.1]],faces:[]}],objects:[],defaultTransform:{position:[0,0,0]}})`);
function load(items){api.loadLayout({version:1,units:'meters',upAxis:'Y',items});}
const item=(id,p=[0,0,0],yaw=0)=>({instanceId:id,assetId:'bed',position:p,yawRadians:yaw});
const box=(c,half=[1,.5,.1],yaw=0)=>({center:c,half,axes:[[Math.cos(yaw),0,-Math.sin(yaw)],[0,1,0],[Math.sin(yaw),0,Math.cos(yaw)]]});
assert(api.boxesOverlap(box([0,.5,0]),box([0,.5,0])));
assert(!api.boxesOverlap(box([0,.5,0]),box([0,1.5,0])),'touching is not overlap');
assert(!api.boxesOverlap(box([0,.5,0]),box([3,.5,0])));
assert(api.boxesOverlap(box([0,.5,0]),box([0,.5,0],[1,.5,.1],Math.PI/2)));
const a=box([0,.5,0],[1,.5,.1],Math.PI/4),b=box([.3,.5,.3],[1,.5,.1],Math.PI/4);
assert(!api.boxesOverlap(a,b),'separate rotated thin boxes must not collide');
load([item('a'),item('b')]);assert.deepEqual(plain(api.overlapState()).sort(),['a','b']);
api.setTransform('b',[5,0,0],0);assert.deepEqual(plain(api.overlapState()),[],'moving clear removes warning');
const snapshot=plain(api.layout());api.add('chair');api.setTransform('a',[.4,.6,.2],1.2);
api.loadLayout(snapshot);api.setFurnitureMoveEnabled(true);api.select('a');api.setCamera(1,1,4);api.resetViewState();
assert.deepEqual(plain(api.layout()),snapshot,'reset restores additions, positions and rotation');
assert.equal(api.interactionState().selected,null);assert.equal(api.interactionState().camera.radius,7.5);
run(`activeRoomParts=[{name:'Wall',vertices:[[2,0,.5],[2,2,.5],[2,2,2],[2,0,2]],faces:[[0,1,2,3]]},{name:'Floor',vertices:[[-3,0,-3],[-3,0,3],[3,0,3],[3,0,-3]],faces:[[0,1,2,3]]}];snapSurfaceCache=null`);
const test=p=>({instanceId:'test',assetId:'test',position:p,yawRadians:0});
let t=test([.96,0,1]);assert.notEqual(api.snapToStructure(t,0,[.8,0,1]),null);assert(Math.abs(t.position[0]-1)<1e-9);
assert.equal(t.position[1],0);assert.equal(t.position[2],1,'only selected axis changes');
t=test([.96,0,0]);assert.equal(api.snapToStructure(t,0,[.8,0,0]),null,'do not snap across doorway');
t=test([.8,0,1]);assert.equal(api.snapToStructure(t,0),null,'outside threshold releases snap');
t=test([0,.04,0]);assert.notEqual(api.snapToStructure(t,1),null);assert(Math.abs(t.position[1])<1e-9);
t=test([0,.04,0]);assert.equal(api.snapToStructure(t,0),null,'horizontal motion must not alter height');
run(`activeRoomParts=[];snapSurfaceCache=null`);
t=test([.96,.02,1]);assert.equal(api.snapToStructure(t,0),null);assert.equal(api.snapToStructure(t,1),null,'furniture is never magnetic');
load([item('a')]);const dims=plain(api.dimensionSegments(api.layout().items[0]));
api.setTransform('a',[0,0,0],Math.PI/2);assert.deepEqual(plain(api.dimensionSegments(api.layout().items[0])).map(d=>d.meters),dims.map(d=>d.meters));
api.setFurnitureMoveEnabled(true);api.select('a');let previous;
for(const zoom of [3.4,7.5,15]){api.setCamera(-.72,.62,zoom);const markup=api.dimensionMarkup(api.layout().items[0]);assert(markup.includes('″'));assert(!markup.includes('NaN'));const values=markup.match(/[WHD] [0-9.]+″/g);if(previous)for(const value of values)assert(previous.includes(value),'visible measurements keep true inch values');if(!previous)previous=values;harness.frame();assert(harness.ids.get('dimensionsOverlay').innerHTML.includes('<path'));}
api.setFurnitureMoveEnabled(false);harness.frame();assert.equal(harness.ids.get('dimensionsOverlay').innerHTML,'');
console.log('PASS: editor startup, rotated overlap/contact, warning cleanup, reset layout/camera, finite wall/floor snap, doorway exclusion, axis lock, snap release, furniture exclusion, inch labels across zoom/rotation.');

(async()=>{
 run('activeRoomParts=room.parts;snapSurfaceCache=null');
 for(const id of ['sofa_007_brown','sofa_027_brown','sofa_028_brown'])await harness.api.register(fixture(id));
 const id='sofa_007_brown';harness.api.tryProduct(id);
 const product=harness.api.layout().items.find(i=>i.productID===id);
 api.setTransform(product.instanceId,[0,0,0],Math.PI/4);
 const dims=plain(api.dimensionSegments(api.layout().items.find(i=>i.instanceId===product.instanceId)));
 assert(dims.every(d=>Number.isFinite(d.meters)&&d.meters>0),'binary chair dimensions');
 harness.api.tryProduct('sofa_027_brown');
 const second=harness.api.layout().items.find(i=>i.productID==='sofa_027_brown');
 api.setTransform(second.instanceId,[0,0,0],Math.PI/4);
 assert(api.overlapState().includes(product.instanceId)&&api.overlapState().includes(second.instanceId),'actual registered models participate in overlap checks');
 const saved=plain(harness.api.layout());harness.api.removeProduct(id);harness.api.restore(saved);
 assert(harness.api.layout().items.some(i=>i.productID===id),'saved reset restores product metadata');
 harness.frame();console.log('PASS: registered textured binary chairs retain dimensions, overlap warnings, metadata, and saved-layout restoration.');
})().catch(e=>{console.error(e);process.exit(1)});
