// ═══════════════════════════════════════════════════════════════════
//  Sentient Ferro-Silicate Swarm
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            particle-swarm, SDF-attraction, liquid-chrome, iridescence,
//            upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: world-scale silicate assembly breath; quartz facet crystallization of locked beads; Si-O bond struts between locked neighbours; curl-advected wake in the temporal smear
//  A packing: ACES display RGBA (alpha = swarm occupancy); C read back as display RGB
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config      : vec4<f32>,
  zoom_config : vec4<f32>,
  zoom_params : vec4<f32>,
  ripples     : array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler                : sampler;
@group(0) @binding(1) var readTexture              : texture_2d<f32>;
@group(0) @binding(2) var writeTexture             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u               : Uniforms;
@group(0) @binding(4) var readDepthTexture         : texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler    : sampler;
@group(0) @binding(6) var writeDepthTexture        : texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC             : texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer : array<f32>;
@group(0) @binding(11) var comparison_sampler      : sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer : array<vec4<f32>>;

const PI : f32 = 3.14159265358979323846;

fn hash2(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(0.1031, 0.1030));
  q += dot(q, q + 33.33);
  return fract((q.x + q.y) * q.x);
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i + vec2<f32>(0,0)), hash2(i + vec2<f32>(1,0)), u.x),
    mix(hash2(i + vec2<f32>(0,1)), hash2(i + vec2<f32>(1,1)), u.x),
    u.y);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(i+vec3<f32>(0,0,0)), hash3(i+vec3<f32>(1,0,0)), u.x),
        mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
    mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
        mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y),
    u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise3(pp);
    pp = pp * 2.03 + vec3<f32>(1.7, 3.1, 5.3);
    a *= 0.5;
  }
  return v;
}

fn curlNoise(p: vec3<f32>, time: f32) -> vec3<f32> {
  let eps = 0.01;
  let n1 = noise3(p + vec3<f32>(eps, 0.0, 0.0) + time);
  let n2 = noise3(p - vec3<f32>(eps, 0.0, 0.0) + time);
  let n3 = noise3(p + vec3<f32>(0.0, eps, 0.0) + time);
  let n4 = noise3(p - vec3<f32>(0.0, eps, 0.0) + time);
  let n5 = noise3(p + vec3<f32>(0.0, 0.0, eps) + time);
  let n6 = noise3(p - vec3<f32>(0.0, 0.0, eps) + time);
  return vec3<f32>(
    (n4 - n3) / (2.0 * eps),
    (n1 - n2) / (2.0 * eps),
    (n6 - n5) / (2.0 * eps)
  );
}

fn kIFS(p: vec3<f32>, time: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  for(var i = 0; i < 6; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    if(z.y + z.z < 0.0) { let t = -z.z; z.z = z.y; z.y = t; }
    z = z * 2.1 - vec3<f32>(1.1, 1.1, 1.1);
    dr = dr * 2.1;
  }
  return length(z) / abs(dr);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

fn rot(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn bass_env(prev: f32, curr: f32, att: f32, rel: f32) -> f32 {
  if(curr > prev) { return mix(prev, curr, att); }
  else { return mix(prev, curr, rel); }
}

// SDF for brutalist target geometry
fn brutalistSDF(p: vec3<f32>, time: f32) -> f32 {
  let pp = p;
  let box = max(abs(pp.x) - 0.8, max(abs(pp.y) - 1.2, abs(pp.z) - 0.8));
  let col1 = length(max(abs(pp - vec3<f32>(0.4, 0.5, 0.0)) - vec3<f32>(0.3, 0.6, 0.3), vec3<f32>(0.0)));
  let col2 = length(max(abs(pp - vec3<f32>(-0.4, -0.3, 0.0)) - vec3<f32>(0.25, 0.4, 0.25), vec3<f32>(0.0)));
  let structure = min(box, min(col1, col2));
  // Add KIFS fractal detail
  let frac = kIFS(pp * 1.5, time) * 0.2;
  return smin(structure, frac, 0.5);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 1: world-scale silicate assembly ─────────────────────────
// The brutalist SDF is sampled at the cell's WORLD centre (slowly rotating,
// sliding slice) so the swarm as a whole reads the building's silhouette.
// `grow` breathes the iso-level: assemble (core -> full block) / dissolve.
fn cellLockRaw(cid: vec2<f32>, gridScale: f32, time: f32, grow: f32) -> f32 {
  let wc = (cid + 0.5) * gridScale * 3.0;
  let a = time * 0.12;
  let wp = vec3<f32>(wc.x * cos(a), wc.y, wc.x * sin(a) + 0.3 * sin(time * 0.07));
  let d = brutalistSDF(wp, time);
  return smoothstep(0.06, -0.06, d - grow);
}

// Same per-cell jitter HEAD applies to the particle (rnd / hash2(cellId + 1)).
fn cellOffset(cid: vec2<f32>, time: f32) -> vec2<f32> {
  return vec2<f32>((hash2(cid + time * 0.01) - 0.5) * 0.3, (hash2(cid + 1.0) - 0.5) * 0.3);
}

fn sdSegment(q: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = q - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
  return length(pa - ba * h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let uv = (fragCoord - 0.5 * res) / res.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let cohesion = u.zoom_params.x;
  let rigidity = u.zoom_params.y;
  let shatterForce = u.zoom_params.z;
  let iridescence = u.zoom_params.w;

  // Bass envelope: HEAD read+wrote engine-reserved extraBuffer[0] from thread
  // (0,0) (illegal write + race, CPU overwrites it). Stateless now.
  let bassSmooth = clamp(bass, 0.0, 2.0);

  // Particle position (simulated via domain repetition)
  let gridScale = 0.15;
  let gridUV = uv / gridScale;
  let cellId = floor(gridUV);
  let cellFract = fract(gridUV) - 0.5;

  // Random offset per cell
  let rnd = hash2(cellId + time * 0.01);
  let rnd3 = hash3(vec3<f32>(cellId, time * 0.05));

  // ── Idea 1: assemble / dissolve breath + lattice lock ──
  // Shatter Force sets how deep the dissolve phase eats the building; bass
  // (x Shatter Force) still blows locked cells loose.
  let assemble = smoothstep(-0.6, 0.6, sin(time * 0.21));
  let grow = mix(-0.30 - 0.25 * shatterForce, 0.12, assemble);
  let unlockAudio = 1.0 - clamp(bassSmooth * shatterForce * 0.6, 0.0, 0.85);
  let lock = cellLockRaw(cellId, gridScale, time, grow) * rigidity * unlockAudio;

  // Particle position in cell (locked particles snap onto the lattice site)
  let jitter = vec2<f32>((rnd - 0.5) * 0.3, (hash2(cellId + 1.0) - 0.5) * 0.3);
  var p = vec3<f32>(
    cellFract.x + jitter.x * (1.0 - lock),
    cellFract.y + jitter.y * (1.0 - lock),
    mix((rnd3 - 0.5) * 0.5, 0.18, lock)
  );

  // Curl noise flow field (frozen inside the assembled crystal)
  let curl = curlNoise(vec3<f32>(p.xy * 2.0, time * 0.2), time);
  p += curl * 0.01 * (1.0 - rigidity) * (1.0 - lock);

  // SDF attraction (swarm seeks brutalist form)
  let sdfD = brutalistSDF(p, time);
  let sdfForce = -normalize(p) * sdfD * rigidity * 0.02;
  p += sdfForce;

  // Audio-reactive shattering
  let shatter = bassSmooth * shatterForce * 2.0;
  p += curlNoise(p * 3.0 + time, time) * shatter;

  // Mouse interaction (magnetic anomaly). HEAD compared a screen-space cursor
  // with cell-local p, i.e. a uniform bias on every cell. The cursor is now
  // mapped into this cell's local frame: nearby beads lean toward it.
  let mouseUV = u.zoom_config.yz;
  let mousePos = (mouseUV - 0.5) * vec2<f32>(res.x / res.y, 1.0);
  let mouseLocal = mousePos / gridScale - cellId - 0.5;
  let beadCentre = -jitter * (1.0 - lock);
  let toMouse = mouseLocal - beadCentre;
  let mouseDist = length(toMouse);
  let mouseForce = toMouse / max(mouseDist, 1e-3) * (1.0 / (1.0 + mouseDist * mouseDist)) * cohesion * 0.5;
  p -= vec3<f32>(mouseForce * (1.0 - 0.7 * lock), 0.0);

  // Calculate particle color based on state
  let vel = length(curl) + shatter * 0.5;
  let density = max(1.0 / (1.0 + abs(sdfD) * 2.0), lock);

  // Liquid chrome base
  var n = normalize(p);

  // ── Idea 2: quartz facet crystallization ──
  // Locked beads trade the round chrome normal for a hexagonal (6 sector x
  // 30-degree tier) quartz facet set; facet edges catch a hard glint.
  let az = atan2(n.y, n.x);
  let el = asin(clamp(n.z, -1.0, 1.0));
  let sector = 2.0 * PI / 6.0;
  let tierH = PI / 6.0;
  let azQ = (floor(az / sector) + 0.5) * sector;
  let elQ = clamp((floor(el / tierH) + 0.5) * tierH, -0.5 * PI, 0.5 * PI);
  let nFacet = vec3<f32>(cos(elQ) * cos(azQ), cos(elQ) * sin(azQ), sin(elQ));
  let edgeAz = smoothstep(0.40, 0.5, abs(fract(az / sector) - 0.5));
  let edgeEl = smoothstep(0.40, 0.5, abs(fract(el / tierH) - 0.5));
  let facetGlint = max(edgeAz, edgeEl) * lock * smoothstep(0.05, 0.15, length(p.xy));
  n = normalize(mix(n, nFacet, lock));

  let viewDir = normalize(vec3<f32>(uv, 1.0));
  let halfDir = normalize(n + viewDir);
  let spec = pow(max(dot(n, halfDir), 0.0), 128.0);
  let fresnel = pow(max(1.0 - abs(dot(n, viewDir)), 0.0), 2.0);

  // Iridescent oil-spill
  let oilHue = fract(dot(p, vec3<f32>(1.0, 2.3, 3.7)) * 0.3 + time * 0.1) * iridescence;
  let oilCol = vec3<f32>(
    0.5 + 0.5 * cos(oilHue * 6.28 + 0.0),
    0.5 + 0.5 * cos(oilHue * 6.28 + 2.09),
    0.5 + 0.5 * cos(oilHue * 6.28 + 4.18)
  );

  // High velocity = heat (neon orange/cyan)
  let heatCol = mix(
    vec3<f32>(0.0, 0.8, 1.0),
    vec3<f32>(1.0, 0.4, 0.0),
    smoothstep(0.3, 1.0, vel)
  );

  // Combine
  var col = mix(vec3<f32>(0.7, 0.72, 0.75), oilCol, fresnel * iridescence);
  col += spec * vec3<f32>(1.0) * 0.5;
  col = mix(col, heatCol, smoothstep(0.2, 0.8, vel) * bassSmooth);

  // Idea 2 (cont.): silicate body is cooler/glassier; edges glint with a
  // little of the oil-spill dispersion.
  col = mix(col, col * vec3<f32>(0.82, 0.9, 1.0), lock * 0.6);
  col += facetGlint * mix(vec3<f32>(0.85, 0.95, 1.0), oilCol, iridescence * 0.5) * 0.9;

  // ── Idea 3: Si-O bond struts between locked 4-neighbours ──
  // Each cell draws its half of the strut from its lattice site to each locked
  // neighbour's site; Swarm Cohesion sets strut thickness.
  var strut = 0.0;
  var strutCore = 0.0;
  let strutW = 0.035 + 0.08 * cohesion;
  for (var k = 0; k < 4; k++) {
    let fk = f32(k);
    let dir = vec2<f32>(round(cos(fk * 0.5 * PI)), round(sin(fk * 0.5 * PI)));
    let nid = cellId + dir;
    let nLock = cellLockRaw(nid, gridScale, time, grow) * rigidity * unlockAudio;
    let nCentre = dir - cellOffset(nid, time) * (1.0 - nLock);
    let dSeg = sdSegment(cellFract, beadCentre, nCentre);
    let bond = min(lock, nLock);
    strut = max(strut, smoothstep(strutW, strutW * 0.3, dSeg) * bond);
    strutCore = max(strutCore, smoothstep(strutW * 0.35, 0.0, dSeg) * bond);
  }
  let outsideBead = smoothstep(0.12, 0.24, length(cellFract - beadCentre));
  strut *= outsideBead;
  strutCore *= outsideBead;
  col = mix(col, vec3<f32>(0.5, 0.58, 0.68) + oilCol * iridescence * 0.15, strut * 0.8);
  col += strutCore * vec3<f32>(0.75, 0.9, 1.0) * 0.6;

  // Density-based brightening
  col *= (0.5 + density * 0.5);

  // Audio bloom
  col += vec3<f32>(0.1, 0.15, 0.2) * bassSmooth * bassSmooth;

  // Chromatic aberration at edges
  let ca = vel * 0.02;
  col.r += noise3(p + vec3<f32>(ca, 0.0, 0.0)) * ca;
  col.b += noise3(p + vec3<f32>(-ca, 0.0, 0.0)) * ca;

  let disp = acesToneMap(col * 1.1);

  // ── Idea 4: curl-advected wake ──
  // Temporal feedback samples C upstream along this cell's curl vector, so
  // free ferro beads stream in wakes; locked crystal (lock -> 1) reads its own
  // texel exactly and stays crisp. C holds display RGB (A below), so the blend
  // is display-space on both sides. HEAD never wrote A, so C was zero and the
  // 0.25 blend rendered the effect at ~25% brightness.
  let wake = clamp(curl.xy * 3.0 * (1.0 - lock), vec2<f32>(-6.0), vec2<f32>(6.0));
  let srcCoord = clamp(vec2<i32>(round(fragCoord - wake)), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
  let prevCol = textureLoad(dataTextureC, srcCoord, 0).rgb;
  let outCol = mix(prevCol, disp, 0.25);

  // Semantic alpha: swarm occupancy (dense beads, locked crystal, struts).
  let occupancy = clamp(0.55 + 0.25 * density + 0.2 * max(lock, strut), 0.0, 1.0);
  let relief = clamp(0.3 * density + 0.5 * lock + 0.2 * strut, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outCol, occupancy));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(outCol, occupancy));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(relief, 0.0, 0.0, 0.0));
}
