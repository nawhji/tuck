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
  for (const id of ['c', 'chatHandle', 'axisIndicator', 'rotationHUD', 'rotateLeft', 'rotateRight', 'roomScale', 'roomScaleBar', 'roomScaleLabel']) { const el = new Element(id === 'c' ? 'canvas' : 'div'); el.id = id; }
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
const a=roomContext(),editor=a.editor,run=s=>vm.runInContext(s,a.context);
const sample=clean(editor.layout());
run(`const sampleParts=activeRoomParts;activeRoomParts=[];assetMap.set('test',{label:'Test',parts:[{vertices:[[-.2,0,-.2],[.2,.4,.2]],faces:[]}],objects:[]});`);
const setup=()=>run(`items=[{instanceId:'a',assetId:'test',position:[0,0,0],yawRadians:0},{instanceId:'b',assetId:'test',position:[0,0,0],yawRadians:0},{instanceId:'c',assetId:'test',position:[5,0,0],yawRadians:0},{instanceId:'d',assetId:'test',position:[5,0,0],yawRadians:0}];sync()`);
setup();assert.deepEqual(clean(editor.overlapState()).sort(),['a','b','c','d'],'all independent collision groups are red');
editor.setFurnitureMoveEnabled(false);editor.select(null);assert.deepEqual(clean(editor.overlapState()).sort(),['a','b','c','d'],'red persists after mode off/deselection');
editor.setTransform('a',[-5,0,0],0);assert.deepEqual(clean(editor.overlapState()).sort(),['c','d'],'moving clear updates only that overlap');
editor.setTransform('c',[0,0,0],0);assert.deepEqual(clean(editor.overlapState()).sort(),['b','c'],'new group is red while previous pair clears');
editor.setTransform('d',[0,0,0],0);assert.deepEqual(clean(editor.overlapState()).sort(),['b','c','d'],'every member in a connected collision group is red');
editor.setTransform('c',[5,0,0],0);editor.setTransform('d',[-7,0,0],0);assert.deepEqual(clean(editor.overlapState()),[],'moving clear removes red');
// Rotation-aware collision: thin parallel diagonal boxes can have intersecting AABBs without a real overlap.
const box=(c,yaw=0)=>({center:c,half:[1,.5,.1],axes:[[Math.cos(yaw),0,-Math.sin(yaw)],[0,1,0],[Math.sin(yaw),0,Math.cos(yaw)]]});
assert(!editor.boxesOverlap(box([0,.5,0],Math.PI/4),box([.3,.5,.3],Math.PI/4)));
assert(editor.boxesOverlap(box([0,.5,0]),box([0,.5,0],Math.PI/2)));
// A finite wall volume and a normal floor: flush contact is valid, penetration is red.
run(`activeRoomParts=[boxPart('Wall',[2,1,0],[.1,2,2],[.9,.9,.9]),boxPart('Floor',[0,-.025,0],[6,.05,6],[.7,.7,.7])];snapSurfaceCache=null;wallCollisionCache=null;items=[{instanceId:'a',assetId:'test',position:[1.75,0,0],yawRadians:0}];sync()`);
assert.deepEqual(clean(editor.overlapState()),[],'flush wall contact is allowed');
editor.setTransform('a',[1.77,0,0],0);assert.deepEqual(clean(editor.overlapState()),['a'],'actual wall penetration is red');
editor.setTransform('a',[3,0,0],0);assert.deepEqual(clean(editor.overlapState()),[],'finite wall only, no infinite-plane warning');
editor.setTransform('a',[0,-.04,0],0);assert.deepEqual(clean(editor.overlapState()),[],'floor is not a red-warning collider');
let moved={instanceId:'a',assetId:'test',position:[1.72,0,0],yawRadians:0};
assert.notEqual(editor.snapToStructure(moved,0,[1.6,0,0]),null);assert(Math.abs(moved.position[0]-1.75)<1e-8);
assert(!editor.overlapsWall(editor.furnitureBox(moved)),'magnetic flush contact is not red');
moved={...moved,position:[1.6,0,0]};assert.equal(editor.snapToStructure(moved,0),null,'dragging beyond 6.5 cm releases snap');
moved={...moved,position:[0,.04,0]};editor.snapToStructure(moved,1);assert(Math.abs(moved.position[1])<1e-8);assert.equal(moved.position[0],0);
// A tiny item contained fully within wall thickness must also count as penetrating.
run(`assetMap.set('tiny',{parts:[{vertices:[[-.01,0,-.01],[.01,.02,.01]],faces:[]}],objects:[]})`);
assert(editor.overlapsWall(editor.furnitureBox({assetId:'tiny',position:[2,.5,0],yawRadians:0})));
run(`activeRoomParts=[boxPart('Wall',[2,1,-.75],[.1,2,.5],[1,1,1]),boxPart('Wall',[2,1,.75],[.1,2,.5],[1,1,1])];snapSurfaceCache=null;wallCollisionCache=null`);
assert(!editor.overlapsWall(editor.furnitureBox({assetId:'test',position:[2,0,0],yawRadians:0})),'doorway gap is not a wall');
moved={assetId:'test',position:[1.72,0,0],yawRadians:0};assert.equal(editor.snapToStructure(moved,0),null,'doorway is not magnetic');
run('activeRoomParts=[];snapSurfaceCache=null');moved={assetId:'test',position:[.04,0,0],yawRadians:0};assert.equal(editor.snapToStructure(moved,0),null,'other furniture is never magnetic');
run('activeRoomParts=sampleParts;');editor.loadLayout(sample);
// The scale bar is a 1/2/5 × 10^n inch reference at the floor center, in CSS pixels.
for(const yaw of [-.72,.9,2.2]){
 let previous=0;
 for(const radius of [3.4,7.5,15]){
  editor.setCamera(yaw,.62,radius);const scale=clean(editor.floorScale());
  assert(scale&&Number.isFinite(scale.inches)&&scale.inches>0);
  const power=10**Math.floor(Math.log10(scale.inches)),mantissa=scale.inches/power;
  assert([1,2,5].some(v=>Math.abs(v-mantissa)<1e-8));
  assert(scale.pixels>=39.99&&scale.pixels<=100.01,'readable screen-sized bar');
  assert(Math.abs(scale.pixels-scale.pixelsPerInch*scale.inches)<1e-8);
  assert(scale.inches>=previous,'zooming out shows a larger physical reference');previous=scale.inches;
  a.frame();assert.equal(a.ids.get('roomScaleLabel').textContent,scale.label);
 }
}
(async()=>{
 await a.api.register(fixture('sofa_007_brown'));a.api.add('sofa_007_brown');
 const saved=clean(editor.layout()),bed=saved.items.find(i=>i.assetId==='bed');
 editor.setTransform(bed.instanceId,[.8,.6,.3],1.1);a.api.remove('sofa_007_brown');
 editor.setFurnitureMoveEnabled(true);editor.select(bed.instanceId);editor.setCamera(.8,.72,4.8);
 const camera=clean(editor.interactionState().camera);
 editor.restoreSavedLayout(saved);
 assert.deepEqual(clean(editor.layout()),saved,'Reset restores saved furniture including products');
 assert.deepEqual(clean(editor.interactionState().camera),camera,'Reset preserves viewpoint');
 assert.equal(editor.interactionState().selected,null);assert.equal(editor.interactionState().furnitureMoveEnabled,false);
 // Fresh scans also keep their viewpoint when resetting (loadScannedRoom normally resets it).
 const matrix=(x,y,z)=>[1,0,0,0,0,1,0,0,0,0,1,0,x,y,z,1];
 const scan={schemaVersion:1,id:'scan',units:'meters',coordinateSystem:'right-handed-y-up',transformLayout:'column-major',walls:[{id:'wall',kind:'wall',transform:matrix(0,1,-2),dimensions:{width:4,height:2,depth:0}}],doors:[],windows:[],openings:[],floors:[],objects:[{id:'chair',category:'chair',transform:matrix(0,.5,0),dimensions:{width:.6,height:1,depth:.6}}]};
 editor.loadScannedRoom(scan);const scanned=clean(editor.layout());editor.setCamera(1,.9,5);
 const before=clean(editor.interactionState().camera);editor.restoreSavedLayout(scanned);
 assert.deepEqual(clean(editor.interactionState().camera),before);
 assert.deepEqual(clean(editor.layout()),scanned);
 console.log('PASS: all overlapping groups red after deselection; furniture SAT; finite wall penetration vs flush/floor/doorway; contained-wall collision; structural-only snapping; 1/2/5 inch scale across zoom and orbit; saved/product/scan Reset preserving camera.');
})().catch(error=>{console.error(error);process.exit(1)});
