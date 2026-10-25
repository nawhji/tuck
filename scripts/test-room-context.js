// Executes only the pure geometry bridge; no browser, network, or model API.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync('Tuck/Resources/DemoRoom.html', 'utf8');
function functionSource(name) {
  const start = html.indexOf('function ' + name + '(');
  assert(start >= 0, name);
  const brace = html.indexOf('{', start);
  let depth = 1, end = brace + 1;
  while (depth) { if (html[end] === '{') depth++; if (html[end] === '}') depth--; end++; }
  return html.slice(start, end);
}
const box = {vertices: [[-1,-.5,-.25],[1,.5,.25]]};
const assetMap = new Map([['scan-chair', {label:'Chair', parts:[box]}]]);
const ctx = vm.createContext({assetMap, items:[{instanceId:'chair',assetId:'scan-chair',position:[3,.5,2],yawRadians:Math.PI/2}], selected:'chair', scannedSource:{id:'room',objects:[{id:'chair', category:'chair',label:'My chair',confidence:'high'}]}, room:{parts:[box]}, Math});
vm.runInContext(['boundsOf','world','chatGeometry','chatContext'].map(functionSource).join('\n'), ctx);
const get = () => JSON.parse(vm.runInContext('JSON.stringify(chatContext())',ctx));
let result = get(), item = result.objects[0];
assert.equal(item.label,'My chair');
assert.equal(result.source,'scan_editor');
assert.equal(result.selectedObjectID,'chair');
assert(Math.abs(item.boundsMeters.min[0]-2.75)<1e-6);
assert(Math.abs(item.boundsMeters.max[2]-3)<1e-6);
ctx.items[0].position[0] = 8;
assert(Math.abs(get().objects[0].centerMeters[0]-8)<1e-6, 'unsaved move');
ctx.items=[]; ctx.selected=null;
assert.equal(get().objects.length,0,'removed furniture must stay removed');
ctx.scannedSource=null;
assert.equal(get().source,'sample_editor');
assert.equal(get().structures.length,1);
console.log('PASS: rotated bounds, current moves, selection, labels, removals, sample provenance');
