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

function roomContext(width=390,height=310) {
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
      this.value = ''; this.hidden = false; this.clientWidth = width; this.clientHeight = height; this.attributes={}; this.innerHTML="";
      this.classList = {toggle() {}};
    }
    set id(value) { this._id = value; ids.set(value, this); }
    get id() { return this._id; }
    append(...children) { this.children.push(...children); }
    add(value) { this.children.push(value); }
    replaceChildren(...children) { this.children = children; }
    setAttribute(key,value) { this.attributes[key]=String(value); } removeAttribute(key) { delete this.attributes[key]; } remove() { this.removed = true; } click() { this.onclick?.(); }
    addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
    getContext() { return gl; }
    getBoundingClientRect() { return {left: 0, top: 0, width, height}; }
    setPointerCapture() {} blur() { document.activeElement = null; }
  }
  const document = {head: new Element('head'), body: new Element('body'), activeElement: null,
    createElement: tag => new Element(tag), getElementById: id => ids.get(id) || null};
  for (const id of ['c', 'chatHandle', 'axisIndicator', 'rotationHUD', 'rotateLeft', 'rotateRight', 'furnitureDimensions']) { const el = new Element(id === 'c' ? 'canvas' : 'div'); el.id = id; }
  class Image {
    constructor() { this.width = this.height = 2; }
    set src(value) { queueMicrotask(() => value.startsWith('data:image/') ? this.onload() : this.onerror()); }
  }
  const context = vm.createContext({console, document, Image,
    Option: function(text, value) { this.text = text; this.value = value; },
    Float32Array, Uint8Array, Map, Set, Math, Number, Array, Error, Promise,
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    innerWidth: width, innerHeight: height, devicePixelRatio: 1,
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
function checkBounds(editor){
 const safe=editor.dimensionSafeRect();
 for(const d of editor.dimensionAnnotations()){
  assert(d.fontSize>=8&&d.fontSize<=13);assert(d.strokeWidth>=.5&&d.strokeWidth<=1.2);
  assert(d.box.left>=safe.left-1e-6&&d.box.right<=safe.right+1e-6);
  assert(d.box.top>=safe.top-1e-6&&d.box.bottom<=safe.bottom+1e-6);
  const angle=Math.atan2(d.b[1]-d.a[1],d.b[0]-d.a[0])*180/Math.PI;
  assert(Math.abs(Math.sin((angle-d.angle)*Math.PI/180))<1e-7,'number rotation follows its dimension line');
  assert(/^\d+\.\d+″$/.test(d.label),'plain inch number, no axis prefix');
 }
}
(async()=>{
 const a=roomContext(),editor=a.editor;
 const sample=clean(editor.layout());assert.equal(sample.items.length,6);
 assert(!sample.items.some(i=>i.assetId==='window_curtains'));
 assert(!editor.assets.some(i=>i.id==='window_curtains'));
 assert(editor.room.parts.some(p=>p.fixedCurtain),'curtain geometry is in permanent room structure');
 const curtainCount=editor.room.parts.filter(p=>p.fixedCurtain).length;
 const legacy={...sample,items:[...sample.items,{instanceId:'old-curtain',assetId:'window_curtains',position:[42,0,42],yawRadians:1}]};
 editor.loadLayout(legacy);assert.deepEqual(clean(editor.layout()),sample,'old movable curtains are migrated out');
 editor.loadLayout(sample);assert.equal(editor.room.parts.filter(p=>p.fixedCurtain).length,curtainCount,'fixed curtains never duplicate or disappear');
 const chat=editor.chatContext();assert(!chat.objects.some(o=>o.category==='window_curtains'));
 assert.deepEqual(clean(editor.dimensionAnnotations()),[],'dimensions default OFF');
 editor.setInchesEnabled(true);assert.equal(editor.dimensionAnnotations().length,18,'six furniture pieces each have three dimensions');checkBounds(editor);
 a.frame();const overlay=a.ids.get('furnitureDimensions');assert(overlay.innerHTML.includes('<path')&&overlay.innerHTML.includes('<text'));
 assert(!overlay.innerHTML.includes('<rect')&&!overlay.innerHTML.includes('foreignObject'),'no text boxes');
 assert(!html.includes('roomScale')&&!html.includes('overlapHighlight')&&!html.includes('overlap?'),'old scale and red renderer are removed');
 editor.setInchesEnabled(false);a.frame();assert.equal(overlay.innerHTML,'');assert('hidden' in overlay.attributes);
 const poses=[{w:390,h:397,insets:[12,12,12,12]},{w:390,h:844,insets:[112,12,126,12]},{w:430,h:932,insets:[123,12,136,12]},{w:320,h:568,insets:[100,12,116,12]},{w:844,h:390,insets:[72,12,100,12]}];
 for(const p of poses){
  const scene=roomContext(p.w,p.h);scene.editor.setInchesEnabled(true);scene.editor.setDimensionInsets(...p.insets);
  for(const yaw of[-.9,.9,2.1])for(const radius of[3.4,7.5,15]){
   scene.editor.setCamera(yaw,.62,radius);checkBounds(scene.editor);scene.frame();
   assert(!scene.ids.get('furnitureDimensions').innerHTML.includes('NaN'));
  }
  const before=clean(scene.editor.layout());scene.editor.setInchesEnabled(false);assert.deepEqual(clean(scene.editor.layout()),before,'toggle never moves furniture');
 }
 // Perspective scales with actual projected depth and zoom, within readability limits.
 const eye=vm.runInContext('camera()',a.context),forward=vm.runInContext('norm(sub(sceneTarget,camera()))',a.context);
 const near=editor.dimensionStyle(eye.map((v,k)=>v+forward[k]*3)),far=editor.dimensionStyle(eye.map((v,k)=>v+forward[k]*15));
 assert(near.fontSize>far.fontSize&&near.strokeWidth>far.strokeWidth);
 assert.throws(()=>editor.setDimensionInsets(NaN,0,0,0),/Invalid dimension/);
 editor.setDimensionInsets(1000,12,1000,12);editor.setInchesEnabled(true);assert.deepEqual(clean(editor.dimensionAnnotations()),[],'covered view does not leak markers offscreen');
 editor.setDimensionInsets(12,12,12,12);
 // Products added with Try get the same three dimensions, while Reset keeps camera and toggle state.
 await a.api.register(fixture('sofa_007_brown'));a.api.add('sofa_007_brown');
 assert.equal(editor.dimensionAnnotations().filter(d=>d.id==='product:sofa_007_brown').length,3);
 const saved=clean(editor.layout());const bed=saved.items.find(i=>i.assetId==='bed');
 editor.setTransform(bed.instanceId,[.8,.6,.3],1.1);a.api.remove('sofa_007_brown');
 editor.setFurnitureMoveEnabled(true);editor.select(bed.instanceId);editor.setCamera(.8,.72,4.8);const camera=clean(editor.interactionState().camera);
 editor.restoreSavedLayout(saved);assert.deepEqual(clean(editor.layout()),saved);assert.deepEqual(clean(editor.interactionState().camera),camera);
 assert.equal(editor.interactionState().selected,null);assert.equal(editor.interactionState().furnitureMoveEnabled,false);
 assert(editor.dimensionAnnotations().length>0,'inch toggle persists across Reset');
 // Existing structural snapping remains; fixed curtains are never magnetic.
 vm.runInContext(`const originalParts=activeRoomParts;activeRoomParts=[{...room.parts.find(p=>p.fixedCurtain),name:'Wall curtain',fixedCurtain:true}];snapSurfaceCache=null`,a.context);
 assert.equal(editor.snapSurfaces().length,0);
 vm.runInContext(`activeRoomParts=[boxPart('Wall',[2,1,0],[.1,2,2],[1,1,1]),boxPart('Floor',[0,-.025,0],[6,.05,6],[1,1,1])];snapSurfaceCache=null;assetMap.set('test',{parts:[{vertices:[[-.2,0,-.2],[.2,.4,.2]],faces:[]}],objects:[]})`,a.context);
 let item={assetId:'test',position:[1.72,0,0],yawRadians:0};editor.snapToStructure(item,0,[1.6,0,0]);assert(Math.abs(item.position[0]-1.75)<1e-8);
 item={...item,position:[0,.04,0]};editor.snapToStructure(item,1);assert(Math.abs(item.position[1])<1e-8);
 console.log('PASS: inch OFF/ON; six static-curtain-free furniture pieces; legacy migration; angled number-only labels; perspective bounds; viewport/sheet/zoom/orbit containment; Try dimensions; Reset preserving camera; structural-only snapping; red and old scale removed.');
})().catch(error=>{console.error(error);process.exit(1)});
