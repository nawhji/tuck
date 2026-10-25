const detachedControls=new Map();const $=id=>{let e=document.getElementById(id);if(e)return e;if(!detachedControls.has(id)){e=document.createElement(['asset','selected'].includes(id)?'select':'input');detachedControls.set(id,e)}return detachedControls.get(id)},canvas=$('c'),gl=canvas.getContext('webgl',{antialias:true,alpha:false});
if(!gl){$('status').textContent='Open in a browser that supports WebGL.';throw Error('WebGL unavailable')}
const vs=`attribute vec3 aPosition;attribute vec3 aNormal;attribute vec2 aUV;attribute vec4 aTangent;varying vec4 vTangent;varying vec2 vUV;uniform mat4 uMVP;uniform mat4 uModel;uniform mat4 uLight;varying vec3 vNormal;varying vec3 vWorld;varying vec4 vShadow;void main(){vTangent=vec4(mat3(uModel)*aTangent.xyz,aTangent.w);vUV=aUV;vec4 w=uModel*vec4(aPosition,1.);vWorld=w.xyz;vNormal=mat3(uModel)*aNormal;vShadow=uLight*w;gl_Position=uMVP*w;}`;
const indexedGeometrySupported=!!gl.getExtension('OES_element_index_uint');
const normalMapsSupported=!!gl.getExtension('OES_standard_derivatives');
const fs=`${normalMapsSupported?'#extension GL_OES_standard_derivatives : enable\n#define TUCK_NORMAL_MAPS 1\n':''}precision highp float;
varying vec2 vUV;uniform sampler2D uMap;uniform bool uHasMap;uniform vec3 uColor;uniform vec3 uEye;uniform float uKind;uniform float uRoughness;uniform sampler2D uShadow;
varying vec3 vNormal;varying vec3 vWorld;varying vec4 vShadow;
uniform bool uOriginalAppearance;
varying vec4 vTangent;uniform bool uHasTangents;
uniform sampler2D uMetallicMap;uniform bool uHasMetallicMap;uniform float uMetallic;
uniform sampler2D uNormalMap;uniform bool uHasNormalMap;uniform float uNormalStrength;
uniform sampler2D uRoughnessMap;uniform bool uHasRoughnessMap;
#ifdef TUCK_NORMAL_MAPS
vec3 mappedNormal(vec3 n){
 vec3 q1=dFdx(vWorld),q2=dFdy(vWorld);vec2 t1=dFdx(vUV),t2=dFdy(vUV);
 vec3 p2=cross(q2,n),p1=cross(n,q1),t=p2*t1.x+p1*t2.x,b=p2*t1.y+p1*t2.y;
 float scale=max(dot(t,t),dot(b,b));if(scale<.000000000001)return n;
 vec3 detail=texture2D(uNormalMap,vUV).xyz*2.-1.;detail.xy*=uNormalStrength;
 return normalize(mat3(t*inversesqrt(scale),b*inversesqrt(scale),n)*detail);
}
#endif
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float unpackDepth(vec3 c){return dot(c,vec3(1.,1./255.,1./65025.));}
float visibility(vec3 normal){vec3 q=vShadow.xyz/vShadow.w*.5+.5;if(q.x<0.||q.x>1.||q.y<0.||q.y>1.||q.z<0.||q.z>1.)return 1.;float bias=max(.0007,.002*(1.-max(dot(normal,normalize(vec3(-3.,6.,4.))),0.)));float shade=0.;for(int x=-2;x<=2;x++)for(int y=-2;y<=2;y++){vec2 off=vec2(float(x),float(y))*(1.5/2048.);float d=unpackDepth(texture2D(uShadow,q.xy+off).rgb);shade+=q.z-bias<=d?1.:0.;}return shade/25.;}
void main(){
// Only the three product chairs use neutral studio illumination. Their source
// maps/tangents are retained; room shadow-map acne and procedural grain are not
// multiplied onto the upholstery. They still CAST shadows onto the room.
if(uOriginalAppearance){
 vec3 source=uColor;if(uHasMap)source*=texture2D(uMap,vUV).rgb;
 vec3 n=normalize(vNormal);if(!gl_FrontFacing)n=-n;
 if(uHasNormalMap&&uHasTangents){
  vec3 t=normalize(vTangent.xyz-n*dot(n,vTangent.xyz));
  vec3 b=cross(n,t)*vTangent.w;
  vec3 detail=texture2D(uNormalMap,vUV).xyz*2.-1.;detail.xy*=uNormalStrength;
  n=normalize(mat3(t,b,n)*detail);
 }
 vec3 v=normalize(uEye-vWorld),l=normalize(vec3(-.4,.85,.6));
 float rough=clamp(uRoughness*(uHasRoughnessMap?texture2D(uRoughnessMap,vUV).r:1.),.05,1.);
 float metal=clamp(uMetallic*(uHasMetallicMap?texture2D(uMetallicMap,vUV).r:1.),0.,1.);
 // Color alone is sRGB. Normal, roughness and metal maps are linear data.
 vec3 base=mix(source/12.92,pow((source+.055)/1.055,vec3(2.4)),step(vec3(.04045),source));
 vec3 f0=mix(vec3(.04),base,metal);
 vec3 fresnel=f0+(1.-f0)*pow(1.-max(dot(n,v),0.),5.);
 vec3 reflected=reflect(-v,n);
 float softbox=pow(max(dot(reflected,l),0.),mix(48.,2.,rough));
 float studio=.35+.65*(n.y*.5+.5)+softbox*(1.-rough)*1.4;
 vec3 col=base*(1.-metal)*(.76+.24*max(dot(n,l),0.))+fresnel*studio;
 col=mix(col*12.92,1.055*pow(max(col,vec3(0.)),vec3(1./2.4))-.055,step(vec3(.0031308),col));
 gl_FragColor=vec4(clamp(col,0.,1.),1.);return;
}
if(uKind>4.5){float light=.65+.35*max(dot(normalize(vNormal),normalize(vec3(-.4,.85,.35))),0.);gl_FragColor=vec4(uColor*light,1.);return;}vec3 n=normalize(vNormal);if(!gl_FrontFacing)n=-n;
#ifdef TUCK_NORMAL_MAPS
if(uHasNormalMap)n=mappedNormal(n);
#endif
vec3 base=uColor;if(uHasMap)base*=texture2D(uMap,vUV).rgb;vec2 uv=abs(n.y)>.6?vWorld.xz:(abs(n.x)>.6?vWorld.zy:vWorld.xy);
if(uKind>.5&&uKind<1.5){float grain=noise(vec2(uv.x*5.+sin(uv.y*2.)*.35,uv.y*120.));float fine=noise(uv*vec2(20.,600.));base*=.94+.065*grain+.035*fine;}
if(uKind>1.5&&uKind<2.5){float weave=sin(uv.x*800.)*sin(uv.y*800.);base*=.975+.018*weave+.025*noise(uv*90.);}
vec3 l=normalize(vec3(-3.,6.,4.)),v=normalize(uEye-vWorld),h=normalize(l+v);float diff=max(dot(n,l),0.),shadow=visibility(n);float hemi=mix(.63,.94,n.y*.5+.5);vec3 light=vec3(1.02,1.0,.95)*hemi+vec3(1.0,.97,.89)*diff*.63*shadow;
float rough=clamp(uRoughness*(uHasRoughnessMap?texture2D(uRoughnessMap,vUV).r:1.),.05,1.);float spec=pow(max(dot(n,h),0.),mix(110.,8.,rough))*(1.-rough)*.35*shadow;
vec3 col=pow(base,vec3(2.2))*light+spec;
if(uKind>2.5&&uKind<3.5)col+=vec3(.10,.12,.13)*pow(1.-max(dot(n,v),0.),3.);
if(uKind>3.5){vec3 reflected=reflect(-v,n);vec3 env=mix(vec3(.46,.42,.35),vec3(.83,.91,.95),smoothstep(-.35,.4,reflected.y));col=mix(col,env*.75,.38)+spec;}
col=vec3(1.)-exp(-col*1.35);gl_FragColor=vec4(pow(col,vec3(1./2.2)),1.);
}
`;
function shader(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s}
const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vs));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fs));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));gl.useProgram(program);
const ap=gl.getAttribLocation(program,'aPosition'),an=gl.getAttribLocation(program,'aNormal'),at=gl.getAttribLocation(program,'aUV'),ut=gl.getUniformLocation(program,'uMap'),uh=gl.getUniformLocation(program,'uHasMap'),um=gl.getUniformLocation(program,'uMVP'),ud=gl.getUniformLocation(program,'uModel'),uc=gl.getUniformLocation(program,'uColor');
const un=gl.getUniformLocation(program,'uNormalMap'),uhn=gl.getUniformLocation(program,'uHasNormalMap'),uns=gl.getUniformLocation(program,'uNormalStrength'),urt=gl.getUniformLocation(program,'uRoughnessMap'),uhr=gl.getUniformLocation(program,'uHasRoughnessMap');
const uo=gl.getUniformLocation(program,'uOriginalAppearance');
const ag=gl.getAttribLocation(program,'aTangent'),ugt=gl.getUniformLocation(program,'uHasTangents');
const umt=gl.getUniformLocation(program,'uMetallicMap'),uhm=gl.getUniformLocation(program,'uHasMetallicMap'),umetal=gl.getUniformLocation(program,'uMetallic');
function sub(a,b){return a.map((v,i)=>v-b[i])}function dot(a,b){return a.reduce((s,v,i)=>s+v*b[i],0)}function cross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}function norm(a){let l=Math.hypot(...a);return a.map(v=>v/l)}
function buffer(arr){let b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(arr),gl.STATIC_DRAW);return b}
function floats(base64){const raw=atob(base64),bytes=new Uint8Array(raw.length);for(let k=0;k<raw.length;k++)bytes[k]=raw.charCodeAt(k);if(bytes.byteLength%4)throw Error('Invalid geometry buffer');return new Float32Array(bytes.buffer)}
function upload(p){
 if(p.positions){
  const {positions,normals,uvs,indices,tangents,texture,normalTexture,roughnessTexture,metallicTexture,...meta}=p;
  let v=floats(positions),n=floats(normals),uv=floats(uvs),t=tangents?floats(tangents):null;
  let ix=indices?new Uint32Array(floats(indices).buffer):null;
  if(!v.length||v.length%3||(!ix&&v.length%9)||n.length!==v.length||uv.length!==v.length/3*2||
     !v.every(Number.isFinite)||!n.every(Number.isFinite)||!uv.every(Number.isFinite)||
     (t&&(t.length!==v.length/3*4||!t.every(Number.isFinite)))||
     (ix&&(!ix.length||ix.length%3||!ix.every(i=>i<v.length/3))))throw Error('Invalid chair geometry');
  if(ix&&!indexedGeometrySupported){
   const expand=(a,size)=>{const result=new Float32Array(ix.length*size);for(let k=0;k<ix.length;k++)for(let j=0;j<size;j++)result[k*size+j]=a[ix[k]*size+j];return result};
   v=expand(v,3);n=expand(n,3);uv=expand(uv,2);if(t)t=expand(t,4);ix=null;
  }
  let indexBuffer=null;if(ix){indexBuffer=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,ix,gl.STATIC_DRAW)}
  return {...meta,positionsArray:v,indicesArray:ix,indexBuffer,v:buffer(v),n:buffer(n),uv:buffer(uv),tangent:t?buffer(t):null,count:ix?ix.length:v.length/3};
 }
 let v=[],n=[];for(let f of p.faces)for(let k=1;k<f.length-1;k++){let t=[p.vertices[f[0]],p.vertices[f[k]],p.vertices[f[k+1]]],nn=cross(sub(t[1],t[0]),sub(t[2],t[0]));if(Math.hypot(...nn)<1e-9)continue;nn=norm(nn);for(let j=0;j<3;j++){v.push(...t[j]);let ix=[f[0],f[k],f[k+1]][j];n.push(...(p.vertexNormals?.[ix]||nn))}}return{...p,v:buffer(v),n:buffer(n),count:v.length/3}
}
function eachVertex(part,fn){if(part.positionsArray){const p=part.positionsArray;for(let k=0;k<p.length;k+=3)fn([p[k],p[k+1],p[k+2]])}else for(const v of part.vertices)fn(v)}
function eachTriangle(part,fn){
 if(part.positionsArray){const p=part.positionsArray,ix=part.indicesArray,point=i=>[p[i*3],p[i*3+1],p[i*3+2]];
  if(ix){for(let k=0;k<ix.length;k+=3)fn(point(ix[k]),point(ix[k+1]),point(ix[k+2]))}
  else for(let k=0;k<p.length;k+=9)fn([p[k],p[k+1],p[k+2]],[p[k+3],p[k+4],p[k+5]],[p[k+6],p[k+7],p[k+8]]);
 }else for(const f of part.faces)for(let k=1;k<f.length-1;k++)fn(part.vertices[f[0]],part.vertices[f[k]],part.vertices[f[k+1]])
}
function drawGeometry(p){if(p.indexBuffer){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,p.indexBuffer);gl.drawElements(gl.TRIANGLES,p.count,gl.UNSIGNED_INT,0)}else gl.drawArrays(gl.TRIANGLES,0,p.count)}
function localBounds(asset){if(!asset.bounds){const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(const p of asset.parts)eachVertex(p,v=>{for(let k=0;k<3;k++){lo[k]=Math.min(lo[k],v[k]);hi[k]=Math.max(hi[k],v[k])}});asset.bounds=[lo,hi]}return asset.bounds}
let roomObjects=room.parts.map(upload),assetMap=new Map(assets.map(a=>[a.id,{...a,objects:a.parts.map(upload)}]));
function mul(a,b){let r=new Float32Array(16);for(let c=0;c<4;c++)for(let row=0;row<4;row++)for(let k=0;k<4;k++)r[c*4+row]+=a[k*4+row]*b[c*4+k];return r}
function look(eye,at){let z=norm(sub(eye,at)),x=norm(cross([0,1,0],z)),y=cross(z,x);return new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,eye),-dot(y,eye),-dot(z,eye),1])}
function perspective(fov,aspect,near,far){let f=1/Math.tan(fov/2),q=1/(near-far);return new Float32Array([f/aspect,0,0,0,0,f,0,0,0,0,(far+near)*q,-1,0,0,2*far*near*q,0])}
function model(item){let c=Math.cos(item.yawRadians),s=Math.sin(item.yawRadians),[x,y,z]=item.position;return new Float32Array([c,0,-s,0,0,1,0,0,s,0,c,0,x,y,z,1])}
const ul=gl.getUniformLocation(program,'uLight'),us=gl.getUniformLocation(program,'uShadow'),uk=gl.getUniformLocation(program,'uKind'),ur=gl.getUniformLocation(program,'uRoughness'),ue=gl.getUniformLocation(program,'uEye');
const identity=model({position:[0,0,0],yawRadians:0});
let items=[],selected=null,serial=0,mode='orbit',yaw=-.72,pitch=.62,radius=7.5,autoWalls=true,showRoof=true,dirty=true;
const chosen=()=>items.find(i=>i.instanceId===selected);
function message(s){$('status').textContent=s}
function sync(){updateRotationHUD();updateFurnitureUI();const pick=$('selected');pick.replaceChildren();if(!items.length){let o=new Option('No furniture added','');pick.add(o)}for(let i of items)pick.add(new Option(assetMap.get(i.assetId).label+' · '+i.instanceId,i.instanceId));pick.value=selected||'';const i=chosen();for(let id of ['x','y','z','angle','left','right','remove','restore'])$(id).disabled=!i;for(let [id,k] of [['x',0],['y',1],['z',2]])$(id).value=i?Number(i.position[k].toFixed(3)):'';$('angle').value=i?Number((i.yawRadians*180/Math.PI).toFixed(1)):'';dirty=true}
function add(id){const a=assetMap.get(id);if(!a)return;let item={instanceId:id+'_'+(++serial),assetId:id,position:[...a.defaultTransform.position],yawRadians:0};items.push(item);selected=item.instanceId;sync();message(a.label+' added.');return item}
for(let a of assets)$('asset').add(new Option(a.label+(a.optional?' (Optional)':''),a.id));
$('add').onclick=()=>add($('asset').value);
$('reference').onclick=()=>{items=[];selected=null;for(let a of assets)if(!a.optional)add(a.id);message('Original layout restored.');sync()};
$('selected').onchange=()=>{selected=$('selected').value;sync()};
function setMode(m){mode=m;$('orbit').classList.toggle('active',m==='orbit');$('move').classList.toggle('active',m==='move');canvas.style.cursor=m==='move'?'grab':'default'}
$('orbit').onclick=()=>setMode('orbit');$('move').onclick=()=>setMode('move');
for(let [id,k] of [['x',0],['y',1],['z',2]])$(id).onchange=()=>{let i=chosen(),v=Number($(id).value);if(i&&Number.isFinite(v)){i.position[k]=v;sync()}};
$('angle').onchange=()=>{let i=chosen(),v=Number($('angle').value);if(i&&Number.isFinite(v)){i.yawRadians=v*Math.PI/180;sync()}};
function rotate(deg){let i=chosen();if(i){i.yawRadians+=deg*Math.PI/180;sync()}}$('left').onclick=()=>rotate(-15);$('right').onclick=()=>rotate(15);
$('restore').onclick=()=>{let i=chosen();if(i){i.position=[...assetMap.get(i.assetId).defaultTransform.position];i.yawRadians=0;sync();commitLayout()}};
$('remove').onclick=()=>{items=items.filter(i=>i.instanceId!==selected);selected=items.at(-1)?.instanceId||null;sync()};
$('empty').onclick=()=>{items=[];selected=null;sync();message('Room and closet rail only.')};
function layout(){return{version:1,units:'meters',upAxis:'Y',items:items.map(i=>({...i,label:itemName(i),position:[...i.position]})),...(scannedSource?{scannedRoom:JSON.parse(JSON.stringify(scannedSource))}:{})}}
function loadLayout(data){
 if(data.scannedRoom)validateScan(data.scannedRoom);
 if(data.version!==1||data.units!=='meters'||data.upAxis!=='Y'||!Array.isArray(data.items)||data.items.length>100)throw Error('Unsupported layout file.');
 const validAssets=new Set([...assets.map(a=>a.id),...Array.from(assetMap.values()).filter(a=>a.productID).map(a=>a.id),...(data.scannedRoom?data.scannedRoom.objects.map(e=>'scan-'+e.id):[])]);
 const ids=new Set(),products=new Set(),next=data.items.map((i,k)=>{
  if(!validAssets.has(i.assetId)||!Array.isArray(i.position)||i.position.length!==3||!i.position.every(v=>typeof v==='number'&&Number.isFinite(v)&&Math.abs(v)<100)||!Number.isFinite(i.yawRadians))throw Error('Invalid furniture or coordinates.');
  const id=typeof i.instanceId==='string'&&i.instanceId.length>0&&i.instanceId.length<=120?i.instanceId:i.assetId+'_'+k;
  if(ids.has(id))throw Error('Duplicate furniture ID.');ids.add(id);
  const productID=assetMap.get(i.assetId)?.productID||null;
  if(i.productID&&i.productID!==productID||productID&&products.has(productID))throw Error('Invalid or duplicate product.');if(productID)products.add(productID);
  const label=typeof i.label==='string'&&i.label.trim()?Array.from(i.label.trim()).slice(0,80).join(''):null;
  return{instanceId:id,assetId:i.assetId,...(label?{label}:{}),position:[...i.position],yawRadians:i.yawRadians,...(productID?{productID}:{})}
 });
 if(data.scannedRoom)loadScannedRoom(data.scannedRoom);else restoreDemoGeometry();
 items=next;serial=Math.max(serial,...items.map(i=>Number(i.instanceId.match(/_(\d+)$/)?.[1])||0));selected=null;showAxis(null);sync()
}
$('save').onclick=()=>{let u=URL.createObjectURL(new Blob([JSON.stringify(layout(),null,2)],{type:'application/json'})),a=document.createElement('a');a.href=u;a.download='tuck-layout.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);message('Layout saved.')};
$('load').onclick=()=>$('file').click();$('file').onchange=async e=>{try{let file=e.target.files[0];if(!file)return;if(file.size>1000000)throw Error('Layout file is too large.');loadLayout(JSON.parse(await file.text()));message('Layout loaded.')}catch(err){message(err.message)}finally{e.target.value=''}};
// Fit the fixed room bounds in both portrait and landscape viewports.
let roomBounds=(()=>{const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(const part of room.parts)for(const v of part.vertices)for(let k=0;k<3;k++){lo[k]=Math.min(lo[k],v[k]);hi[k]=Math.max(hi[k],v[k])}const corners=[];for(let mask=0;mask<8;mask++)corners.push(lo.map((v,k)=>(mask&(1<<k))?hi[k]:v));return corners})();
function camera(){const dir=[Math.cos(pitch)*Math.sin(yaw),Math.sin(pitch),Math.cos(pitch)*Math.cos(yaw)],f=dir.map(v=>-v),right=norm(cross(f,[0,1,0])),up=cross(right,f),rect=canvas.getBoundingClientRect(),aspect=Math.max(.1,rect.width/Math.max(1,rect.height)),t=Math.tan(.73/2);let fit=7.5;for(const corner of roomBounds){const q=sub(corner,sceneTarget);fit=Math.max(fit,dot(q,dir)+Math.max(Math.abs(dot(q,right))/(t*aspect*.88),Math.abs(dot(q,up))/(t*.88)))}const distance=fit*radius/7.5;return dir.map((v,k)=>v*distance+sceneTarget[k])}
function ray(x,y){let r=canvas.getBoundingClientRect(),eye=camera(),f=norm(sub(sceneTarget,eye)),right=norm(cross(f,[0,1,0])),up=cross(right,f),xx=(2*(x-r.left)/r.width-1)*Math.tan(.73/2)*r.width/r.height,yy=(1-2*(y-r.top)/r.height)*Math.tan(.73/2);return{origin:eye,dir:norm(f.map((v,k)=>v+right[k]*xx+up[k]*yy))}}
function world(v,i){let c=Math.cos(i.yawRadians),s=Math.sin(i.yawRadians);return[c*v[0]+s*v[2]+i.position[0],v[1]+i.position[1],-s*v[0]+c*v[2]+i.position[2]]}
function triangleHit(r,a,b,c){let e1=sub(b,a),e2=sub(c,a),p=cross(r.dir,e2),det=dot(e1,p);if(Math.abs(det)<1e-8)return Infinity;let t=sub(r.origin,a),u=dot(t,p)/det;if(u<0||u>1)return Infinity;let q=cross(t,e1),v=dot(r.dir,q)/det;if(v<0||u+v>1)return Infinity;let d=dot(e2,q)/det;return d>.001?d:Infinity}
function hitsBounds(r,item){const c=Math.cos(item.yawRadians),s=Math.sin(item.yawRadians),o=sub(r.origin,item.position),origin=[c*o[0]-s*o[2],o[1],s*o[0]+c*o[2]],d=r.dir,dir=[c*d[0]-s*d[2],d[1],s*d[0]+c*d[2]],bounds=localBounds(assetMap.get(item.assetId));let near=0,far=Infinity;for(let k=0;k<3;k++){if(Math.abs(dir[k])<1e-8){if(origin[k]<bounds[0][k]||origin[k]>bounds[1][k])return false;continue}let a=(bounds[0][k]-origin[k])/dir[k],b=(bounds[1][k]-origin[k])/dir[k];near=Math.max(near,Math.min(a,b));far=Math.min(far,Math.max(a,b));if(far<near)return false}return true}
function pick(r){let best=null,dist=Infinity;for(const i of items){if(!hitsBounds(r,i))continue;for(const p of assetMap.get(i.assetId).parts)eachTriangle(p,(a,b,c)=>{const d=triangleHit(r,world(a,i),world(b,i),world(c,i));if(d<dist){dist=d;best=i}})}return best?{item:best,point:r.origin.map((v,k)=>v+dist*r.dir[k])}:null}
function plane(r,height){if(Math.abs(r.dir[1])<1e-5)return null;let t=(height-r.origin[1])/r.dir[1];return t>0?r.origin.map((v,k)=>v+t*r.dir[k]):null}
// World-axis movement. The furniture's geometric center is a hidden pivot.
const axisVectors=[[1,0,0],[0,1,0],[0,0,1]],axisNames=['X','Y','Z'];
let activeAxis=null,activeDirection=1,pinchGesture=false;
const axisBadge=document.getElementById('axisIndicator');
function boundsCenter(item){const bounds=localBounds(assetMap.get(item.assetId));return world(bounds[0].map((v,k)=>(v+bounds[1][k])/2),item)}
function project(point){const rect=canvas.getBoundingClientRect(),eye=camera(),f=norm(sub(sceneTarget,eye)),right=norm(cross(f,[0,1,0])),up=cross(right,f),d=sub(point,eye),depth=dot(d,f),t=Math.tan(.73/2);if(depth<=.05)return null;return[rect.left+rect.width/2+dot(d,right)*rect.height/(2*t*depth),rect.top+rect.height/2-dot(d,up)*rect.height/(2*t*depth)]}
function screenAxis(center,axis){const v=axisVectors[axis],a=project(center.map((p,k)=>p-v[k]*.5)),b=project(center.map((p,k)=>p+v[k]*.5));if(!a||!b)return null;const delta=[b[0]-a[0],b[1]-a[1]],length=Math.hypot(...delta);return length>=8?{delta,length,unit:delta.map(x=>x/length)}:null}
function inferAxis(center,dx,dy){const length=Math.hypot(dx,dy);if(length<9)return null;let best=null,score=-1;for(let axis=0;axis<3;axis++){const s=screenAxis(center,axis);if(!s)continue;const alignment=Math.abs((dx*s.unit[0]+dy*s.unit[1])/length);if(alignment>score){score=alignment;best=axis}}return best}
function axisParameter(pointerRay,center,axis){const direction=axisVectors[axis],w=sub(center,pointerRay.origin),b=dot(direction,pointerRay.dir),denom=1-b*b;if(denom<.003)return null;return(b*dot(pointerRay.dir,w)-dot(direction,w))/denom}
function showAxis(axis){activeAxis=axis;if(axisBadge){axisBadge.hidden=axis===null;axisBadge.textContent=axis===null?'':'Move '+axisNames[axis]}dirty=true}
function arrowPart(axis){const vertices=[],faces=[],a=axisVectors[axis],b=axisVectors[(axis+1)%3],c=axisVectors[(axis+2)%3],N=24;
 function ring(t,r){const first=vertices.length;for(let k=0;k<N;k++){const angle=k*2*Math.PI/N;vertices.push(a.map((v,j)=>v*t+b[j]*Math.cos(angle)*r+c[j]*Math.sin(angle)*r))}return first}
 const start=ring(0,.012),end=ring(.84,.012),head=ring(.84,.035),tip=vertices.length;vertices.push([...a]);
 for(let k=0;k<N;k++){const j=(k+1)%N;faces.push([start+k,start+j,end+j,end+k],[head+k,head+j,tip],[head+j,head+k,end+k,end+j])}
 faces.push(Array.from({length:N},(_,i)=>start+N-1-i));
 for(const face of faces){const pts=face.map(i=>vertices[i]),n=cross(sub(pts[1],pts[0]),sub(pts[2],pts[0])),center=pts[0].map((_,i)=>pts.reduce((sum,p)=>sum+p[i],0)/pts.length),radial=center.map((v,i)=>v-a[i]*dot(center,a));const want=Math.hypot(...radial)>.0001?radial:a.map(v=>-v);if(dot(n,want)<0)face.reverse()}
 return{name:'MovementArrow'+axisNames[axis],vertices,faces,color:[.27,.29,.31],wall:null,materialKind:5,roughness:.9}
}
const arrowObjects=axisVectors.map((_,axis)=>[upload(arrowPart(axis))]);
function furnitureAxisLengths(item){const asset=assetMap.get(item.assetId);if(asset.axisExtentCache?.yaw===item.yawRadians)return asset.axisExtentCache.lengths;const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity],rotated={position:[0,0,0],yawRadians:item.yawRadians};for(const part of asset.parts)eachVertex(part,vertex=>{const point=world(vertex,rotated);for(let k=0;k<3;k++){lo[k]=Math.min(lo[k],point[k]);hi[k]=Math.max(hi[k],point[k])}});const lengths=lo.map((v,k)=>hi[k]-v);asset.axisExtentCache={yaw:item.yawRadians,lengths};return lengths}
function gizmoTransform(){const item=chosen();if(!item||activeAxis===null)return null;const center=boundsCenter(item),axisLength=furnitureAxisLengths(item)[activeAxis],scale=axisLength*.6;if(!(scale>0))return null;const screen=screenAxis(center,activeAxis),normal=screen?[-screen.unit[1],screen.unit[0]]:[1,0],otherAxes=[0,1,2].filter(k=>k!==activeAxis),projectedWidths=otherAxes.map(k=>{const v=axisVectors[k],a=project(center.map((p,j)=>p-v[j]*.5)),b=project(center.map((p,j)=>p+v[j]*.5));return a&&b?(b[0]-a[0])*normal[0]+(b[1]-a[1])*normal[1]:0}),pixelsPerMeter=Math.hypot(...projectedWidths),crossScale=pixelsPerMeter>1e-6?2.5/(.024*pixelsPerMeter):1,sizes=[crossScale,crossScale,crossScale];sizes[activeAxis]=scale*activeDirection;return{center,scale,crossScale,shaftPixels:2.5,axisLength,direction:activeDirection,matrix:new Float32Array([sizes[0],0,0,0,0,sizes[1],0,0,0,0,sizes[2],0,...center,1])}}
function drawAxisGizmo(eye){const g=gizmoTransform();if(!g)return;gl.clear(gl.DEPTH_BUFFER_BIT);draw(arrowObjects[activeAxis],g.matrix,eye)}
const pointers=new Map();let dragging=null,lastPinch=null,orbitStart=null;
let furnitureMoveEnabled=false;
function setFurnitureMoveEnabled(enabled){furnitureMoveEnabled=!!enabled;dragging=null;orbitStart=null;lastPinch=null;pinchGesture=false;pointers.clear();selected=null;showAxis(null);canvas.style.cursor='default';sync()}
canvas.addEventListener('pointerdown',e=>{
 canvas.setPointerCapture(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);lastPinch=null;
 if(pointers.size>1){if(dragging)commitLayout();dragging=null;orbitStart=null;pinchGesture=true;showAxis(null);return}
 pinchGesture=false;const hit=furnitureMoveEnabled?pick(ray(e.clientX,e.clientY)):null;showAxis(null);
 if(hit){selected=hit.item.instanceId;const center=boundsCenter(hit.item);dragging={id:selected,start:[e.clientX,e.clientY],position:[...hit.item.position],center,axis:null,startParameter:null};orbitStart=null;canvas.style.cursor='grabbing';sync()}
 else{dragging=null;orbitStart=[e.clientX,e.clientY]}
});
canvas.addEventListener('pointermove',e=>{
 const old=pointers.get(e.pointerId);if(!old)return;pointers.set(e.pointerId,[e.clientX,e.clientY]);
 if(pointers.size>1){const a=[...pointers.values()],d=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);if(lastPinch&&d>0)radius=Math.max(3.4,Math.min(15,radius*lastPinch/d));lastPinch=d}
 else if(pinchGesture){return}
 else if(dragging){
  const item=items.find(i=>i.instanceId===dragging.id);if(!item)return;const dx=e.clientX-dragging.start[0],dy=e.clientY-dragging.start[1];
  if(dragging.axis===null){const axis=inferAxis(dragging.center,dx,dy);if(axis===null)return;dragging.axis=axis;dragging.startParameter=axisParameter(ray(...dragging.start),dragging.center,axis);showAxis(axis)}
  const axis=dragging.axis,current=axisParameter(ray(e.clientX,e.clientY),dragging.center,axis);let distance;
  if(current!==null&&dragging.startParameter!==null)distance=current-dragging.startParameter;
  else{const s=screenAxis(dragging.center,axis);if(!s)return;distance=(dx*s.unit[0]+dy*s.unit[1])/s.length}
  if(Number.isFinite(distance)){if(dragging.previousDistance===undefined&&Math.abs(distance)>1e-5)activeDirection=Math.sign(distance);dragging.previousDistance=distance;item.position=[...dragging.position];item.position[axis]+=distance;sync()}
 }else{yaw-=(e.clientX-old[0])*.009;pitch=Math.max(.12,Math.min(1.48,pitch+(e.clientY-old[1])*.007))}
 dirty=true;
});
for(const name of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(name,e=>{
 if(!pointers.has(e.pointerId))return;
 if(name==='pointerup'&&orbitStart&&!pinchGesture&&Math.hypot(e.clientX-orbitStart[0],e.clientY-orbitStart[1])<9){selected=null;showAxis(null);sync()}
 if(dragging)commitLayout();pointers.delete(e.pointerId);dragging=null;orbitStart=null;lastPinch=null;canvas.style.cursor='default';if(name==='pointercancel')showAxis(null);if(!pointers.size)pinchGesture=false;dirty=true;
});
canvas.addEventListener('wheel',e=>{e.preventDefault();radius=Math.max(3.4,Math.min(15,radius*Math.exp(e.deltaY*.001)));dirty=true},{passive:false});
$('reverse').onclick=()=>{yaw=.78;pitch=.65;dirty=true};$('top').onclick=()=>{pitch=1.35;dirty=true};
$('walls').onclick=e=>{autoWalls=!autoWalls;e.target.classList.toggle('active',autoWalls);dirty=true};$('roof').onclick=e=>{showRoof=!showRoof;e.target.classList.toggle('active',showRoof);dirty=true};$('reset').onclick=()=>{yaw=-.72;pitch=.62;radius=7.5;dirty=true};
function resize(){let d=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(canvas.clientWidth*d);canvas.height=Math.round(canvas.clientHeight*d);gl.viewport(0,0,canvas.width,canvas.height);dirty=true}addEventListener('resize',resize);if(typeof ResizeObserver!=='undefined')new ResizeObserver(resize).observe(canvas);resize();gl.enable(gl.DEPTH_TEST);gl.clearColor(1,1,1,1);
function draw(objects,m,eye,highlight=false){gl.uniformMatrix4fv(ud,false,m);for(let p of objects){if(hidden(p,eye))continue;if(p.singleSided){gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK)}else gl.disable(gl.CULL_FACE);gl.bindBuffer(gl.ARRAY_BUFFER,p.v);gl.enableVertexAttribArray(ap);gl.vertexAttribPointer(ap,3,gl.FLOAT,false,0,0);gl.bindBuffer(gl.ARRAY_BUFFER,p.n);gl.enableVertexAttribArray(an);gl.vertexAttribPointer(an,3,gl.FLOAT,false,0,0);if(p.uv){gl.bindBuffer(gl.ARRAY_BUFFER,p.uv);gl.enableVertexAttribArray(at);gl.vertexAttribPointer(at,2,gl.FLOAT,false,0,0)}else{gl.disableVertexAttribArray(at);gl.vertexAttrib2f(at,0,0)}if(p.tangent){gl.bindBuffer(gl.ARRAY_BUFFER,p.tangent);gl.enableVertexAttribArray(ag);gl.vertexAttribPointer(ag,4,gl.FLOAT,false,0,0)}else{gl.disableVertexAttribArray(ag);gl.vertexAttrib4f(ag,1,0,0,1)}gl.uniform1i(ugt,p.tangent?1:0);gl.uniform1i(uo,p.originalAppearance?1:0);gl.uniform1i(uh,p.map?1:0);gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,p.map||shadowTexture);gl.uniform1i(ut,1);gl.uniform1i(uhn,p.normalMap&&(p.tangent||normalMapsSupported)?1:0);gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,p.normalMap||shadowTexture);gl.uniform1i(un,2);gl.uniform1f(uns,p.normalStrength??1);gl.uniform1i(uhr,p.roughnessMap?1:0);gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_2D,p.roughnessMap||shadowTexture);gl.uniform1i(urt,3);gl.activeTexture(gl.TEXTURE4);gl.bindTexture(gl.TEXTURE_2D,p.metallicMap||shadowTexture);gl.uniform1i(umt,4);gl.uniform1i(uhm,p.metallicMap?1:0);gl.uniform1f(umetal,p.metallic??0);gl.uniform1f(uk,p.materialKind||0);gl.uniform1f(ur,p.roughness??.8);gl.uniform3fv(uc,highlight&&!p.preserveAppearance?p.color.map(v=>Math.min(1,v*.70+.30)):p.color);drawGeometry(p)}}
// A real directional shadow pass, shared by the room and every movable instance.
function ortho(l,r,b,t,n,f){return new Float32Array([2/(r-l),0,0,0,0,2/(t-b),0,0,0,0,-2/(f-n),0,-(r+l)/(r-l),-(t+b)/(t-b),-(f+n)/(f-n),1])}
let lightMatrix=mul(ortho(-4.8,4.8,-4.8,4.8,.1,22),look([-4.5,9,6],[0,.5,0]));
const shadowProgram=gl.createProgram();gl.attachShader(shadowProgram,shader(gl.VERTEX_SHADER,`attribute vec3 aPosition;uniform mat4 uLight;uniform mat4 uModel;void main(){gl_Position=uLight*uModel*vec4(aPosition,1.);}`));gl.attachShader(shadowProgram,shader(gl.FRAGMENT_SHADER,`precision highp float;void main(){vec3 c=fract(gl_FragCoord.z*vec3(1.,255.,65025.));c-=c.yzz*vec3(1./255.,1./255.,0.);gl_FragColor=vec4(c,1.);}`));gl.linkProgram(shadowProgram);if(!gl.getProgramParameter(shadowProgram,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(shadowProgram));
const sap=gl.getAttribLocation(shadowProgram,'aPosition'),sul=gl.getUniformLocation(shadowProgram,'uLight'),sud=gl.getUniformLocation(shadowProgram,'uModel');
const shadowTexture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,shadowTexture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,2048,2048,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
const shadowBuffer=gl.createFramebuffer(),shadowDepth=gl.createRenderbuffer();gl.bindFramebuffer(gl.FRAMEBUFFER,shadowBuffer);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,shadowTexture,0);gl.bindRenderbuffer(gl.RENDERBUFFER,shadowDepth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,2048,2048);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,shadowDepth);if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw Error('Unable to create shadow buffer.');gl.bindFramebuffer(gl.FRAMEBUFFER,null);
function hidden(p,eye){if(p.wall==='scan')return autoWalls&&dot(p.cutawayNormal,sub(eye,p.cutawayCenter))>0;return(p.wall==='roof'&&!showRoof)||(autoWalls&&p.wall&&((p.wall==='front'&&eye[2]>0)||(p.wall==='back'&&eye[2]<0)||(p.wall==='left'&&eye[0]<0)||(p.wall==='right'&&eye[0]>0)))}
function shadowDraw(objects,m,eye){gl.uniformMatrix4fv(sud,false,m);for(let p of objects){if(hidden(p,eye)||p.materialKind===4)continue;gl.disable(gl.CULL_FACE);gl.bindBuffer(gl.ARRAY_BUFFER,p.v);gl.enableVertexAttribArray(sap);gl.vertexAttribPointer(sap,3,gl.FLOAT,false,0,0);drawGeometry(p)}}
function render(){if(dirty){dirty=false;let eye=camera();gl.bindFramebuffer(gl.FRAMEBUFFER,shadowBuffer);gl.viewport(0,0,2048,2048);gl.clearColor(1,1,1,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(shadowProgram);gl.disableVertexAttribArray(an);gl.disableVertexAttribArray(at);gl.disableVertexAttribArray(ag);gl.uniformMatrix4fv(sul,false,lightMatrix);shadowDraw(roomObjects,identity,eye);for(let i of items)shadowDraw(assetMap.get(i.assetId).objects,model(i),eye);
gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(1,1,1,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(program);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,shadowTexture);gl.uniform1i(us,0);gl.uniform3fv(ue,eye);gl.uniformMatrix4fv(ul,false,lightMatrix);gl.uniformMatrix4fv(um,false,mul(perspective(.73,canvas.width/canvas.height,.1,100),look(eye,sceneTarget)));draw(roomObjects,identity,eye);for(let i of items)draw(assetMap.get(i.assetId).objects,model(i),eye,i.instanceId===selected);drawAxisGizmo(eye);positionLabels()}requestAnimationFrame(render)}
// Scanned-room adapter. Raw RoomPlan geometry stays immutable; editor items carry changes.
let scannedSource=null;
let activeRoomParts=room.parts;
let sceneTarget=[0,.95,0];
const rotationHUD=document.getElementById('rotationHUD');
function updateRotationHUD(){if(rotationHUD)rotationHUD.hidden=!(furnitureMoveEnabled&&chosen())}
const rotateStep=degrees=>{if(!furnitureMoveEnabled||!chosen())return;dragging=null;showAxis(null);rotate(degrees)};
if(rotationHUD){document.getElementById('rotateLeft').onclick=()=>rotateStep(-15);document.getElementById('rotateRight').onclick=()=>rotateStep(15)}
function matrixPoint(m,p){return[0,1,2].map(k=>m[k]*p[0]+m[4+k]*p[1]+m[8+k]*p[2]+m[12+k])}
function inversePlanePoint(m,p){const q=sub(p,m.slice(12,15));return[dot(q,m.slice(0,3)),dot(q,m.slice(4,7)),dot(q,m.slice(8,11))]}
function polygonArea(p){return p.reduce((sum,a,i)=>{const b=p[(i+1)%p.length];return sum+a[0]*b[1]-b[0]*a[1]},0)/2}
function triangulate(poly){
 const ids=poly.map((_,i)=>i);if(polygonArea(poly)<0)ids.reverse();const faces=[];
 const cross2=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
 const inside=(p,a,b,c)=>cross2(a,b,p)>=-1e-9&&cross2(b,c,p)>=-1e-9&&cross2(c,a,p)>=-1e-9;
 let attempts=0;while(ids.length>3&&attempts++<poly.length*poly.length){let found=false;for(let i=0;i<ids.length;i++){const a=ids[(i+ids.length-1)%ids.length],b=ids[i],c=ids[(i+1)%ids.length];if(cross2(poly[a],poly[b],poly[c])<=1e-10)continue;if(ids.some(k=>k!==a&&k!==b&&k!==c&&inside(poly[k],poly[a],poly[b],poly[c])))continue;faces.push([a,b,c]);ids.splice(i,1);found=true;break}if(!found)break}
 if(ids.length===3)faces.push([...ids]);if(faces.length!==poly.length-2)throw Error('Unsupported room surface outline. Try scanning again.');return faces;
}
function clipPolygon(poly,axis,value,keepGreater){
 const out=[];for(let i=0;i<poly.length;i++){const a=poly[i],b=poly[(i+1)%poly.length],aa=keepGreater?a[axis]>=value-1e-8:a[axis]<=value+1e-8,bb=keepGreater?b[axis]>=value-1e-8:b[axis]<=value+1e-8;if(aa)out.push(a);if(aa!==bb){const t=(value-a[axis])/(b[axis]-a[axis]);out.push([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])])}}
 // Remove clipping duplicates/collinear vertices before ear clipping.
 const clean=out.filter((p,i)=>!i||Math.hypot(p[0]-out[i-1][0],p[1]-out[i-1][1])>1e-7);
 if(clean.length>1&&Math.hypot(clean[0][0]-clean.at(-1)[0],clean[0][1]-clean.at(-1)[1])<1e-7)clean.pop();
 return clean.filter((p,i)=>{const a=clean[(i+clean.length-1)%clean.length],b=clean[(i+1)%clean.length];return Math.abs((p[0]-a[0])*(b[1]-p[1])-(p[1]-a[1])*(b[0]-p[0]))>1e-9});
}
function boxPart(name,center,size,color=[.72,.69,.64],materialKind=0){
 const vertices=[];for(let mask=0;mask<8;mask++)vertices.push(center.map((p,k)=>p+((mask&(1<<k))?1:-1)*size[k]/2));
 return{name,vertices,faces:[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],color,wall:null,materialKind,roughness:.8};
}
function surfacePart(name,poly,m,thickness,color,extra={}){
 if(poly.length<3||Math.abs(polygonArea(poly))<1e-7)return null;
 if(polygonArea(poly)<0)poly=[...poly].reverse();
 const n=poly.length,tri=triangulate(poly),vertices=[...poly.map(p=>matrixPoint(m,[...p,-thickness/2])),...poly.map(p=>matrixPoint(m,[...p,thickness/2]))];
 const faces=[...tri.map(f=>[...f].reverse()),...tri.map(f=>f.map(i=>i+n))];for(let i=0;i<n;i++){const j=(i+1)%n;faces.push([i,j,j+n,i+n])}
 return{name,vertices,faces,color,wall:null,materialKind:0,roughness:.9,...extra};
}
function localOutline(e){return e.polygonCorners?.length>=3?e.polygonCorners.map(p=>[p.x,p.y]):[[-e.dimensions.width/2,-e.dimensions.height/2],[e.dimensions.width/2,-e.dimensions.height/2],[e.dimensions.width/2,e.dimensions.height/2],[-e.dimensions.width/2,e.dimensions.height/2]]}
function boundsOf(parts){const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(const part of parts)eachVertex(part,v=>{for(let k=0;k<3;k++){lo[k]=Math.min(lo[k],v[k]);hi[k]=Math.max(hi[k],v[k])}});if(!Number.isFinite(lo[0]))throw Error('No room geometry was found.');return{lo,hi,corners:Array.from({length:8},(_,mask)=>lo.map((v,k)=>(mask&(1<<k))?hi[k]:v))}}
function validateScan(doc){
 if(doc?.schemaVersion!==1||doc.units!=='meters'||doc.coordinateSystem!=='right-handed-y-up'||doc.transformLayout!=='column-major')throw Error('Unsupported room coordinates.');
 const groups=['walls','doors','windows','openings','floors','objects'];for(const k of groups)if(!Array.isArray(doc[k]))throw Error('Incomplete room data.');
 const all=groups.flatMap(k=>doc[k]);if(doc.objects.length>100||all.length-doc.objects.length>500||!all.length)throw Error('Room data is too large or empty.');
 const ids=new Set();for(const e of all){if(typeof e.id!=='string'||!e.id||e.id.length>120||ids.has(e.id))throw Error('Invalid room object ID.');ids.add(e.id);if(!Array.isArray(e.transform)||e.transform.length!==16||!e.transform.every(x=>Number.isFinite(x)&&Math.abs(x)<10000)||Math.abs(e.transform[3])>.01||Math.abs(e.transform[7])>.01||Math.abs(e.transform[11])>.01||Math.abs(e.transform[15]-1)>.01)throw Error('Invalid room transform.');const d=e.dimensions;if(!d||![d.width,d.height,d.depth].every(x=>Number.isFinite(x)&&x>=0&&x<100)||![d.width,d.height,d.depth].some(x=>x>0))throw Error('Invalid room dimensions.');if(e.polygonCorners!=null&&(!Array.isArray(e.polygonCorners)||e.polygonCorners.length>100||!e.polygonCorners.every(p=>[p.x,p.y,p.z].every(x=>Number.isFinite(x)&&Math.abs(x)<100))))throw Error('Invalid surface outline.')}
}
function buildRoomParts(doc){
 const raw=doc.walls.map(w=>surfacePart('Wall',localOutline(w),w.transform,.08,[.91,.90,.87])).filter(Boolean);
 for(const e of doc.objects)raw.push(boxPart('Bounds',e.transform.slice(12,15),[e.dimensions.width,e.dimensions.height,e.dimensions.depth]));
 if(!raw.length)for(const f of doc.floors)raw.push(surfacePart('Floor',localOutline(f),f.transform,.04,[.78,.72,.63]));
 const rawBounds=boundsOf(raw.filter(Boolean)),center=rawBounds.lo.map((v,k)=>(v+rawBounds.hi[k])/2),parts=[];
 for(const w of doc.walls){
  const poly=localOutline(w),m=w.transform,xmin=Math.min(...poly.map(p=>p[0])),xmax=Math.max(...poly.map(p=>p[0])),ymin=Math.min(...poly.map(p=>p[1])),ymax=Math.max(...poly.map(p=>p[1]));
  let normal=norm([m[8],0,m[10]]);if(dot(normal,sub(m.slice(12,15),center))<0)normal=normal.map(x=>-x);
  const extra={wall:'scan',cutawayNormal:normal,cutawayCenter:m.slice(12,15)};
  const holes=[];for(const h of [...doc.doors,...doc.windows,...doc.openings]){
   const hm=h.transform,parallel=Math.abs(dot(norm(m.slice(8,11)),norm(hm.slice(8,11))));if(parallel<.94)continue;
   const c=inversePlanePoint(m,hm.slice(12,15));if(Math.abs(c[2])>.22)continue;
   const corners=localOutline(h).map(p=>inversePlanePoint(m,matrixPoint(hm,[...p,0])));
   const r=[Math.max(xmin,Math.min(...corners.map(p=>p[0]))),Math.min(xmax,Math.max(...corners.map(p=>p[0]))),Math.max(ymin,Math.min(...corners.map(p=>p[1]))),Math.min(ymax,Math.max(...corners.map(p=>p[1])))];
   if(r[1]-r[0]>.01&&r[3]-r[2]>.01)holes.push(r);
  }
  const xs=[...new Set([xmin,xmax,...holes.flatMap(r=>r.slice(0,2))])].sort((a,b)=>a-b),ys=[...new Set([ymin,ymax,...holes.flatMap(r=>r.slice(2))])].sort((a,b)=>a-b);if(xs.length*ys.length>1024||parts.length>4000)throw Error('Room surface is too complex to preview. Try a shorter scan.');
  for(let x=0;x<xs.length-1;x++)for(let y=0;y<ys.length-1;y++){
   const mid=[(xs[x]+xs[x+1])/2,(ys[y]+ys[y+1])/2];if(holes.some(r=>mid[0]>r[0]&&mid[0]<r[1]&&mid[1]>r[2]&&mid[1]<r[3]))continue;
   let clipped=poly;for(const [axis,value,greater]of[[0,xs[x],true],[0,xs[x+1],false],[1,ys[y],true],[1,ys[y+1],false]]){clipped=clipPolygon(clipped,axis,value,greater);if(clipped.length<3)break}
   const p=surfacePart('Wall '+w.id,clipped,m,.08,[.91,.90,.87],extra);if(p)parts.push(p);
  }
 }
 for(const e of [...doc.doors,...doc.windows]){
  const p=surfacePart(e.kind,localOutline(e),e.transform,e.kind==='window'?.025:.045,e.kind==='window'?[.66,.79,.83]:[.66,.51,.37]);if(p)parts.push(p);
 }
 if(doc.floors.length){for(const f of doc.floors){const p=surfacePart('Floor',localOutline(f),f.transform,.035,[.76,.69,.58],{materialKind:1});if(p)parts.push(p)}}
 else{const{lo,hi}=rawBounds;parts.push(boxPart('Estimated floor',[(lo[0]+hi[0])/2,lo[1]-.025,(lo[2]+hi[2])/2],[Math.max(.2,hi[0]-lo[0]),.05,Math.max(.2,hi[2]-lo[2])],[.76,.69,.58],1))}
 return parts;
}
function genericFurniture(category,d){
 const[w,h,z]=d,p=[],wood=[.56,.40,.28],fabric=[.80,.77,.70],light=[.9,.89,.86];const box=(name,c,s,color=fabric)=>p.push(boxPart(name,c,s,color));
 switch(category){
 case 'sofa':box('Seat',[0,-.12*h,.07*z],[w,.43*h,.84*z]);box('Back',[0,.25*h,-.4*z],[w,.5*h,.2*z]);for(const sign of [-1,1])box('Arm',[sign*.44*w,.07*h,0],[.12*w,.65*h,z]);break;
 case 'table':box('Top',[0,.44*h,0],[w,.12*h,z],wood);for(const x of [-1,1])for(const zz of [-1,1])box('Leg',[x*.42*w,-.06*h,zz*.42*z],[.09*w,.88*h,.09*z],wood);break;
 case 'storage':case 'refrigerator':box('Cabinet',[0,0,0],[w,h,z],category==='storage'?wood:light);for(const y of [-.22,.22])box('Handle',[.31*w,y*h,.51*z],[.035*w,.16*h,.025*z],[.3,.31,.32]);break;
 case 'television':box('Screen',[0,.07*h,0],[w,.86*h,.24*z],[.12,.13,.14]);box('Stand',[0,-.43*h,0],[.5*w,.14*h,z],[.25,.25,.25]);break;
 case 'sink':box('Basin',[0,.35*h,0],[w,.3*h,z],light);box('Pedestal',[0,-.15*h,0],[.36*w,.7*h,.48*z],light);break;
 case 'toilet':box('Bowl',[0,-.12*h,.15*z],[w,.65*h,.7*z],light);box('Tank',[0,.2*h,-.37*z],[.8*w,.6*h,.26*z],light);break;
 case 'bathtub':box('Base',[0,-.1*h,0],[w,.8*h,z],light);box('Inside',[0,.33*h,0],[.82*w,.12*h,.78*z],[.68,.74,.75]);break;
 default:box('Detected '+category,[0,0,0],d,[.69,.72,.72]);
 }
 return p;
}
function furnitureAsset(e){
 const dims=[e.dimensions.width,e.dimensions.height,e.dimensions.depth].map(x=>Math.max(.03,x)),category=String(e.category||'unknown').toLowerCase();
 const template=['bed','chair'].includes(category)?assetMap.get(category):null;
 const parts=template?template.parts:genericFurniture(category,dims),b=boundsOf(parts),extent=b.lo.map((v,k)=>Math.max(1e-5,b.hi[k]-v)),center=b.lo.map((v,k)=>(v+b.hi[k])/2);
 const normalized=parts.map(p=>({...p,wall:null,vertexNormals:undefined,vertices:p.vertices.map(v=>v.map((x,k)=>(x-center[k])*dims[k]/extent[k]))}));
 return{id:'scan-'+e.id,label:category==='unknown'?'Detected furniture':category.charAt(0).toUpperCase()+category.slice(1),dimensionsMeters:dims,parts:normalized,objects:normalized.map(upload),defaultTransform:{position:e.transform.slice(12,15),yawRadians:Math.atan2(e.transform[8],e.transform[0])},scanned:true};
}
function deleteObjects(objects){for(const p of objects){gl.deleteBuffer(p.v);gl.deleteBuffer(p.n)}}
function setRoomGeometry(parts){
 const b=boundsOf(parts);deleteObjects(roomObjects);activeRoomParts=parts;roomObjects=parts.map(upload);roomBounds=b.corners;
 sceneTarget=[(b.lo[0]+b.hi[0])/2,(b.lo[1]+b.hi[1])/2,(b.lo[2]+b.hi[2])/2];
 const span=Math.max(...b.hi.map((v,k)=>v-b.lo[k]),1),extent=span*.9;
 lightMatrix=mul(ortho(-extent,extent,-extent,extent,.1,span*8),look(sceneTarget.map((v,k)=>v+[-span,span*2,span*1.3][k]),sceneTarget));
 radius=7.5;yaw=-.72;pitch=.62;dirty=true;
}
function clearScannedAssets(){for(const[id,a]of assetMap)if(a.scanned){deleteObjects(a.objects);assetMap.delete(id)}}
function loadScannedRoom(doc){
 validateScan(doc);const parts=buildRoomParts(doc); // Validate/triangulate before replacing the current scene.
 const generated=doc.objects.map(furnitureAsset);clearScannedAssets();setRoomGeometry(parts);
 for(const a of generated)assetMap.set(a.id,a);
 scannedSource=JSON.parse(JSON.stringify(doc));items=generated.map(a=>({instanceId:a.id.slice(5),assetId:a.id,position:[...a.defaultTransform.position],yawRadians:a.defaultTransform.yawRadians}));
 selected=null;dragging=null;pointers.clear();showAxis(null);sync();return null;
}
function restoreDemoGeometry(){if(scannedSource){clearScannedAssets();setRoomGeometry(room.parts);sceneTarget=[0,.95,0];scannedSource=null}}

// Native product bridge and small in-room furniture controls.
let bridgeActive=false,showNames=true;
const textureCache=new Map(),labelNodes=new Map();
const style=document.createElement('style');style.textContent=`
#furnitureTools{position:absolute;top:4px;left:6px;right:6px;display:flex;justify-content:space-between;gap:6px;z-index:20;pointer-events:none}
#furnitureTools>*{pointer-events:auto;font:11px -apple-system,sans-serif;background:#fffffff0;border:1px solid #e5ded5;border-radius:12px;padding:5px 8px;max-width:68%}
#selectedFurniture{position:absolute;bottom:5px;left:6px;right:6px;background:#fffffff2;border:1px solid #e5ded5;border-radius:14px;padding:6px;display:flex;align-items:center;gap:4px;z-index:20;box-shadow:0 2px 10px #392d2510}
#selectedFurniture[hidden]{display:none}#selectedFurniture input{min-width:0;flex:1;border:0;background:transparent;font:12px -apple-system,sans-serif;padding:4px}
#selectedFurniture button{font:12px -apple-system,sans-serif;padding:5px 8px;border:0;border-radius:9px;background:#f4f0ea;min-height:28px}#selectedFurniture .remove{color:#b7382c}
#furnitureLabels{position:absolute;inset:0;pointer-events:none;z-index:12}.furnitureLabel{position:absolute;max-width:145px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;transform:translate(-50%,-50%);border:1px solid #e3dbd1;border-radius:8px;padding:3px 6px;background:#ffffffe8;color:#4a352b;font:10px -apple-system,sans-serif;pointer-events:auto;min-width:0}.furnitureLabel.selected{background:#4a352b;color:white;border-color:#4a352b}
#axisIndicator{bottom:51px}#rotationHUD{display:none!important}
`;document.head.append(style);
const tools=document.createElement('div');tools.id='furnitureTools';
const nameToggle=document.createElement('button');nameToggle.textContent='Names on';nameToggle.onclick=()=>{showNames=!showNames;nameToggle.textContent=showNames?'Names on':'Names off';dirty=true};tools.append(nameToggle);document.body.append(tools);
const toolbar=document.createElement('div');toolbar.id='selectedFurniture';toolbar.hidden=true;
const nameInput=document.createElement('input');nameInput.maxLength=80;nameInput.setAttribute('aria-label','Furniture name');nameInput.placeholder='Furniture name';nameInput.onchange=()=>renameSelected(nameInput.value);nameInput.onkeydown=e=>{if(e.key==='Enter')nameInput.blur()};
const turnLeft=document.createElement('button');turnLeft.textContent='↶';turnLeft.setAttribute('aria-label','Rotate furniture left');turnLeft.onclick=()=>{rotate(-15);commitLayout()};
const turnRight=document.createElement('button');turnRight.textContent='↷';turnRight.setAttribute('aria-label','Rotate furniture right');turnRight.onclick=()=>{rotate(15);commitLayout()};
const removeButton=document.createElement('button');removeButton.textContent='Remove';removeButton.className='remove';removeButton.onclick=()=>removeSelected();toolbar.append(nameInput,turnLeft,turnRight,removeButton);document.body.append(toolbar);
const labels=document.createElement('div');labels.id='furnitureLabels';document.body.append(labels);
function itemName(i){const raw=scannedSource?.objects.find(e=>'scan-'+e.id===i.assetId);return i.label||raw?.label||assetMap.get(i.assetId)?.label||'Furniture'}
function updateFurnitureUI(){
 const i=chosen();toolbar.hidden=!i;if(i&&document.activeElement!==nameInput)nameInput.value=itemName(i);
 const live=new Set(items.map(i=>i.instanceId));for(const[id,node]of labelNodes)if(!live.has(id)){node.remove();labelNodes.delete(id)}
 for(const item of items){let node=labelNodes.get(item.instanceId);if(!node){node=document.createElement('button');node.className='furnitureLabel';node.onclick=()=>selectFurniture(item.instanceId);labels.append(node);labelNodes.set(item.instanceId,node)}node.textContent=itemName(item);node.classList.toggle('selected',item.instanceId===selected)}
}
function positionLabels(){for(const item of items){const node=labelNodes.get(item.instanceId),p=project(boundsCenter(item));if(!node)continue;const visible=showNames&&p&&p[0]>0&&p[0]<innerWidth&&p[1]>37&&p[1]<innerHeight-(chosen()?52:8);node.hidden=!visible;if(visible){node.style.left=p[0]+'px';node.style.top=p[1]+'px'}}}
function selectFurniture(id){if(id&&!furnitureMoveEnabled)setFurnitureMoveEnabled(true);selected=id&&items.some(i=>i.instanceId===id)?id:null;showAxis(null);sync();commitLayout()}
function renameSelected(value){const i=chosen();if(!i)return;const name=Array.from(String(value).trim()).slice(0,80).join('');if(!name){nameInput.value=itemName(i);return}i.label=name;sync();commitLayout()}
function removeSelected(){if(!chosen())return;items=items.filter(i=>i.instanceId!==selected);selected=null;showAxis(null);sync();commitLayout()}
function post(type,extra={}){window.webkit?.messageHandlers?.furniture?.postMessage({type,furnitureMoveEnabled,...extra})}
function commitLayout(){if(bridgeActive)post('layout',{layout:layout()})}
async function texture(url,key){
 if(!url)return null;if(textureCache.has(key))return textureCache.get(key);
 const promise=new Promise((resolve,reject)=>{const image=new Image(),timeout=setTimeout(()=>reject(Error('Chair texture timed out')),15000);image.onload=()=>{clearTimeout(timeout);const map=gl.createTexture();gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,map);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL,gl.NONE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);const powerOfTwo=n=>(n&(n-1))===0,wrap=powerOfTwo(image.width)&&powerOfTwo(image.height)?gl.REPEAT:gl.CLAMP_TO_EDGE;gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,wrap);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,wrap);if(wrap===gl.REPEAT){gl.generateMipmap(gl.TEXTURE_2D);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR)}resolve(map)};image.onerror=()=>{clearTimeout(timeout);reject(Error('Chair texture could not be loaded'))};image.src=url});textureCache.set(key,promise);try{return await promise}catch(error){textureCache.delete(key);throw error}
}
async function register(payload){
 const allowed=['sofa_007_brown','sofa_027_brown','sofa_028_brown'];if(!payload||!allowed.includes(payload.id)||!Array.isArray(payload.parts)||!payload.parts.length)throw Error('Unknown chair model');if(assetMap.has(payload.id))return true;
 const objects=[];try{for(const [index,part] of payload.parts.entries()){const object=upload(part);objects.push(object);object.preserveAppearance=true;object.originalAppearance=true;object.map=await texture(part.texture,`${payload.id}:${index}:color`);object.normalMap=await texture(part.normalTexture,`${payload.id}:${index}:normal`);object.roughnessMap=await texture(part.roughnessTexture,`${payload.id}:${index}:roughness`);object.metallicMap=await texture(part.metallicTexture,`${payload.id}:${index}:metallic`)}}catch(error){for(const o of objects){gl.deleteBuffer(o.v);gl.deleteBuffer(o.n);if(o.uv)gl.deleteBuffer(o.uv);if(o.tangent)gl.deleteBuffer(o.tangent);if(o.indexBuffer)gl.deleteBuffer(o.indexBuffer)}throw error}
 assetMap.set(payload.id,{id:payload.id,productID:payload.id,label:payload.label,parts:objects,objects,defaultTransform:{position:[0,0,0],yawRadians:0},bounds:payload.bounds,optional:true});dirty=true;return true
}
function footprint(assetId,position,yawRadians=0){const asset=assetMap.get(assetId),b=localBounds(asset),i={position,yawRadians},corners=[];for(const x of[b[0][0],b[1][0]])for(const z of[b[0][2],b[1][2]])corners.push(world([x,0,z],i));return{low:[Math.min(...corners.map(v=>v[0])),Math.min(...corners.map(v=>v[2]))],high:[Math.max(...corners.map(v=>v[0])),Math.max(...corners.map(v=>v[2]))]}}
function spawn(id){
 const b=boundsOf(activeRoomParts),center=scannedSource?sceneTarget:[0,0,0],floorParts=activeRoomParts.filter(p=>p.name.toLowerCase().includes('floor'));
 const floorY=scannedSource&&floorParts.length?boundsOf(floorParts).hi[1]:0;
 const candidates=[[-.35,.5],[-.5,-.45],[.35,.5],[0,0],[-.7,1.05],[.65,-1.1]].map(p=>[p[0]+center[0],floorY,p[1]+center[2]]);
 for(const p of candidates){const a=footprint(id,p);if(a.low[0]<b.lo[0]||a.high[0]>b.hi[0]||a.low[1]<b.lo[2]||a.high[1]>b.hi[2])continue;const collision=items.some(i=>{if(['rug','wall_shelves','window_curtains','closet_shelf'].includes(i.assetId))return false;const c=footprint(i.assetId,i.position,i.yawRadians);return a.low.every((v,k)=>v<c.high[k]-.03)&&a.high.every((v,k)=>v>c.low[k]+.03)});if(!collision)return p}return candidates[0]
}
function tryProduct(id){const asset=assetMap.get(id);if(!asset?.productID)throw Error('3D chair is not loaded');if(!furnitureMoveEnabled)setFurnitureMoveEnabled(true);let item=items.find(i=>i.productID===id);if(!item){item={instanceId:'product:'+id,assetId:id,productID:id,label:asset.label,position:spawn(id),yawRadians:0};items.push(item)}selected=item.instanceId;showAxis(null);sync();commitLayout();return layout()}
function removeProduct(id){items=items.filter(i=>i.productID!==id);if(!chosen())selected=null;showAxis(null);sync();commitLayout();return layout()}
function resetFurniture(){if(scannedSource)loadScannedRoom(JSON.parse(JSON.stringify(scannedSource)));else{items=[];selected=null;for(const asset of assets)if(!asset.optional)add(asset.id)}selected=null;showAxis(null);sync();commitLayout();return layout()}
window.tuckFurniture={register,tryProduct,removeProduct,restore:data=>{loadLayout(data);return layout()},reset:resetFurniture,layout,select:selectFurniture,rename:renameSelected,removeSelected,rotate:degrees=>{if(!Number.isFinite(degrees))throw Error('Invalid angle');rotate(degrees);commitLayout();return layout()}};
canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();post('error',{message:'The 3D preview was interrupted. Close and reopen the app to reload it.'})});


// Open directly into the furnished scene so visual quality is immediately visible.
for(let a of assets)if(!a.optional)add(a.id);selected=null;sync();message('Your room is ready. Drag to explore.');render();
// Chat uses current editor transforms, including unsaved moves and removals.
function chatGeometry(id,category,label,confidence,parts,pose){
 const local=boundsOf(parts),corners=local.corners.map(v=>world(v,pose));
 const lo=[0,1,2].map(k=>Math.min(...corners.map(v=>v[k]))),hi=[0,1,2].map(k=>Math.max(...corners.map(v=>v[k])));
 return{id,category,label:label||null,confidence:confidence||null,dimensionsMeters:local.hi.map((v,k)=>v-local.lo[k]),centerMeters:lo.map((v,k)=>(v+hi[k])/2),yawRadians:pose.yawRadians,worldCornersMeters:corners,boundsMeters:{min:lo,max:hi}};
}
function chatContext(){
 const objects=items.map(i=>{const a=assetMap.get(i.assetId),e=scannedSource?.objects.find(e=>'scan-'+e.id===i.assetId);return chatGeometry(i.instanceId,e?.category||i.assetId,i.label||e?.label||a.label,e?.confidence,a.parts,i)});
 const identityPose={position:[0,0,0],yawRadians:0};
 const structures=scannedSource?['walls','doors','windows','openings','floors'].flatMap(kind=>(scannedSource[kind]||[]).map(e=>{
   const d=e.dimensions,t=e.transform,corners=[];
   for(const x of [-d.width/2,d.width/2])for(const y of [-d.height/2,d.height/2])for(const z of [-d.depth/2,d.depth/2])corners.push([t[0]*x+t[4]*y+t[8]*z+t[12],t[1]*x+t[5]*y+t[9]*z+t[13],t[2]*x+t[6]*y+t[10]*z+t[14]]);
   const lo=[0,1,2].map(k=>Math.min(...corners.map(v=>v[k]))),hi=[0,1,2].map(k=>Math.max(...corners.map(v=>v[k])));
   return{id:e.id,category:e.category,label:e.label||null,confidence:e.confidence||null,dimensionsMeters:[d.width,d.height,d.depth],centerMeters:[t[12],t[13],t[14]],yawRadians:null,worldCornersMeters:corners,boundsMeters:{min:lo,max:hi}};
 })):room.parts.map((p,k)=>chatGeometry('sample-structure-'+k,'structure',null,null,[p],identityPose));
 return{roomID:'editor',roomName:'Room',revision:'pending',source:scannedSource?'scan_editor':'sample_editor',units:'meters',coordinateSystem:'right-handed-y-up',selectedObjectID:selected||null,objects,structures};
}
window.tuckEditor={chatContext,add,layout,loadLayout,loadScannedRoom,rotateSelected:rotateStep,setFurnitureMoveEnabled,select:id=>{selected=id;showAxis(null);sync()},setTransform:(id,position,yawRadians)=>{let i=items.find(i=>i.instanceId===id);if(!i||!Array.isArray(position)||position.length!==3||!position.every(Number.isFinite)||!Number.isFinite(yawRadians))throw Error('Invalid transform');i.position=[...position];i.yawRadians=yawRadians;sync()},assets,room,pick,ray,world,model,
project,boundsCenter,screenAxis,inferAxis,axisParameter,gizmoTransform,furnitureAxisLengths,
interactionState:()=>({sourceRoomID:scannedSource?.id??null,furnitureMoveEnabled,selected,axis:activeAxis,direction:activeDirection,dragging:dragging?{id:dragging.id,axis:dragging.axis}:null,camera:{yaw,pitch,radius}}),
setCamera:(y,p,r)=>{yaw=y;pitch=p;radius=r;showAxis(null);dirty=true}};
bridgeActive=true;post('ready',{layout:layout()});
